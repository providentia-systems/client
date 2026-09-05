import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'profile_port.dart';

/// Only an explicit Gravatar choice causes a request to that provider.
String? gravatarAddress(ProfileRecord profile) {
  if (profile['avatarSource'] != 'gravatar') return null;
  for (final raw in profile['emails'] as List? ?? <Object?>[]) {
    final email = profileRecord(raw);
    if (email['id'] == profile['avatarEmailId']) {
      final digest = sha256.convert(
        utf8.encode('${email['email']}'.trim().toLowerCase()),
      );
      return 'https://www.gravatar.com/avatar/$digest?s=256&d=identicon';
    }
  }
  return null;
}

Future<Uint8List?> chooseCroppedAvatar(BuildContext context) async {
  final selection = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    withData: true,
    allowMultiple: false,
  );
  if (selection == null) return null;
  if (selection.files.single.size > 10 * 1024 * 1024) {
    throw const ProfileFailure('Choose an image smaller than 10 MB.');
  }
  final bytes =
      selection.files.single.bytes ??
      await selection.xFiles.single.readAsBytes();
  if (bytes.length > 10 * 1024 * 1024) {
    throw const ProfileFailure(
      'Choose a PNG, JPEG or WebP image smaller than 10 MB.',
    );
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 24000000) {
    throw const ProfileFailure(
      'Choose an image with fewer than 24 million pixels.',
    );
  }
  final decoded = decoder!.decode(bytes);
  if (decoded == null) {
    throw const ProfileFailure('The selected image could not be read.');
  }
  final upright = img.bakeOrientation(decoded);
  final source = math.max(upright.width, upright.height) > 1600
      ? img.copyResize(
          upright,
          width: upright.width >= upright.height ? 1600 : null,
          height: upright.height > upright.width ? 1600 : null,
        )
      : upright;
  if (!context.mounted) return null;
  return showDialog<Uint8List>(
    context: context,
    builder: (_) => _CropDialog(source: source),
  );
}

class _CropDialog extends StatefulWidget {
  const _CropDialog({required this.source});
  final img.Image source;
  @override
  State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  double _x = .5;
  double _y = .5;
  double _zoom = 1;
  img.Image _crop(int size) {
    final source = widget.source;
    final side = (math.min(source.width, source.height) / _zoom).round();
    return img.copyResize(
      img.copyCrop(
        source,
        x: ((source.width - side) * _x).round(),
        y: ((source.height - side) * _y).round(),
        width: side,
        height: side,
      ),
      width: size,
      height: size,
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Crop your image'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.memory(
              Uint8List.fromList(img.encodeJpg(_crop(256), quality: 85)),
              width: 256,
              height: 256,
              gaplessPlayback: true,
            ),
            const Text('Zoom'),
            Slider(
              value: _zoom,
              min: 1,
              max: 4,
              onChanged: (value) => setState(() => _zoom = value),
            ),
            const Text('Horizontal position'),
            Slider(value: _x, onChanged: (value) => setState(() => _x = value)),
            const Text('Vertical position'),
            Slider(value: _y, onChanged: (value) => setState(() => _y = value)),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          Uint8List.fromList(img.encodeJpg(_crop(512), quality: 90)),
        ),
        child: const Text('Use image'),
      ),
    ],
  );
}
