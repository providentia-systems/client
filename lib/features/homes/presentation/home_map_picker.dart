import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MapPoint {
  const MapPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

/// An explicit, online map selector. Tiles remain with Flutter's image cache;
/// coordinates are saved only after the user confirms and saves the home.
class HomeMapPicker extends StatefulWidget {
  const HomeMapPicker({required this.initial, super.key});
  final MapPoint initial;
  @override
  State<HomeMapPicker> createState() => _HomeMapPickerState();
}

class _HomeMapPickerState extends State<HomeMapPicker> {
  late MapPoint _point = widget.initial;
  int _zoom = 13;
  double get _world => 256.0 * (1 << _zoom);
  Offset get _center {
    final latitude = _point.latitude.clamp(-85.05, 85.05) * math.pi / 180;
    return Offset(
      (_point.longitude + 180) / 360 * _world,
      (1 - math.log(math.tan(latitude) + 1 / math.cos(latitude)) / math.pi) /
          2 *
          _world,
    );
  }

  MapPoint _fromPixel(Offset value) {
    final x = value.dx % _world;
    final y = value.dy.clamp(0, _world);
    final n = math.pi * (1 - 2 * y / _world);
    return MapPoint(
      math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi,
      x / _world * 360 - 180,
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Place your home on the map'),
    content: SizedBox(
      width: 640,
      height: 430,
      child: Column(
        children: <Widget>[
          const Text(
            'Drag the map under the pin. Map tiles are provided by OpenStreetMap.',
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final center = _center;
                final origin =
                    center - Offset(box.maxWidth / 2, box.maxHeight / 2);
                final startX = (origin.dx / 256).floor();
                final startY = (origin.dy / 256).floor();
                final columns = (box.maxWidth / 256).ceil() + 1;
                final rows = (box.maxHeight / 256).ceil() + 1;
                return ClipRect(
                  child: GestureDetector(
                    onPanUpdate: (event) => setState(
                      () => _point = _fromPixel(_center - event.delta),
                    ),
                    onTapUp: (event) => setState(
                      () => _point = _fromPixel(origin + event.localPosition),
                    ),
                    child: Stack(
                      children: <Widget>[
                        const Positioned.fill(
                          child: ColoredBox(color: Color(0xffe6ece5)),
                        ),
                        for (var x = startX; x < startX + columns; x++)
                          for (var y = startY; y < startY + rows; y++)
                            if (y >= 0 && y < (1 << _zoom))
                              Positioned(
                                left: x * 256 - origin.dx,
                                top: y * 256 - origin.dy,
                                width: 256,
                                height: 256,
                                child: Image.network(
                                  'https://tile.openstreetmap.org/$_zoom/${x % (1 << _zoom)}/$y.png',
                                  headers: kIsWeb
                                      ? null
                                      : const <String, String>{
                                          'User-Agent':
                                              'Providentia/2.0 (home location selector)',
                                        },
                                  errorBuilder: (_, error, trace) =>
                                      const Center(
                                        child: Text('Map unavailable'),
                                      ),
                                  gaplessPlayback: true,
                                ),
                              ),
                        const Center(
                          child: IgnorePointer(
                            child: Icon(
                              Icons.location_on,
                              size: 36,
                              color: Colors.red,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Column(
                            children: <Widget>[
                              IconButton.filled(
                                tooltip: 'Zoom in',
                                onPressed: _zoom >= 18
                                    ? null
                                    : () => setState(() => _zoom++),
                                icon: const Icon(Icons.add),
                              ),
                              IconButton.filled(
                                tooltip: 'Zoom out',
                                onPressed: _zoom <= 2
                                    ? null
                                    : () => setState(() => _zoom--),
                                icon: const Icon(Icons.remove),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Text(
            '${_point.latitude.toStringAsFixed(5)}, ${_point.longitude.toStringAsFixed(5)}',
          ),
          TextButton(
            onPressed: () =>
                launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
            child: const Text('© OpenStreetMap contributors'),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _point),
        child: const Text('Use this location'),
      ),
    ],
  );
}
