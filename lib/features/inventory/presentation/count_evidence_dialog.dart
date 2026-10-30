import 'package:flutter/material.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';

Future<void> showCountEvidenceDialog({
  required BuildContext context,
  required InventoryController controller,
  required StockCountSession session,
  bool acceptedReview = false,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _CountEvidenceDialog(
    controller: controller,
    session: session,
    acceptedReview: acceptedReview,
  ),
);

/// An explicit offset prevents a device timezone from silently reinterpreting
/// historical observations. Household timezone authority stays on the server.
DateTime parseCountObservation(String text) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(text.trim());
  if (match == null) throw const FormatException('Include a timezone offset.');
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final civil = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (civil.year != parts[0] ||
      civil.month != parts[1] ||
      civil.day != parts[2] ||
      civil.hour != parts[3] ||
      civil.minute != parts[4] ||
      civil.second != parts[5]) {
    throw const FormatException('Choose a real calendar time.');
  }
  final zone = match.group(7)!;
  if (zone != 'Z' &&
      (int.parse(zone.substring(1, 3)) > 14 ||
          int.parse(zone.substring(4)) > 59 ||
          (int.parse(zone.substring(1, 3)) == 14 &&
              zone.substring(4) != '00'))) {
    throw const FormatException('Choose a valid timezone offset.');
  }
  return DateTime.parse(text.trim()).toUtc();
}

class _CountEvidenceDialog extends StatefulWidget {
  const _CountEvidenceDialog({
    required this.controller,
    required this.session,
    required this.acceptedReview,
  });
  final InventoryController controller;
  final StockCountSession session;
  final bool acceptedReview;
  @override
  State<_CountEvidenceDialog> createState() => _CountEvidenceDialogState();
}

class _CountEvidenceDialogState extends State<_CountEvidenceDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _observed;
  final _reason = TextEditingController();
  final _quantities = <String, TextEditingController>{};
  late bool _complete;
  late String _reliability;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _observed = TextEditingController(
      text: widget.session.observedAt?.toUtc().toIso8601String() ?? '',
    );
    _complete = widget.session.scopeComplete ?? false;
    _reliability =
        const {
          'reliable',
          'partial',
          'unassessed',
        }.contains(widget.session.reliability)
        ? widget.session.reliability!
        : 'unassessed';
    if (widget.acceptedReview) {
      for (final line in widget.session.confirmedLines) {
        _quantities[line.id] = TextEditingController(
          text: _quantity(line.observedQuantity!),
        );
      }
    }
  }

  String _quantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  @override
  void dispose() {
    _observed.dispose();
    _reason.dispose();
    for (final field in _quantities.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_reliability == 'reliable' && !_complete) {
      setState(
        () =>
            _error = 'A reliable observation requires explicit complete scope.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final evidence = StockCountEvidence(
        scopeComplete: _complete,
        reliability: _reliability,
        observedAt: parseCountObservation(_observed.text),
      );
      if (widget.acceptedReview) {
        final corrections = <StockCountLineCorrection>[];
        for (final line in widget.session.confirmedLines) {
          final text = _quantities[line.id]!.text.trim();
          if (double.parse(text) != line.observedQuantity) {
            corrections.add(
              StockCountLineCorrection(
                id: line.id,
                expectedRevision: line.revision,
                quantity: text,
              ),
            );
          }
        }
        final saved = await widget.controller.reviewAcceptedCount(
          session: widget.session,
          evidence: evidence,
          reason: _reason.text,
          corrections: corrections,
        );
        if (!saved) {
          if (mounted) {
            setState(
              () => _error =
                  widget.controller.countError ??
                  'This accepted count is not currently available for review. Refresh and retry.',
            );
          }
          return;
        }
      } else {
        await widget.controller.closeCount(evidence: evidence);
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The count could not be saved. Check the observation time and current revision; your input is kept.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final item in widget.controller.state.items)
        item.id: item.canonicalName,
    };
    return AlertDialog(
      title: Text(
        widget.acceptedReview
            ? 'Review accepted count'
            : 'Finish and review count',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.session.locationId == 'primary'
                      ? 'Scope: whole home. Only the listed products are observed; omitted products never become zero.'
                      : 'Scope: selected location. This count cannot replace the whole-home balance.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _observed,
                  key: const Key('count-observed-at'),
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Actual physical observation time',
                    hintText: 'YYYY-MM-DDTHH:mm:ss+02:00',
                    helperText:
                        'Include Z (UTC) or an explicit timezone offset.',
                  ),
                  validator: (value) {
                    try {
                      parseCountObservation(value ?? '');
                      return null;
                    } on FormatException {
                      return 'Enter a real observation time with timezone offset.';
                    }
                  },
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _observed.text = DateTime.now()
                              .toUtc()
                              .toIso8601String();
                        }),
                  child: const Text('Use current time (UTC)'),
                ),
                Text(
                  widget.session.observedTimezone == null
                      ? 'The server verifies and captures the household timezone. Entry and finishing times do not establish when stock was observed.'
                      : 'Captured household timezone: ${widget.session.observedTimezone}. Review the actual observation time independently from entry time.',
                ),
                CheckboxListTile(
                  key: const Key('count-complete-scope'),
                  contentPadding: EdgeInsets.zero,
                  value: _complete,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _complete = value!),
                  title: const Text(
                    'The listed products were counted completely within this scope',
                  ),
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _reliability,
                  key: const Key('count-reliability'),
                  decoration: const InputDecoration(
                    labelText: 'Observation reliability',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'unassessed',
                      child: Text(
                        'Unassessed — no reliability claim',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'partial',
                      child: Text(
                        'Partial — incomplete or uncertain',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'reliable',
                      child: Text(
                        'Reliable — checked complete observation',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _reliability = value!),
                ),
                if (widget.acceptedReview) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Corrections keep the original product identities and audit evidence. Accepted stock remains unchanged until server chronology readback.',
                  ),
                  for (final line in widget.session.confirmedLines)
                    TextFormField(
                      controller: _quantities[line.id],
                      enabled: !_busy,
                      key: ValueKey('count-correction-${line.id}'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: names[line.itemId] ?? 'Counted product',
                        helperText:
                            'Accepted: ${_quantity(line.observedQuantity!)} ${line.unit ?? 'unit unavailable'}',
                      ),
                      validator: (value) =>
                          RegExp(
                            r'^(?:0|[1-9]\d{0,8})(?:\.\d{1,8})?$',
                          ).hasMatch(value?.trim() ?? '')
                          ? null
                          : 'Enter a nonnegative quantity with at most eight decimals.',
                    ),
                  TextFormField(
                    controller: _reason,
                    enabled: !_busy,
                    maxLength: 191,
                    key: const Key('count-review-reason'),
                    decoration: const InputDecoration(
                      labelText: 'Reason for audited review',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Explain this evidence correction.'
                        : null,
                  ),
                ],
                if (_error != null)
                  Text(_error!, key: const Key('count-evidence-error')),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          key: const Key('save-count-evidence'),
          onPressed: _busy ? null : _submit,
          child: Text(
            _busy
                ? 'Saving…'
                : widget.acceptedReview
                ? 'Queue audited review'
                : 'Finish count',
          ),
        ),
      ],
    );
  }
}
