import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'profile_port.dart';

Future<ProfileRecord?> confirmAccountEmail(
  BuildContext context,
  ProfilePort port, {
  String? action,
}) => showDialog<ProfileRecord>(
  context: context,
  builder: (_) => _EmailConfirmation(port: port, action: action),
);

class _EmailConfirmation extends StatefulWidget {
  const _EmailConfirmation({required this.port, this.action});
  final ProfilePort port;
  final String? action;
  @override
  State<_EmailConfirmation> createState() => _EmailConfirmationState();
}

class _EmailConfirmationState extends State<_EmailConfirmation> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  ProfileRecord? _challenge;
  Timer? _timer;
  var _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _challenge != null) setState(() {});
    });
    if (widget.action != null) unawaited(_request());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  int get _remaining {
    final time = DateTime.tryParse('${_challenge?['resendAt']}');
    return time == null
        ? 0
        : time.difference(DateTime.now()).inSeconds.clamp(0, 60);
  }

  Future<void> _request() async {
    if (widget.action == null && !_email.text.contains('@')) {
      setState(() => _error = 'Enter an email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = profileRecord(
        await widget.port.call(
          widget.action == null
              ? 'requestAccountEmailCode'
              : 'requestSecurityCode',
          body: <String, Object?>{
            if (widget.action == null)
              'email': _email.text.trim()
            else
              'action': widget.action,
          },
        ),
      );
      if (mounted) {
        setState(() {
          _challenge = <String, Object?>{
            ...result,
            'resendAt': DateTime.now()
                .add(
                  Duration(
                    seconds: profileInteger(result['resendAfterSeconds']),
                  ),
                )
                .toIso8601String(),
          };
          _code.clear();
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

  Future<void> _verify() async {
    if (!RegExp(r'^\d{8}$').hasMatch(_code.text)) {
      setState(() => _error = 'Enter the eight-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = profileRecord(
        await widget.port.call(
          widget.action == null ? 'verifyAccountEmail' : 'verifySecurityCode',
          body: <String, Object?>{
            'challengeId': _challenge!['challengeId'],
            'bindingToken': _challenge!['bindingToken'],
            'code': _code.text,
          },
        ),
      );
      if (mounted) Navigator.pop(context, result);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = profileError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.action == null
          ? 'Add a verified email'
          : 'Confirm with an email code',
    ),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.action == null)
            TextField(
              controller: _email,
              enabled: !_busy && _challenge == null,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const <String>[AutofillHints.email],
              decoration: const InputDecoration(labelText: 'New email address'),
            ),
          if (_challenge != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              widget.action == null
                  ? 'Enter the code sent to your new address.'
                  : 'Enter the code sent to your primary email address.',
            ),
            TextField(
              controller: _code,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const <String>[AutofillHints.oneTimeCode],
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: const InputDecoration(labelText: 'Eight-digit code'),
              onSubmitted: (_) => _busy ? null : _verify(),
            ),
            TextButton(
              onPressed: _busy || _remaining > 0 ? null : _request,
              child: Text(
                _remaining > 0
                    ? 'Resend in ${_remaining}s'
                    : 'Send another code',
              ),
            ),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy
            ? null
            : _challenge == null
            ? _request
            : _verify,
        child: Text(_challenge == null ? 'Send code' : 'Verify code'),
      ),
    ],
  );
}
