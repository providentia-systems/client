import 'package:providentia/features/reporting/domain/household_report.dart';

final class ReportContractUnavailableException implements Exception {
  const ReportContractUnavailableException();
}

final class ReportForbiddenException implements Exception {
  const ReportForbiddenException();
}

final class CrossHomeReportDataException implements Exception {
  const CrossHomeReportDataException();
}

abstract interface class HouseholdReportRepository {
  Future<HouseholdReport> load({required String homeId});
}

final class UnavailableHouseholdReportRepository
    implements HouseholdReportRepository {
  const UnavailableHouseholdReportRepository();

  @override
  Future<HouseholdReport> load({required String homeId}) async {
    throw const ReportContractUnavailableException();
  }
}

final class HouseholdReportService {
  const HouseholdReportService(this._repository);

  final HouseholdReportRepository _repository;

  Future<HouseholdReport> load({required String homeId}) async {
    if (homeId.trim().isEmpty) {
      throw ArgumentError.value(homeId, 'homeId', 'must not be empty');
    }
    final report = await _repository.load(homeId: homeId);
    if (report.homeId != homeId ||
        report.allScopedLines.any((line) => line.homeId != homeId)) {
      throw const CrossHomeReportDataException();
    }
    return report;
  }
}
