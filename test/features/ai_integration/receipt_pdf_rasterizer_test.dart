import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/media_acquisition_service.dart';
import 'package:providentia/features/ai_integration/infrastructure/receipt_page_media_editor.dart';
import 'package:providentia/features/ai_integration/infrastructure/receipt_pdf_rasterizer.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';

void main() {
  test(
    'rasterizes ordered PDF pages into editable sanitized receipt images',
    () async {
      final sources = RegisteredMediaSourceReader();
      final input = _pdfBytes();
      Uint8List? documentInput;
      final document = _FakePdfDocument(
        pages: <ReceiptPdfRenderedPage>[
          _page(40, 20, image.ColorRgb8(220, 20, 20)),
          _page(20, 40, image.ColorRgb8(20, 20, 220)),
        ],
      );
      final rasterizer = ReceiptPdfRasterizer(
        sources: sources,
        openDocument: (bytes) async {
          expect(bytes, isNot(same(input)));
          expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
          documentInput = bytes;
          return document;
        },
        clock: () => DateTime.utc(2026, 8, 11),
      );

      final assets = await rasterizer.rasterize(
        bytes: input,
        homeId: 'home-1',
        sourceName: 'synthetic.pdf',
      );

      expect(assets.map((asset) => asset.pageIndex), <int?>[0, 1]);
      expect(assets.map((asset) => asset.mimeType).toSet(), <String>{
        'image/jpeg',
      });
      expect(sources.registeredIds, assets.map((asset) => asset.id).toSet());
      expect(document.disposed, isTrue);
      expect(input.every((byte) => byte == 0), isTrue);
      expect(documentInput!.every((byte) => byte == 0), isTrue);

      final editor = ReceiptPageMediaEditor(sources: sources);
      final rotated = await editor.rotateClockwise90(assets.first);
      expect(rotated.pageIndex, 0);
      expect(rotated.width, 20);
      expect(rotated.height, 40);

      final preparedStore = MemoryEphemeralPreparedMediaStore();
      final prepared =
          await SanitizingImageMediaPreparer(
            sources: sources,
            prepared: preparedStore,
          ).prepare(
            homeId: 'home-1',
            purpose: AiExtractionKind.receipt,
            assets: <AiMediaAsset>[rotated, assets[1]],
          );
      expect(prepared.media.map((media) => media.pageIndex), <int?>[0, 1]);
      expect(prepared.orderedHashes, hasLength(2));
      expect(prepared.orderedHashes.toSet(), hasLength(2));

      await editor.discard(<AiMediaAsset>[rotated, assets[1]]);
      expect(sources.registeredIds, isEmpty);
    },
  );

  test('picker cancellation creates no transient source', () async {
    final sources = RegisteredMediaSourceReader();
    final rasterizer = ReceiptPdfRasterizer(
      sources: sources,
      pickPdf: () async => null,
      openDocument: (_) async =>
          _FakePdfDocument(pages: <ReceiptPdfRenderedPage>[]),
    );

    expect(await rasterizer.choose(homeId: 'home-1'), isEmpty);
    expect(sources.registeredIds, isEmpty);
  });

  test('rejects malformed, incomplete and incorrectly named PDFs', () async {
    var opened = false;
    final rasterizer = ReceiptPdfRasterizer(
      sources: RegisteredMediaSourceReader(),
      openDocument: (_) async {
        opened = true;
        return _FakePdfDocument(pages: <ReceiptPdfRenderedPage>[]);
      },
    );

    for (final sample in <({Uint8List bytes, String name})>[
      (bytes: Uint8List.fromList(List<int>.filled(32, 1)), name: 'x.pdf'),
      (
        bytes: Uint8List.fromList('%PDF-1.7 missing trailer'.codeUnits),
        name: 'x.pdf',
      ),
      (bytes: _pdfBytes(), name: 'x.png'),
    ]) {
      await expectLater(
        rasterizer.rasterize(
          bytes: sample.bytes,
          homeId: 'home-1',
          sourceName: sample.name,
        ),
        throwsA(isA<MediaAcquisitionException>()),
      );
      expect(sample.bytes.every((byte) => byte == 0), isTrue);
    }
    expect(opened, isFalse);
  });

  test('rejects oversized input before parsing and clears its bytes', () async {
    var opened = false;
    final input = _pdfBytes();
    final rasterizer = ReceiptPdfRasterizer(
      sources: RegisteredMediaSourceReader(),
      maximumSourceBytes: input.length - 1,
      openDocument: (_) async {
        opened = true;
        return _FakePdfDocument(pages: <ReceiptPdfRenderedPage>[]);
      },
    );

    await expectLater(
      rasterizer.rasterize(
        bytes: input,
        homeId: 'home-1',
        sourceName: 'receipt.pdf',
      ),
      throwsA(isA<MediaAcquisitionException>()),
    );

    expect(opened, isFalse);
    expect(input.every((byte) => byte == 0), isTrue);
  });

  test(
    'rejects encrypted and over-page PDFs and always disposes them',
    () async {
      for (final document in <_FakePdfDocument>[
        _FakePdfDocument(
          encrypted: true,
          pages: <ReceiptPdfRenderedPage>[
            _page(10, 10, image.ColorRgb8(1, 2, 3)),
          ],
        ),
        _FakePdfDocument(
          pages: List<ReceiptPdfRenderedPage>.generate(
            9,
            (_) => _page(10, 10, image.ColorRgb8(1, 2, 3)),
          ),
        ),
      ]) {
        final sources = RegisteredMediaSourceReader();
        final input = _pdfBytes();
        final rasterizer = ReceiptPdfRasterizer(
          sources: sources,
          openDocument: (_) async => document,
        );
        await expectLater(
          rasterizer.rasterize(
            bytes: input,
            homeId: 'home-1',
            sourceName: 'receipt.pdf',
          ),
          throwsA(isA<MediaAcquisitionException>()),
        );
        expect(document.disposed, isTrue);
        expect(sources.registeredIds, isEmpty);
        expect(input.every((byte) => byte == 0), isTrue);
      }
    },
  );

  test(
    'rolls back already-rendered pages after a later page failure',
    () async {
      final sources = RegisteredMediaSourceReader();
      final document = _FakePdfDocument(
        pages: <ReceiptPdfRenderedPage>[
          _page(20, 20, image.ColorRgb8(1, 2, 3)),
          ReceiptPdfRenderedPage(
            jpegBytes: Uint8List(1),
            width: 20,
            height: 20,
          ),
        ],
      );
      final rasterizer = ReceiptPdfRasterizer(
        sources: sources,
        openDocument: (_) async => document,
      );
      final input = _pdfBytes();

      await expectLater(
        rasterizer.rasterize(
          bytes: input,
          homeId: 'home-1',
          sourceName: 'receipt.pdf',
        ),
        throwsA(isA<MediaAcquisitionException>()),
      );
      expect(sources.registeredIds, isEmpty);
      expect(document.disposed, isTrue);
      expect(input.every((byte) => byte == 0), isTrue);
    },
  );

  test('rendered-page byte limit rolls back the complete batch', () async {
    final sources = RegisteredMediaSourceReader();
    final first = _page(30, 30, image.ColorRgb8(1, 2, 3));
    final second = _page(30, 30, image.ColorRgb8(3, 2, 1));
    final input = _pdfBytes();
    final rasterizer = ReceiptPdfRasterizer(
      sources: sources,
      maximumRenderedBytes:
          first.jpegBytes.length + second.jpegBytes.length - 1,
      openDocument: (_) async =>
          _FakePdfDocument(pages: <ReceiptPdfRenderedPage>[first, second]),
    );

    await expectLater(
      rasterizer.rasterize(
        bytes: input,
        homeId: 'home-1',
        sourceName: 'receipt.pdf',
      ),
      throwsA(isA<MediaAcquisitionException>()),
    );

    expect(sources.registeredIds, isEmpty);
    expect(input.every((byte) => byte == 0), isTrue);
  });

  test('document disposal failure rolls back rendered pages', () async {
    final sources = RegisteredMediaSourceReader();
    final input = _pdfBytes();
    final rasterizer = ReceiptPdfRasterizer(
      sources: sources,
      openDocument: (_) async => _FakePdfDocument(
        pages: <ReceiptPdfRenderedPage>[
          _page(20, 20, image.ColorRgb8(1, 2, 3)),
        ],
        disposeError: StateError('private native handle'),
      ),
    );

    await expectLater(
      rasterizer.rasterize(
        bytes: input,
        homeId: 'home-1',
        sourceName: 'receipt.pdf',
      ),
      throwsA(
        isA<MediaAcquisitionException>().having(
          (error) => error.safeMessage,
          'safeMessage',
          isNot(contains('private')),
        ),
      ),
    );
    expect(sources.registeredIds, isEmpty);
    expect(input.every((byte) => byte == 0), isTrue);
  });
}

final class _FakePdfDocument implements ReceiptPdfDocument {
  _FakePdfDocument({
    required this.pages,
    this.encrypted = false,
    this.disposeError,
  });

  final List<ReceiptPdfRenderedPage> pages;
  final bool encrypted;
  final Object? disposeError;
  bool disposed = false;

  @override
  bool get isEncrypted => encrypted;

  @override
  int get pageCount => pages.length;

  @override
  Future<ReceiptPdfRenderedPage> renderPage(int pageIndex) async =>
      pages[pageIndex];

  @override
  Future<void> dispose() async {
    disposed = true;
    if (disposeError case final error?) throw error;
  }
}

ReceiptPdfRenderedPage _page(int width, int height, image.Color color) {
  final pixels = image.Image(width: width, height: height);
  image.fill(pixels, color: color);
  return ReceiptPdfRenderedPage(
    jpegBytes: Uint8List.fromList(image.encodeJpg(pixels)),
    width: width,
    height: height,
  );
}

Uint8List _pdfBytes() => Uint8List.fromList(
  '%PDF-1.7\n1 0 obj\n<<>>\nendobj\nstartxref\n0\n%%EOF\n'.codeUnits,
);
