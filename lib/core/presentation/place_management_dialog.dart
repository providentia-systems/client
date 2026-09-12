import 'package:flutter/material.dart';

/// Presentation value shared by the location and store metadata editors.
final class PlaceDetails {
  const PlaceDetails({
    this.id,
    required this.name,
    required this.detail,
    this.archived = false,
    this.revision,
  });

  final String? id;
  final String name;
  final String detail;
  final bool archived;
  final int? revision;
}

class PlaceManagementDialog extends StatelessWidget {
  const PlaceManagementDialog({
    required this.title,
    required this.singular,
    required this.detailLabel,
    required this.listenable,
    required this.entries,
    required this.save,
    this.detailOptions,
    this.maxNameLength = 191,
    super.key,
  });

  final String title;
  final String singular;
  final String detailLabel;
  final Listenable listenable;
  final List<PlaceDetails> Function() entries;
  final Future<bool> Function(PlaceDetails) save;
  final List<String>? detailOptions;
  final int maxNameLength;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 480,
      height: 360,
      child: ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          final places = entries();
          return ListView(
            children: [
              if (places.isEmpty) const Text('Nothing added yet.'),
              for (final entry in places)
                ListTile(
                  title: Text(entry.name),
                  subtitle: Text(
                    [
                      entry.detail,
                      if (entry.archived) 'Removed',
                    ].where((value) => value.isNotEmpty).join(' · '),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _edit(context, entry),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton.icon(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add),
        label: Text('Add $singular'),
      ),
    ],
  );

  Future<void> _edit(BuildContext context, PlaceDetails? entry) =>
      showDialog<void>(
        context: context,
        builder: (_) => _PlaceEditor(
          title: '${entry == null ? 'Add' : 'Edit'} $singular',
          detailLabel: detailLabel,
          initial: entry,
          save: save,
          detailOptions: detailOptions,
          maxNameLength: maxNameLength,
        ),
      );
}

class _PlaceEditor extends StatefulWidget {
  const _PlaceEditor({
    required this.title,
    required this.detailLabel,
    required this.initial,
    required this.save,
    required this.detailOptions,
    required this.maxNameLength,
  });

  final String title;
  final String detailLabel;
  final PlaceDetails? initial;
  final Future<bool> Function(PlaceDetails) save;
  final List<String>? detailOptions;
  final int maxNameLength;

  @override
  State<_PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<_PlaceEditor> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _detail = TextEditingController(
    text: widget.initial?.detail ?? widget.detailOptions?.first ?? '',
  );
  late bool _archived = widget.initial?.archived ?? false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              enabled: !_saving,
              maxLength: widget.maxNameLength,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            if (widget.detailOptions == null)
              TextField(
                controller: _detail,
                enabled: !_saving,
                maxLength: 191,
                decoration: InputDecoration(labelText: widget.detailLabel),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _detail.text,
                decoration: InputDecoration(labelText: widget.detailLabel),
                items: widget.detailOptions!
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: _saving ? null : (value) => _detail.text = value!,
              ),
            if (widget.initial != null)
              SwitchListTile(
                title: const Text('Removed'),
                subtitle: const Text(
                  'Existing history is kept. Turn off to restore.',
                ),
                value: _archived,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _archived = value),
              ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.save(
      PlaceDetails(
        id: widget.initial?.id,
        name: _name.text.trim(),
        detail: _detail.text.trim(),
        archived: _archived,
        revision: widget.initial?.revision,
      ),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error =
            'The change could not be saved. Close and refresh before retrying. '
            'Finish open counts or draft receipts before removing a place.';
      });
    }
  }
}
