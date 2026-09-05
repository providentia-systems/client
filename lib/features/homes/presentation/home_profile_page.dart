import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:providentia/features/profile/avatar_editor.dart';
import 'package:providentia/features/profile/location_picker.dart';
import 'package:providentia/features/profile/profile_port.dart';

import 'home_map_picker.dart';

class HomeProfilePage extends StatefulWidget {
  const HomeProfilePage({
    required this.port,
    required this.homeId,
    required this.mayEdit,
    super.key,
  });
  final ProfilePort port;
  final String homeId;
  final bool mayEdit;
  @override
  State<HomeProfilePage> createState() => _HomeProfilePageState();
}

class _HomeProfilePageState extends State<HomeProfilePage> {
  final _description = TextEditingController();
  ProfileRecord? _profile;
  Uint8List? _image;
  bool _busy = true;
  String? _error;
  Map<String, String> get _path => <String, String>{'homeId': widget.homeId};
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final record = profileRecord(
        await widget.port.call('getHomeProfile', path: _path),
      );
      final image = profileBytes(
        await widget.port.call('getHomeImage', path: _path),
      );
      if (!mounted) return;
      setState(() {
        _profile = record;
        _image = image;
        _description.text = '${record['description'] ?? ''}';
        _busy = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = profileError(error);
          _busy = false;
        });
      }
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = profileError(error);
          _busy = false;
        });
      }
    }
  }

  Future<void> _photo(bool remove) async {
    try {
      final bytes = remove ? null : await chooseCroppedAvatar(context);
      if (!remove && bytes == null) return;
      if (!mounted) return;
      await _perform(() async {
        await widget.port.call(
          remove ? 'deleteHomeImage' : 'putHomeImage',
          path: _path,
          body: <String, Object?>{
            'expectedRevision': _profile!['avatarRevision'],
            if (bytes != null) 'imageBase64': base64Encode(bytes),
          },
        );
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = profileError(error));
    }
  }

  Future<void> _place({bool region = false, bool city = false}) async {
    final result = await chooseLocation(
      context,
      widget.port,
      country: region || city ? _profile!['countryCode'] as String? : null,
      state: city ? _profile!['stateId'] as int? : null,
      cities: city,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (city) {
        _profile!['cityId'] = result['id'];
        _profile!['cityName'] = result['name'];
      } else if (region) {
        _profile!['stateId'] = result['id'];
        _profile!['stateName'] = result['name'];
        _profile!['cityId'] = null;
        _profile!['cityName'] = null;
      } else {
        _profile!['countryCode'] = result['code'];
        _profile!['stateId'] = null;
        _profile!['cityId'] = null;
        _profile!['stateName'] = null;
        _profile!['cityName'] = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Home profile')),
    body: _profile == null
        ? Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Text(_error!),
          )
        : ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              if (_busy) const LinearProgressIndicator(),
              Center(
                child: CircleAvatar(
                  radius: 64,
                  backgroundImage: _image == null ? null : MemoryImage(_image!),
                  child: _image == null
                      ? const Icon(Icons.home_outlined, size: 64)
                      : null,
                ),
              ),
              if (widget.mayEdit)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  children: <Widget>[
                    TextButton(
                      onPressed: _busy ? null : () => _photo(false),
                      child: const Text('Choose and crop photo'),
                    ),
                    if (_image != null)
                      TextButton(
                        onPressed: _busy ? null : () => _photo(true),
                        child: const Text('Use default image'),
                      ),
                  ],
                ),
              TextField(
                controller: _description,
                enabled: widget.mayEdit && !_busy,
                maxLines: 4,
                maxLength: 4000,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              ListTile(
                title: const Text('Country'),
                subtitle: Text(
                  '${_profile!['countryCode'] ?? 'Choose country'}',
                ),
                onTap: widget.mayEdit && !_busy ? () => _place() : null,
              ),
              ListTile(
                title: const Text('Region'),
                subtitle: Text(
                  '${_profile!['stateName'] ?? _profile!['stateId'] ?? 'Optional'}',
                ),
                onTap:
                    widget.mayEdit && !_busy && _profile!['countryCode'] != null
                    ? () => _place(region: true)
                    : null,
              ),
              ListTile(
                title: const Text('City'),
                subtitle: Text(
                  '${_profile!['cityName'] ?? _profile!['cityId'] ?? 'Optional'}',
                ),
                onTap:
                    widget.mayEdit && !_busy && _profile!['countryCode'] != null
                    ? () => _place(city: true)
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: const Text('Map location'),
                subtitle: Text(
                  _profile!['latitude'] == null
                      ? 'Optional — select a point on the map'
                      : '${_profile!['latitude']}, ${_profile!['longitude']}',
                ),
                onTap: widget.mayEdit && !_busy
                    ? () async {
                        final place = await showDialog<MapPoint>(
                          context: context,
                          builder: (_) => HomeMapPicker(
                            initial: MapPoint(
                              double.tryParse('${_profile!['latitude']}') ??
                                  -22.56,
                              double.tryParse('${_profile!['longitude']}') ??
                                  17.08,
                            ),
                          ),
                        );
                        if (place != null && mounted) {
                          setState(() {
                            _profile!['latitude'] = place.latitude;
                            _profile!['longitude'] = place.longitude;
                          });
                        }
                      }
                    : null,
                trailing: widget.mayEdit && _profile!['latitude'] != null
                    ? IconButton(
                        tooltip: 'Remove location',
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _profile!['latitude'] = null;
                                _profile!['longitude'] = null;
                              }),
                        icon: const Icon(Icons.clear),
                      )
                    : null,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (widget.mayEdit)
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _perform(() async {
                          await widget.port.call(
                            'updateHomeProfile',
                            path: _path,
                            body: <String, Object?>{
                              'description': _description.text,
                              'countryCode': _profile!['countryCode'],
                              'stateId': _profile!['stateId'],
                              'cityId': _profile!['cityId'],
                              'latitude': _profile!['latitude'],
                              'longitude': _profile!['longitude'],
                              'expectedRevision': _profile!['revision'],
                            },
                          );
                        }),
                  child: const Text('Save home profile'),
                ),
            ],
          ),
  );
}
