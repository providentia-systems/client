import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'avatar_editor.dart';
import 'email_confirmation_dialog.dart';
import 'location_picker.dart';
import 'profile_port.dart';

final class AccountProfilePage extends StatefulWidget {
  const AccountProfilePage({
    required this.port,
    required this.onChanged,
    this.onboarding = false,
    this.onSignOut,
    super.key,
  });
  final ProfilePort port;
  final Future<void> Function() onChanged;
  final bool onboarding;
  final VoidCallback? onSignOut;
  @override
  State<AccountProfilePage> createState() => _AccountProfilePageState();
}

class _AccountProfilePageState extends State<AccountProfilePage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _timezone = TextEditingController();
  ProfileRecord? _profile;
  ProfileRecord? _country;
  ProfileRecord? _state;
  ProfileRecord? _city;
  ProfileRecord? _policy;
  Uint8List? _avatar;
  var _busy = true;
  var _accepted = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _name.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = profileRecord(
        await widget.port.call('getAccountProfile'),
      );
      final countries = profileRecords(
        await widget.port.call('listAvailableCountries'),
      );
      final code =
          profile['countryCode'] ??
          (countries.length == 1 ? countries.single['code'] : null);
      final country = countries
          .where((value) => value['code'] == code)
          .firstOrNull;
      final policy = country == null
          ? null
          : profileRecord(
              await widget.port.call(
                'getCountryPrivacyPolicy',
                path: <String, String>{'countryCode': '$code'},
              ),
            );
      final avatar = profile['avatarSource'] == 'upload'
          ? profileBytes(await widget.port.call('getOwnAvatar'))
          : null;
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _country = country;
        _policy = policy;
        _avatar = avatar;
        _accepted = false;
        _name.text = '${profile['displayName'] ?? ''}';
        _timezone.text = profile['onboardingComplete'] == true
            ? '${profile['timezone']}'
            : '${country?['defaultTimezone'] ?? 'UTC'}';
        _state = profile['stateId'] == null
            ? null
            : <String, Object?>{
                'id': profile['stateId'],
                'name': profile['stateName'] ?? 'Region selected',
              };
        _city = profile['cityId'] == null
            ? null
            : <String, Object?>{
                'id': profile['cityId'],
                'name': profile['cityName'] ?? 'City selected',
              };
        _busy = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = profileError(error);
        });
      }
    }
  }

  bool get _requiresAcceptance =>
      widget.onboarding || _country?['code'] != _profile?['countryCode'];
  Future<void> _selectCountry() async {
    final country = await chooseLocation(context, widget.port);
    if (country == null || !mounted) return;
    setState(() {
      _busy = true;
      _accepted = false;
      _error = null;
    });
    try {
      final policy = profileRecord(
        await widget.port.call(
          'getCountryPrivacyPolicy',
          path: <String, String>{'countryCode': '${country['code']}'},
        ),
      );
      if (mounted) {
        setState(() {
          _country = country;
          _state = null;
          _city = null;
          _policy = policy;
          _timezone.text = '${country['defaultTimezone']}';
          _busy = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = profileError(error);
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_country == null || (_requiresAcceptance && !_accepted)) {
      setState(
        () => _error = 'Select your country and accept its privacy notice.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.port.call(
        widget.onboarding
            ? 'completeAccountOnboarding'
            : 'updateAccountProfile',
        body: <String, Object?>{
          'displayName': _name.text.trim(),
          'countryCode': _country!['code'],
          'stateId': _state == null ? null : profileInteger(_state!['id']),
          'cityId': _city == null ? null : profileInteger(_city!['id']),
          'locale': _profile!['locale'] ?? 'en',
          'timezone': _timezone.text.trim(),
          'expectedRevision': profileInteger(_profile!['revision']),
          if (_requiresAcceptance) ...<String, Object?>{
            'policyAccepted': _accepted,
            'policyId': _policy!['id'],
            'policyRevision': profileInteger(_policy!['revision']),
          },
        },
      );
      await widget.onChanged();
      if (mounted && !widget.onboarding) await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = profileError(error);
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) {
        await widget.onChanged();
        if (mounted) await _load();
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = profileError(error);
        });
      }
    }
  }

  Future<void> _upload() async {
    try {
      final bytes = await chooseCroppedAvatar(context);
      if (bytes == null || !mounted) return;
      await _run(() async {
        await widget.port.call(
          'putOwnAvatar',
          body: <String, Object?>{
            'imageBase64': base64Encode(bytes),
            'expectedRevision': profileInteger(_profile!['avatarRevision']),
          },
        );
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = profileError(error));
    }
  }

  Future<void> _emailAction(ProfileRecord email, bool primary) async {
    final proof = await confirmAccountEmail(
      context,
      widget.port,
      action: primary ? 'email.primary' : 'email.remove',
    );
    if (proof == null || !mounted) return;
    await _run(() async {
      await widget.port.call(
        primary ? 'makeAccountEmailPrimary' : 'removeAccountEmail',
        path: <String, String>{'emailId': '${email['id']}'},
        body: <String, Object?>{'proofToken': proof['proofToken']},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final emails = (_profile?['emails'] as List? ?? <Object?>[])
        .map(profileRecord)
        .toList();
    final gravatar = _profile == null ? null : gravatarAddress(_profile!);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onboarding ? 'Set up your account' : 'Your profile'),
        actions: <Widget>[
          if (widget.onSignOut != null)
            IconButton(
              onPressed: widget.onSignOut,
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: <Widget>[
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  MaterialBanner(
                    content: Text(_error!),
                    actions: <Widget>[
                      TextButton(
                        onPressed: _busy ? null : _load,
                        child: const Text('Reload'),
                      ),
                    ],
                  ),
                if (_profile != null) ...<Widget>[
                  if (!widget.onboarding) ...<Widget>[
                    Center(
                      child: CircleAvatar(
                        radius: 48,
                        foregroundImage: gravatar != null
                            ? NetworkImage(gravatar)
                            : _avatar != null
                            ? MemoryImage(_avatar!)
                            : null,
                        child: const Icon(Icons.person_outline, size: 48),
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: <Widget>[
                        TextButton.icon(
                          onPressed: _busy ? null : _upload,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Upload and crop avatar'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  await widget.port.call(
                                    'deleteOwnAvatar',
                                    body: <String, Object?>{
                                      'expectedRevision': profileInteger(
                                        _profile!['avatarRevision'],
                                      ),
                                    },
                                  );
                                }),
                          child: const Text('Use default avatar'),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      title: const Text('Look up avatar by verified email'),
                      subtitle: const Text(
                        'Optional Gravatar lookup sends a hash of the chosen email and your network address to Gravatar.',
                      ),
                      children: <Widget>[
                        for (final email in emails)
                          ListTile(
                            title: Text('${email['email']}'),
                            trailing:
                                _profile!['avatarSource'] == 'gravatar' &&
                                    _profile!['avatarEmailId'] == email['id']
                                ? const Icon(Icons.check)
                                : null,
                            onTap: _busy
                                ? null
                                : () => _run(() async {
                                    await widget.port.call(
                                      'selectGravatar',
                                      body: <String, Object?>{
                                        'emailId': email['id'],
                                        'expectedRevision': profileInteger(
                                          _profile!['revision'],
                                        ),
                                      },
                                    );
                                  }),
                          ),
                      ],
                    ),
                  ],
                  TextFormField(
                    controller: _name,
                    enabled: !_busy,
                    maxLength: 120,
                    autofillHints: const <String>[AutofillHints.name],
                    decoration: const InputDecoration(labelText: 'Your name'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your name.'
                        : null,
                  ),
                  ListTile(
                    title: const Text('Country'),
                    subtitle: Text('${_country?['name'] ?? 'Select country'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : _selectCountry,
                  ),
                  ListTile(
                    title: const Text('Region (optional)'),
                    subtitle: Text('${_state?['name'] ?? 'Not selected'}'),
                    trailing: _state == null
                        ? const Icon(Icons.chevron_right)
                        : IconButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _state = null;
                                    _city = null;
                                  }),
                            tooltip: 'Clear region',
                            icon: const Icon(Icons.clear),
                          ),
                    onTap: _busy || _country == null
                        ? null
                        : () async {
                            final state = await chooseLocation(
                              context,
                              widget.port,
                              country: '${_country!['code']}',
                            );
                            if (state != null && mounted) {
                              setState(() {
                                _state = state;
                                _city = null;
                              });
                            }
                          },
                  ),
                  ListTile(
                    title: const Text('City (optional)'),
                    subtitle: Text('${_city?['name'] ?? 'Not selected'}'),
                    trailing: _city == null
                        ? const Icon(Icons.chevron_right)
                        : IconButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _city = null),
                            tooltip: 'Clear city',
                            icon: const Icon(Icons.clear),
                          ),
                    onTap: _busy || _country == null
                        ? null
                        : () async {
                            final city = await chooseLocation(
                              context,
                              widget.port,
                              country: '${_country!['code']}',
                              state: _state == null
                                  ? null
                                  : profileInteger(_state!['id']),
                              cities: true,
                            );
                            if (city != null && mounted) {
                              setState(() => _city = city);
                            }
                          },
                  ),
                  TextFormField(
                    controller: _timezone,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Timezone',
                      hintText: 'Africa/Windhoek',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your timezone.'
                        : null,
                  ),
                  if (_policy != null)
                    ExpansionTile(
                      title: Text('${_policy!['title']}'),
                      initiallyExpanded: widget.onboarding,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText('${_policy!['body']}'),
                        ),
                      ],
                    ),
                  if (_requiresAcceptance)
                    CheckboxListTile(
                      title: const Text(
                        'I have read and agree to the privacy notice.',
                      ),
                      value: _accepted,
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _accepted = value == true),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(
                      widget.onboarding
                          ? 'Complete account setup'
                          : 'Save profile',
                    ),
                  ),
                  if (!widget.onboarding) ...<Widget>[
                    const Divider(height: 40),
                    Text(
                      'Verified login emails',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'You can sign in with any verified address. Keep one primary address on your account.',
                    ),
                    for (final email in emails)
                      ListTile(
                        title: Text('${email['email']}'),
                        subtitle: email['primary'] == true
                            ? const Text('Primary email')
                            : null,
                        trailing: email['primary'] == true
                            ? const Icon(Icons.verified_outlined)
                            : PopupMenuButton<String>(
                                enabled: !_busy,
                                onSelected: (value) =>
                                    _emailAction(email, value == 'primary'),
                                itemBuilder: (_) =>
                                    const <PopupMenuEntry<String>>[
                                      PopupMenuItem(
                                        value: 'primary',
                                        child: Text('Make primary'),
                                      ),
                                      PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Remove email'),
                                      ),
                                    ],
                              ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final result = await confirmAccountEmail(
                                context,
                                widget.port,
                              );
                              if (result != null && mounted) {
                                await widget.onChanged();
                                if (mounted) await _load();
                              }
                            },
                      icon: const Icon(Icons.add),
                      label: const Text('Add email address'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
