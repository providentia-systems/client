from pathlib import Path
root = Path.cwd()
def replace(path, old, new):
    p=root/path; s=p.read_text(); assert old in s,path; p.write_text(s.replace(old,new))
replace('lib/features/ai_integration/application/receipt_ai_handoff_controller.dart','await recovery.findIntakeReceipt(', 'await (recovery as PurchaseIntakeRecoveryRepository).findIntakeReceipt(')
for method in ['reviewObservation','reviewDiscrepancy']:
    replace('lib/features/ai_integration/presentation/server_ai_workspace_controller.dart',f'() => repository.{method}(',f'() => (repository as AiEvidenceReviewRepository).{method}(')
replace('lib/features/data_governance/application/data_governance_service.dart','return repository.retrieveExport(request, isCurrent: isCurrent);','return (repository as DataExportRepository).retrieveExport(request, isCurrent: isCurrent);')
replace('lib/features/data_governance/infrastructure/platform_data_export_saver_native.dart',"import 'package:flutter/services.dart';", "import 'platform_data_export_ios_channel.dart';")
replace('lib/features/data_governance/infrastructure/platform_data_export_saver_native.dart',"static const _channel = MethodChannel('providentia/data-export');",'static const _channel = IosDataExportChannel();')
replace('lib/features/data_governance/infrastructure/platform_data_export_saver_native.dart',"await _channel.invokeMethod<bool>('save', <String, Object?>{\n        'filename': artifact.filename,\n        'bytes': artifact.bytes,\n      });",'await _channel.save(artifact.filename, artifact.bytes);')
replace('lib/features/data_governance/infrastructure/platform_data_export_saver_native.dart',"await _channel.invokeMethod<void>('discard')",'await _channel.discard()')
for name in ['receipt_ai_handoff_parser_test.dart','generated_server_ai_repository_test.dart']:
    path='test/features/ai_integration/'+name
    replace(path,"  'status': 'review_required',", "  'status': 'review_required',\n  'targetId': null,")
    if name.startswith('receipt_'):
        replace(path,"  'targetId': null,", "  'targetId': null,\n  'observationDecisions': <Object?>[],\n  'discrepancies': <Object?>[],")
replace('test/features/inventory/stock_photo_count_controller_test.dart',"'duplicate cross-image candidates cannot create two count lines'","'similar candidates stay visible until explicit human review'")
replace('test/features/inventory/stock_photo_count_controller_test.dart',"expect(harness.stock.state.candidates, hasLength(1));\n      expect(\n        harness.stock.state.safeMessage,\n        contains('overlapping candidate removed'),\n      );", "expect(harness.stock.state.candidates, hasLength(2));\n      expect(harness.repository.saved.last.lines, isEmpty);\n      expect(harness.repository.movements, isEmpty);")
replace('lib/features/ai_integration/infrastructure/drift_ai_review_resume_store.dart',"      final Object? decoded = jsonDecode(row.payload);", "      final Object? decoded;\n      try {\n        decoded = jsonDecode(row.payload);\n      } on FormatException {\n        continue; // Corrupt hints never replace authoritative server review.\n      }")
