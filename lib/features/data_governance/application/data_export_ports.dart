import '../domain/data_export_artifact.dart';
import '../domain/data_governance_models.dart';

/// Separate retrieval capability keeps networking out of the file-save port.
abstract interface class DataExportRepository {
  Future<DataExportArtifact> retrieveExport(
    DataGovernanceRequest request, {
    required bool Function() isCurrent,
  });
}

enum DataExportSaveResult { saved, handedToBrowser, cancelled }

abstract interface class DataExportSaver {
  Future<DataExportSaveResult> save(DataExportArtifact artifact);

  /// Invalidates pending dialogs where the platform supports cancellation and
  /// deletes only this adapter's temporary storage, never user-saved copies.
  Future<void> clearTemporaryState();
}
