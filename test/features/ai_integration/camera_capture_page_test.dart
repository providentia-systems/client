import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/presentation/camera_capture_page.dart';

void main() {
  testWidgets('unavailable camera fails safely and offers retry', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CameraCapturePage(
          loadCameras: () async {
            loads++;
            return const <CameraDescription>[];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('camera-safe-error')), findsOneWidget);
    expect(find.text('No camera is available on this device.'), findsOneWidget);
    expect(find.byKey(const Key('camera-capture')), findsOneWidget);

    await tester.tap(find.byKey(const Key('camera-retry')));
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('initialized camera captures through the common camera API', (
    tester,
  ) async {
    final controller = _TestCameraController(_description);
    await tester.pumpWidget(
      MaterialApp(
        home: CameraCapturePage(
          loadCameras: () async => <CameraDescription>[_description],
          createController: (_) => controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.initializeCalls, 1);
    await tester.tap(find.byKey(const Key('camera-capture')));
    await tester.pumpAndSettle();

    expect(controller.captureCalls, 1);
    expect(controller.disposeCalls, 1);
  });

  testWidgets('resume waits for inactive controller disposal to finish', (
    tester,
  ) async {
    final disposeGate = Completer<void>();
    final controllers = <_TestCameraController>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CameraCapturePage(
          loadCameras: () async => <CameraDescription>[_description],
          createController: (_) {
            final controller = _TestCameraController(
              _description,
              disposeGate: controllers.isEmpty ? disposeGate : null,
            );
            controllers.add(controller);
            return controller;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(controllers, hasLength(1));
    expect(controllers.single.disposeCalls, 1);

    disposeGate.complete();
    await tester.pumpAndSettle();

    expect(controllers, hasLength(2));
    expect(controllers.last.initializeCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

const CameraDescription _description = CameraDescription(
  name: 'camera-1',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

final class _TestCameraController extends CameraController {
  _TestCameraController(CameraDescription description, {this.disposeGate})
    : super(description, ResolutionPreset.high, enableAudio: false);

  final Completer<void>? disposeGate;
  int initializeCalls = 0;
  int captureCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(640, 480),
    );
  }

  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);

  @override
  Future<XFile> takePicture() async {
    captureCalls++;
    return XFile.fromData(
      Uint8List.fromList(List<int>.generate(16, (index) => index)),
      name: 'captured.jpg',
      mimeType: 'image/jpeg',
    );
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await disposeGate?.future;
    await super.dispose();
  }
}
