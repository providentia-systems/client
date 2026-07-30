import 'package:flutter/foundation.dart';
import 'package:providentia/features/reporting/application/household_report_service.dart';
import 'package:providentia/features/reporting/domain/household_report.dart';

enum ReportingStatus {
  idle,
  loading,
  ready,
  contractUnavailable,
  forbidden,
  failure,
}

final class ReportingController extends ChangeNotifier {
  factory ReportingController({
    required HouseholdReportService service,
    required String activeHomeId,
  }) => ReportingController._(service, activeHomeId);

  ReportingController._(this._service, this._activeHomeId);

  final HouseholdReportService _service;

  String _activeHomeId;
  ReportingStatus _status = ReportingStatus.idle;
  HouseholdReport? _report;
  int _loadGeneration = 0;

  String get activeHomeId => _activeHomeId;
  HouseholdReport? get report => _report;
  ReportingStatus get status => _status;

  Future<void> load() async {
    final generation = ++_loadGeneration;
    final requestedHomeId = _activeHomeId;
    _status = ReportingStatus.loading;
    _report = null;
    notifyListeners();
    try {
      final loaded = await _service.load(homeId: requestedHomeId);
      if (generation != _loadGeneration || requestedHomeId != _activeHomeId) {
        return;
      }
      _report = loaded;
      _status = ReportingStatus.ready;
    } on ReportContractUnavailableException {
      if (generation == _loadGeneration) {
        _status = ReportingStatus.contractUnavailable;
      }
    } on ReportForbiddenException {
      if (generation == _loadGeneration) {
        _status = ReportingStatus.forbidden;
      }
    } on Exception {
      if (generation == _loadGeneration) {
        _status = ReportingStatus.failure;
      }
    }
    if (generation == _loadGeneration) {
      notifyListeners();
    }
  }

  void switchHome(String homeId) {
    if (homeId.trim().isEmpty) {
      throw ArgumentError.value(homeId, 'homeId', 'must not be empty');
    }
    if (_activeHomeId == homeId) {
      return;
    }
    _activeHomeId = homeId;
    _loadGeneration++;
    _report = null;
    _status = ReportingStatus.idle;
    notifyListeners();
  }
}
