import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/profile/profile_port.dart';

class MemberPermissionsPage extends StatefulWidget {
  const MemberPermissionsPage({
    required this.port,
    required this.home,
    required this.member,
    super.key,
  });
  final ProfilePort port;
  final HomeSummary home;
  final HomeMembership member;
  @override
  State<MemberPermissionsPage> createState() => _MemberPermissionsPageState();
}

class _MemberPermissionsPageState extends State<MemberPermissionsPage> {
  Map<String, Object?> _values = <String, Object?>{};
  int _revision = 0;
  bool _busy = true;
  String? _error;
  Map<String, String> get _path => <String, String>{
    'homeId': widget.home.id,
    'userId': widget.member.userId,
  };
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final value = profileRecord(
        await widget.port.call('getMemberPermissionOverrides', path: _path),
      );
      if (mounted) {
        setState(() {
          _values = profileRecord(value['permissions']);
          _revision = profileInteger(value['revision']);
          _busy = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = profileError(error);
          _busy = false;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.port.call(
        'updateMemberPermissionOverrides',
        path: _path,
        body: <String, Object?>{
          'permissions': _values,
          'expectedRevision': _revision,
        },
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = profileError(error);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = profileRecord(widget.home.access['features']);
    final allowed =
        (widget.home.access['delegablePermissions'] as List? ?? <Object?>[])
            .whereType<String>()
            .toSet();
    final keys = allowed.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text('${widget.member.displayName}: permissions')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text(
            'Inherit follows the home’s role settings. Individual choices always remain within the features enabled by the administrator for this home.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final key in keys)
            ListTile(
              title: Text(key),
              subtitle: features[key] == true
                  ? null
                  : const Text('Currently disabled for this home'),
              trailing: DropdownButton<String>(
                value: _values[key] == true
                    ? 'allow'
                    : _values[key] == false
                    ? 'deny'
                    : 'inherit',
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem(
                    value: 'inherit',
                    child: Text('Inherit'),
                  ),
                  if (widget.home.role == HomeRole.owner ||
                      widget.home.effectivePermissions.contains(key) ||
                      _values[key] == true)
                    DropdownMenuItem(
                      value: 'allow',
                      enabled:
                          features[key] == true &&
                          (widget.home.role == HomeRole.owner ||
                              widget.home.effectivePermissions.contains(key)),
                      child: const Text('Allow'),
                    ),
                  const DropdownMenuItem(value: 'deny', child: Text('Deny')),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        if (value == 'inherit') {
                          _values.remove(key);
                        } else {
                          _values[key] = value == 'allow';
                        }
                      }),
              ),
            ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save permissions'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() => _busy = true);
                    unawaited(_load());
                  },
            child: const Text('Reload current permissions'),
          ),
        ],
      ),
    );
  }
}
