import 'dart:async';

import 'package:flutter/material.dart';

import 'profile_port.dart';

Future<ProfileRecord?> chooseLocation(
  BuildContext context,
  ProfilePort port, {
  String? country,
  int? state,
  bool cities = false,
}) => showDialog<ProfileRecord>(
  context: context,
  builder: (_) => _LocationPicker(
    port: port,
    country: country,
    state: state,
    cities: cities,
  ),
);

class _LocationPicker extends StatefulWidget {
  const _LocationPicker({
    required this.port,
    this.country,
    this.state,
    required this.cities,
  });
  final ProfilePort port;
  final String? country;
  final int? state;
  final bool cities;
  @override
  State<_LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<_LocationPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ProfileRecord> _places = <ProfileRecord>[];
  int _offset = 0;
  int _generation = 0;
  var _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.port.call(
        widget.country == null
            ? 'listAvailableCountries'
            : widget.cities
            ? 'listCountryCities'
            : 'listCountryStates',
        path: <String, String>{
          if (widget.country != null) 'countryCode': widget.country!,
        },
        query: <String, String>{
          'search': _search.text.trim(),
          'offset': '$_offset',
          if (widget.state != null) 'stateId': '${widget.state}',
        },
      );
      if (mounted && generation == _generation) {
        setState(() {
          _places = profileRecords(response);
          _busy = false;
        });
      }
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _error = profileError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.country == null
        ? _places
              .where(
                (place) => '${place['name']}'.toLowerCase().contains(
                  _search.text.toLowerCase(),
                ),
              )
              .toList()
        : _places;
    return AlertDialog(
      title: Text(
        widget.country == null
            ? 'Select country'
            : widget.cities
            ? 'Select city'
            : 'Select region',
      ),
      content: SizedBox(
        width: 540,
        height: 440,
        child: Column(
          children: <Widget>[
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) {
                if (widget.country == null) {
                  setState(() {});
                  return;
                }
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  _offset = 0;
                  unawaited(_load());
                });
              },
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            Expanded(
              child: visible.isEmpty && !_busy
                  ? const Center(child: Text('No matching locations.'))
                  : ListView(
                      children: <Widget>[
                        for (final place in visible)
                          ListTile(
                            title: Text('${place['name']}'),
                            onTap: _busy
                                ? null
                                : () => Navigator.pop(context, place),
                          ),
                      ],
                    ),
            ),
            if (widget.country != null)
              Row(
                children: <Widget>[
                  TextButton(
                    onPressed: _busy || _offset == 0
                        ? null
                        : () {
                            _offset = (_offset - 100).clamp(0, _offset);
                            unawaited(_load());
                          },
                    child: const Text('Previous'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy || _places.length < 100
                        ? null
                        : () {
                            _offset += 100;
                            unawaited(_load());
                          },
                    child: const Text('Next'),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
