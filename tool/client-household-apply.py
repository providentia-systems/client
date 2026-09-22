from pathlib import Path
root = Path(__file__).resolve().parents[1]
def edit(name, old, new):
    path = root / name
    source = path.read_text()
    if old in source:
        path.write_text(source.replace(old, new))
    elif new not in source:
        raise RuntimeError('Expected source not found: ' + name)
edit('lib/core/database/drift_household_repository.dart',
     "    if (globalCategoryId != null)\n      _requireUuid(globalCategoryId, 'global category');",
     "    if (globalCategoryId != null) {\n      _requireUuid(globalCategoryId, 'global category');\n    }")
edit('lib/core/database/drift_household_repository.dart',
     "    if (draft.globalCategoryId != null)\n      _requireUuid(draft.globalCategoryId!, 'global category');",
     "    if (draft.globalCategoryId != null) {\n      _requireUuid(draft.globalCategoryId!, 'global category');\n    }")
edit('lib/core/database/drift_household_repository.dart',
     "        if (item.catalogCategoryId != null)\n          _requireUuid(item.catalogCategoryId!, 'catalog category');",
     "        if (item.catalogCategoryId != null) {\n          _requireUuid(item.catalogCategoryId!, 'catalog category');\n        }")
edit('lib/core/database/drift_household_repository.dart',
     "        if (unit != null) 'unit': unit,", "        'unit': ?unit,")
edit('lib/features/inventory/presentation/inventory_workspace.dart',
     "                if (value != null)\n                  setState(() {\n                    _reason = value;\n                    _error = null;\n                  });",
     "                if (value != null) {\n                  setState(() {\n                    _reason = value;\n                    _error = null;\n                  });\n                }")
edit('test/features/inventory/inventory_controller_test.dart',
     'This name and pack text stay private to the active home.',
     'This product stays private to your home, even when you select a global category.')
p = root / 'test/core/database/drift_household_repository_test.dart'
s = p.read_text(); start = s.index("    'private product creation is atomic private and protocol allowlisted',"); end = s.index("    'private product creation fails closed", start)
part = s[start:end].replace("        'homeCategoryId': _homeCategoryId,\n", "        'homeCategoryId': _homeCategoryId,\n        'globalCategoryId': null,\n        'unit': 'units',\n").replace('expect(command.keys, hasLength(5));', 'expect(command.keys, hasLength(7));')
if "'globalCategoryId': null" not in s[start:end]:
    p.write_text(s[:start] + part + s[end:])
edit('test/core/database/household_metadata_roundtrip_test.dart',
     "payload: jsonEncode({...data, 'id': id, 'revision': 1}),",
     "payload: jsonEncode({...data, if (type == 'inventory-balance') 'homeProductId': id, 'id': id, 'revision': 1}),")
edit('test/features/inventory/household_workflow_acceptance_test.dart',
     "        await _workspace(tester, repository, scale: scale);\n        await tester.ensureVisible(find.text('Apple'));",
     "        await _workspace(tester, repository, scale: scale);\n        await tester.scrollUntilVisible(find.text('Apple'), 180, scrollable: find.byType(Scrollable).first);\n        await tester.ensureVisible(find.text('Apple'));")
