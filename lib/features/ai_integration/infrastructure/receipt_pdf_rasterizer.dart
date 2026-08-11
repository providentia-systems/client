import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as image;
import 'package:pdfrx/pdfrx.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/media_acquisition_service.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';

abstract interface class ReceiptPdfDocument {
  bool get isEncrypted;
  int get pageCount;

  Future<ReceiptPdfRenderedPage> renderPage(int pageIndex);

  Future<void> dispose();
}

final class ReceiptPdfRenderedPage {
  ReceiptPdfRenderedPage({
    required Uint8List jpegBytes,
    required this.width,
    required this.height,
  }) : jpegBytes = Uint8List.fromList(jpegBytes);

  final Uint8List jpegBytes;
  final int width;
  final int height;
}

typedef ReceiptPdfDocumentOpener =
    Future<ReceiptPdfDocument> Function(Uint8List bytes);
typedef ReceiptPdfBytePicker =
    Future<({Uint8List bytes, String name})?> Function();

/// Converts a selected receipt PDF into bounded, ordered local JPEG pages.
///
/// The source PDF is never registered in the media store and therefore can
/// never reach an extraction gateway. Only rendered pixels enter the existing
/// preview, edit, sanitization and ordered-consent flow.
final class ReceiptPdfRasterizer {
  ReceiptPdfRasterizer({
    required RegisteredMediaSourceReader sources,
    ReceiptPdfDocumentOpener? openDocument,
    ReceiptPdfBytePicker? pickPdf,
    DateTime Function()? clock,
    int maximumSourceBytes = 25 * 1024 * 1024,
    int maximumPages = 8,
    int maximumRenderedBytes = 40 * 1024 * 1024,
  }) : this._(
         sources,
         openDocument ?? _openPdfrxDocument,
         pickPdf ?? _pickPlatformPdf,
         clock ?? DateTime.now,
         maximumSourceBytes,
         maximumPages,
         maximumRenderedBytes,
       );

  ReceiptPdfRasterizer._(
    this._sources,
    this._openDocument,
    this._pickPdf,
    this._clock,
    this.maximumSourceBytes,
    this.maximumPages,
    this.maximumRenderedBytes,
  );

  final RegisteredMediaSourceReader _sources;
  final ReceiptPdfDocumentOpener _openDocument;
  final ReceiptPdfBytePicker _pickPdf;
  final DateTime Function() _clock;
  final int maximumSourceBytes;
  final int maximumPages;
  final int maximumRenderedBytes;

  Future<List<AiMediaAsset>> choose({required String homeId}) async {
    final selected = await _pickPdf();
    if (selected == null) return const <AiMediaAsset>[];
    return rasterize(
      bytes: selected.bytes,
      homeId: homeId,
      sourceName: selected.name,
    );
  }

  Future<List<AiMediaAsset>> rasterize({
    required Uint8List bytes,
    required String homeId,
    required String sourceName,
  }) async {
    ReceiptPdfDocument? document;
    Uint8List? documentBytes;
    final created = <AiMediaAsset>[];
    MediaAcquisitionException? failure;
    try {
      if (homeId.trim().isEmpty) {
        throw const MediaAcquisitionException(
          'The receipt PDF does not belong to an active household.',
        );
      }
      if (!sourceName.toLowerCase().endsWith('.pdf')) {
        throw const MediaAcquisitionException(
          'Choose a PDF file for receipt document intake.',
        );
      }
      _validateEnvelope(bytes);
      documentBytes = Uint8List.fromList(bytes);
      document = await _openDocument(documentBytes);
      if (document.isEncrypted) {
        throw const MediaAcquisitionException(
          'Password-protected receipt PDFs are not supported.',
        );
      }
      if (document.pageCount < 1 || document.pageCount > maximumPages) {
        throw const MediaAcquisitionException(
          'Receipt PDFs must contain between 1 and 8 pages.',
        );
      }
      var totalBytes = 0;
      for (var index = 0; index < document.pageCount; index++) {
        final rendered = await document.renderPage(index);
        if (rendered.width < 1 ||
            rendered.height < 1 ||
            rendered.width > 2400 ||
            rendered.height > 2400 ||
            rendered.jpegBytes.length < 16) {
          throw const MediaAcquisitionException(
            'A receipt PDF page could not be rendered safely.',
          );
        }
        totalBytes += rendered.jpegBytes.length;
        if (totalBytes > maximumRenderedBytes) {
          throw const MediaAcquisitionException(
            'The rendered receipt pages exceed the safe memory limit.',
          );
        }
        final digest = sha256.convert(rendered.jpegBytes).toString();
        final asset = AiMediaAsset(
          id: 'receipt-pdf-${digest.substring(0, 20)}-page-$index',
          homeId: homeId,
          localReference: 'registered://receipt-pdf-page-${index + 1}',
          purpose: AiExtractionKind.receipt,
          mimeType: 'image/jpeg',
          byteLength: rendered.jpegBytes.length,
          createdAt: _clock().toUtc(),
          pageIndex: index,
          width: rendered.width,
          height: rendered.height,
        );
        _sources.register(asset, rendered.jpegBytes);
        created.add(asset);
      }
    } on MediaAcquisitionException catch (error) {
      failure = error;
    } catch (_) {
      failure = const MediaAcquisitionException(
        'The receipt PDF could not be opened safely.',
      );
    }
    try {
      if (document != null) await document.dispose();
    } catch (_) {
      failure ??= const MediaAcquisitionException(
        'The receipt PDF could not be opened safely.',
      );
    }
    documentBytes?.fillRange(0, documentBytes.length, 0);
    bytes.fillRange(0, bytes.length, 0);
    if (failure case final error?) {
      _remove(created);
      throw error;
    }
    return List<AiMediaAsset>.unmodifiable(created);
  }

  void _validateEnvelope(Uint8List bytes) {
    if (bytes.length < 16 || bytes.length > maximumSourceBytes) {
      throw const MediaAcquisitionException(
        'The receipt PDF is empty or exceeds the 25 MB safety limit.',
      );
    }
    const header = <int>[0x25, 0x50, 0x44, 0x46, 0x2d];
    if (!Iterable<int>.generate(
      header.length,
    ).every((index) => bytes[index] == header[index])) {
      throw const MediaAcquisitionException(
        'The selected file is not a valid receipt PDF.',
      );
    }
    final tailStart = math.max(0, bytes.length - 2048);
    const eof = <int>[0x25, 0x25, 0x45, 0x4f, 0x46];
    var hasEof = false;
    for (
      var offset = tailStart;
      offset <= bytes.length - eof.length;
      offset++
    ) {
      if (Iterable<int>.generate(
        eof.length,
      ).every((index) => bytes[offset + index] == eof[index])) {
        hasEof = true;
        break;
      }
    }
    if (!hasEof) {
      throw const MediaAcquisitionException(
        'The selected receipt PDF is incomplete.',
      );
    }
  }

  void _remove(Iterable<AiMediaAsset> assets) {
    for (final asset in assets) {
      _sources.remove(asset.id);
    }
  }
}

Future<({Uint8List bytes, String name})?> _pickPlatformPdf() async {
  final result = await FilePicker.pickFiles(
    allowMultiple: false,
    withData: true,
    type: FileType.custom,
    allowedExtensions: const <String>['pdf'],
  );
  if (result == null) return null;
  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes == null) {
    throw const MediaAcquisitionException(
      'The receipt PDF could not be read on this device.',
    );
  }
  return (bytes: Uint8List.fromList(bytes), name: file.name);
}

Future<ReceiptPdfDocument> _openPdfrxDocument(Uint8List bytes) async {
  await pdfrxFlutterInitialize();
  final document = await PdfDocument.openData(bytes, sourceName: 'receipt.pdf');
  return _PdfrxReceiptPdfDocument(document);
}

final class _PdfrxReceiptPdfDocument implements ReceiptPdfDocument {
  _PdfrxReceiptPdfDocument(this._document);

  final PdfDocument _document;

  @override
  bool get isEncrypted => _document.isEncrypted;

  @override
  int get pageCount => _document.pages.length;

  @override
  Future<ReceiptPdfRenderedPage> renderPage(int pageIndex) async {
    final page = _document.pages[pageIndex];
    const targetDpi = 160.0;
    final scale = math.min(
      targetDpi / 72.0,
      math.min(2200 / page.width, 2200 / page.height),
    );
    final rendered = await page.render(
      width: (page.width * scale).ceil(),
      height: (page.height * scale).ceil(),
    );
    if (rendered == null) {
      throw const MediaAcquisitionException(
        'A receipt PDF page could not be rendered safely.',
      );
    }
    try {
      final pixels = rendered.createImageNF();
      return ReceiptPdfRenderedPage(
        jpegBytes: Uint8List.fromList(image.encodeJpg(pixels, quality: 92)),
        width: pixels.width,
        height: pixels.height,
      );
    } finally {
      rendered.dispose();
    }
  }

  @override
  Future<void> dispose() => _document.dispose();
}
