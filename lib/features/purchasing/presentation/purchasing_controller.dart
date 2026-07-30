import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/purchasing/application/purchase_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/purchase_services.dart';

enum PurchaseView { recent, history }

final class PurchasingState {
  const PurchasingState({
    this.lines = const <PurchaseLine>[],
    this.view = PurchaseView.recent,
    this.loading = true,
    this.safeError,
  });

  final List<PurchaseLine> lines;
  final PurchaseView view;
  final bool loading;
  final String? safeError;
}

final class PurchasingController extends ChangeNotifier {
  PurchasingController({
    required PurchaseRepository repository,
    required this.homeId,
    PurchaseHistoryGrouper grouper = const PurchaseHistoryGrouper(),
  }) : _repository = repository,
       _grouper = grouper;

  final PurchaseRepository _repository;
  final PurchaseHistoryGrouper _grouper;
  final String homeId;
  StreamSubscription<List<PurchaseLine>>? _subscription;
  PurchasingState _state = const PurchasingState();

  PurchasingState get state => _state;
  List<PurchaseGroup> get recentGroups =>
      _grouper.groupRecent(homeId: homeId, lines: _state.lines);
  List<MonthlyPurchaseSummary> get monthlyHistory =>
      _grouper.summarizeHistory(homeId: homeId, lines: _state.lines);
  Money? get recentSpend =>
      _grouper.recentSpend(homeId: homeId, lines: _state.lines);

  void start() {
    if (_subscription != null) return;
    _subscription = _repository
        .watchPurchaseLines(homeId: homeId)
        .listen(
          (lines) {
            if (lines.any((line) => line.homeId != homeId)) {
              _state = PurchasingState(
                lines: _state.lines,
                view: _state.view,
                loading: false,
                safeError: 'Purchase-history access was rejected.',
              );
              notifyListeners();
              return;
            }
            _state = PurchasingState(
              lines: List<PurchaseLine>.unmodifiable(lines),
              view: _state.view,
              loading: false,
            );
            notifyListeners();
          },
          onError: (Object _) {
            _state = PurchasingState(
              lines: _state.lines,
              view: _state.view,
              loading: false,
              safeError: 'Purchase history could not be loaded.',
            );
            notifyListeners();
          },
        );
  }

  void selectView(PurchaseView view) {
    if (_state.view == view) return;
    _state = PurchasingState(
      lines: _state.lines,
      view: view,
      loading: _state.loading,
      safeError: _state.safeError,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
