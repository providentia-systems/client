import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

typedef AvailableCameraLoader = Future<List<CameraDescription>> Function();
typedef CameraControllerFactory =
    CameraController Function(CameraDescription description);

/// A lifecycle-safe camera surface for Android, iOS, web, Linux and macOS.
///
/// The official camera package provides phone and browser implementations;
/// camera_desktop registers the same platform interface on desktop. Lifecycle
/// transitions are serialized so a resumed camera never races disposal of the
/// inactive controller.
final class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({
    super.key,
    this.loadCameras = availableCameras,
    this.createController = _createController,
  });

  final AvailableCameraLoader loadCameras;
  final CameraControllerFactory createController;

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

Future<XFile?> showCameraCapture(BuildContext context) =>
    Navigator.of(context).push<XFile>(
      MaterialPageRoute<XFile>(builder: (_) => const CameraCapturePage()),
    );

CameraController _createController(CameraDescription description) =>
    CameraController(description, ResolutionPreset.high, enableAudio: false);

final class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _description;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  Future<void> _cameraTransition = Future<void>.value();
  String? _safeError;
  bool _initializing = true;
  bool _capturing = false;
  int _lifecycleGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleLoad();
  }

  void _scheduleLoad([CameraDescription? preferred]) {
    final generation = ++_lifecycleGeneration;
    if (mounted) {
      setState(() {
        _initializing = true;
        _safeError = null;
      });
    }
    _enqueueCameraTransition(() => _load(generation, preferred));
  }

  Future<void> _load(int generation, CameraDescription? preferred) async {
    CameraController? candidate;
    try {
      final cameras = await widget.loadCameras();
      if (!_current(generation)) return;
      if (cameras.isEmpty) {
        _showUnavailable(generation, 'No camera is available on this device.');
        return;
      }
      final selected = _selectCamera(cameras, preferred);
      candidate = widget.createController(selected);
      await candidate.initialize();
      if (!_current(generation)) {
        await _disposeSafely(candidate);
        return;
      }
      final previous = _controller;
      _controller = candidate;
      _description = selected;
      _cameras = List<CameraDescription>.unmodifiable(cameras);
      candidate = null;
      if (mounted) {
        setState(() {
          _initializing = false;
          _safeError = null;
        });
      }
      await _disposeSafely(previous);
    } on CameraException {
      await _disposeSafely(candidate);
      _showUnavailable(
        generation,
        'Camera access is unavailable. Check the device permission or upload an image instead.',
      );
    } on Object {
      await _disposeSafely(candidate);
      _showUnavailable(
        generation,
        'The camera could not be initialized safely. Upload an image instead.',
      );
    }
  }

  CameraDescription _selectCamera(
    List<CameraDescription> cameras,
    CameraDescription? preferred,
  ) {
    if (preferred != null) {
      for (final camera in cameras) {
        if (camera.name == preferred.name) return camera;
      }
    }
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.back) return camera;
    }
    return cameras.first;
  }

  bool _current(int generation) =>
      mounted && generation == _lifecycleGeneration;

  void _showUnavailable(int generation, String message) {
    if (!_current(generation)) return;
    setState(() {
      _initializing = false;
      _safeError = message;
    });
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_capturing || controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final image = await controller.takePicture();
      if (mounted) Navigator.of(context).pop<XFile>(image);
    } on CameraException {
      if (mounted) {
        setState(() {
          _capturing = false;
          _safeError = 'The photo could not be captured. Please try again.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _capturing = false;
          _safeError = 'The camera stopped unexpectedly. Please try again.';
        });
      }
    }
  }

  void _switchCamera() {
    if (_cameras.length < 2 || _initializing || _capturing) return;
    final currentIndex = _cameras.indexWhere(
      (camera) => camera.name == _description?.name,
    );
    _scheduleLoad(_cameras[(currentIndex + 1) % _cameras.length]);
  }

  void _enqueueCameraTransition(Future<void> Function() transition) {
    final previous = _cameraTransition;
    _cameraTransition = () async {
      try {
        await previous;
      } on Object {
        // One faulty platform call must not break the lifecycle queue.
      }
      await transition();
    }();
  }

  Future<void> _disposeSafely(CameraController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } on Object {
      // Disposal has no user-recoverable detail. Reinitialization remains
      // serialized after this attempt.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_controller == null) _scheduleLoad(_description);
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        ++_lifecycleGeneration;
        final controller = _controller;
        _controller = null;
        _enqueueCameraTransition(() => _disposeSafely(controller));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Take photo'),
      actions: <Widget>[
        if (_cameras.length > 1)
          IconButton(
            key: const Key('camera-switch'),
            tooltip: 'Switch camera',
            onPressed: _switchCamera,
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
      ],
    ),
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: _preview()),
          if (_safeError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _safeError!,
                key: const Key('camera-safe-error'),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              key: const Key('camera-capture'),
              onPressed: _controller?.value.isInitialized == true && !_capturing
                  ? _capture
                  : null,
              icon: _capturing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt_outlined),
              label: Text(_capturing ? 'Capturing…' : 'Capture photo'),
            ),
          ),
          if (_safeError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: OutlinedButton(
                key: const Key('camera-retry'),
                onPressed: _initializing ? null : _scheduleLoad,
                child: const Text('Try camera again'),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _preview() {
    final controller = _controller;
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black12,
        child: Center(child: Icon(Icons.no_photography_outlined, size: 64)),
      );
    }
    final previewSize = controller.value.previewSize;
    final aspectRatio = previewSize == null || previewSize.height == 0
        ? 4 / 3
        : previewSize.width / previewSize.height;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_lifecycleGeneration;
    final controller = _controller;
    _controller = null;
    _enqueueCameraTransition(() => _disposeSafely(controller));
    super.dispose();
  }
}
