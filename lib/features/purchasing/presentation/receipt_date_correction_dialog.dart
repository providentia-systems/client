import 'package:flutter/material.dart';
import 'package:providentia/features/purchasing/domain/purchase_calendar.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';

class ReceiptDateCorrectionDialog extends StatefulWidget {
  const ReceiptDateCorrectionDialog({
    required this.controller,
    required this.receipt,
    super.key,
  });
  final PurchasingController controller;
  final PurchaseReceiptCapture receipt;
  @override
  State<ReceiptDateCorrectionDialog> createState() =>
      _ReceiptDateCorrectionDialogState();
}

class _ReceiptDateCorrectionDialogState
    extends State<ReceiptDateCorrectionDialog> {
  final _form = GlobalKey<FormState>();
  late final _date = TextEditingController(
    text: formatPurchaseDay(widget.receipt.purchaseDate),
  );
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _date.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Correct purchase day'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Existing purchase day: ${formatPurchaseDay(widget.receipt.purchaseDate)}',
              ),
              Text('Opened receipt revision ${widget.receipt.revision}'),
              const Text(
                'The receipt identity and creation time stay fixed. This audited correction reconciles purchase history and stock chronology; it does not record another purchase.',
              ),
              TextFormField(
                key: const Key('receipt-correction-date'),
                controller: _date,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Proposed purchase day (YYYY-MM-DD)',
                ),
                validator: (value) {
                  try {
                    final day = parsePurchaseDay(value?.trim() ?? '');
                    return formatPurchaseDay(day) ==
                            formatPurchaseDay(widget.receipt.purchaseDate)
                        ? 'Choose a different purchase day.'
                        : null;
                  } on FormatException catch (error) {
                    return error.message;
                  }
                },
              ),
              TextFormField(
                key: const Key('receipt-correction-reason'),
                controller: _reason,
                enabled: !_saving,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Correction reason',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Give the reason for changing this purchase day.'
                    : null,
              ),
              const Text(
                'Saving queues the correction on this device. The server validates the household purchase day and current revision when synchronization is available.',
              ),
              if (_saving) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(
                  _error!,
                  key: const Key('receipt-correction-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const Text(
                  'Your entries are retained. Refresh and review current values, then reopen the latest revision before submitting a different correction.',
                ),
                TextButton(
                  key: const Key('receipt-correction-refresh'),
                  onPressed: _saving ? null : _refresh,
                  child: const Text('Refresh authoritative receipt details'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('receipt-correction-save'),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Queue audited correction'),
      ),
    ],
  );
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.controller.correctPurchaseDate(
      original: widget.receipt,
      purchaseDate: parsePurchaseDay(_date.text.trim()),
      reason: _reason.text,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error =
            widget.controller.state.captureError ??
            'The correction could not be saved. Your entries are retained.';
      });
    }
  }

  Future<void> _refresh() async {
    await widget.controller.retrySynchronization();
    await widget.controller.refreshReceiptHistory(widget.receipt.id);
    if (!mounted) return;
    final current = widget.controller.state.capture;
    setState(
      () => _error = current?.id == widget.receipt.id
          ? 'Current saved revision ${current!.revision}, purchase day ${formatPurchaseDay(current.purchaseDate)}. Your proposed day and reason are retained.'
          : 'The receipt selection changed. Your entries are retained; reopen the intended receipt.',
    );
  }
}
