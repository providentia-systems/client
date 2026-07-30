import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/administration/application/catalog_administration_ports.dart';
import 'package:providentia/features/administration/domain/catalog_administration_models.dart';

enum CatalogWorkbenchStatus {
  idle,
  loading,
  ready,
  contractUnavailable,
  forbidden,
  conflict,
  stale,
  failure,
}

final class CatalogWorkbenchController extends ChangeNotifier {
  CatalogWorkbenchController(this._repository);

  final CatalogModerationRepository _repository;

  CatalogWorkbenchStatus _status = CatalogWorkbenchStatus.idle;
  List<CatalogQueueItem> _items = const <CatalogQueueItem>[];
  List<CatalogAuditEvent> _auditEvents = const <CatalogAuditEvent>[];
  String? _selectedItemId;
  bool _disposed = false;

  Set<CatalogCapability> get capabilities => _repository.capabilities;
  List<CatalogQueueItem> get items => _items;
  List<CatalogAuditEvent> get auditEvents => _auditEvents;
  String? get selectedItemId => _selectedItemId;
  CatalogWorkbenchStatus get status => _status;

  CatalogQueueItem? get selectedItem {
    for (final item in _items) {
      if (item.id == _selectedItemId) {
        return item;
      }
    }
    return null;
  }

  Future<void> refresh() async {
    if (!capabilities.contains(CatalogCapability.review)) {
      _setStatus(CatalogWorkbenchStatus.forbidden);
      return;
    }
    _setStatus(CatalogWorkbenchStatus.loading);
    try {
      final loaded = await _repository.loadQueue();
      _items = List<CatalogQueueItem>.unmodifiable(loaded);
      if (_repository case final CatalogAuditRepository auditRepository) {
        _auditEvents = capabilities.contains(CatalogCapability.readAudit)
            ? List<CatalogAuditEvent>.unmodifiable(
                await auditRepository.loadAudit(),
              )
            : const <CatalogAuditEvent>[];
      }
      if (!_items.any((item) => item.id == _selectedItemId)) {
        _selectedItemId = _items.isEmpty ? null : _items.first.id;
      }
      _setStatus(CatalogWorkbenchStatus.ready);
    } on CatalogContractUnavailableException {
      _setStatus(CatalogWorkbenchStatus.contractUnavailable);
    } on CatalogForbiddenException {
      _setStatus(CatalogWorkbenchStatus.forbidden);
    } on CatalogConflictException {
      _setStatus(CatalogWorkbenchStatus.conflict);
    } on CatalogStaleRevisionException {
      _setStatus(CatalogWorkbenchStatus.stale);
    } on Exception {
      _setStatus(CatalogWorkbenchStatus.failure);
    }
  }

  void select(String itemId) {
    if (!_items.any((item) => item.id == itemId)) {
      throw ArgumentError.value(itemId, 'itemId', 'is not in the queue');
    }
    if (_selectedItemId == itemId) {
      return;
    }
    _selectedItemId = itemId;
    notifyListeners();
  }

  void _setStatus(CatalogWorkbenchStatus value) {
    _status = value;
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
