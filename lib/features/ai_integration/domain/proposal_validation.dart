import 'package:providentia/features/ai_integration/domain/ai_models.dart';

final class ProposalValidationException implements Exception {
  ProposalValidationException(Iterable<String> issues)
    : issues = List<String>.unmodifiable(issues);

  final List<String> issues;

  @override
  String toString() => 'ProposalValidationException(${issues.join('; ')})';
}

abstract final class AiProposalSchemas {
  static const String receiptVersion = 'receipt-v1';
  static const String stockPhotoVersion = 'stock-photo-v1';

  static Map<String, Object> get receiptV1 => <String, Object>{
    'type': 'object',
    'additionalProperties': false,
    'required': <String>[
      'schemaVersion',
      'classification',
      'header',
      'lines',
      'warnings',
    ],
    'properties': <String, Object>{
      'schemaVersion': <String, Object>{
        'type': 'string',
        'const': receiptVersion,
      },
      'classification': <String, Object>{
        'type': 'string',
        'enum': <String>[
          'receipt',
          'invoice',
          'medicine_leaflet',
          'other',
          'unknown',
        ],
      },
      'header': <String, Object>{
        'type': 'object',
        'additionalProperties': false,
        'required': _receiptHeaderKeys,
        'properties': <String, Object>{
          for (final key in _receiptHeaderKeys)
            key: _fieldSchema(<String>['string', 'null']),
        },
      },
      'lines': <String, Object>{
        'type': 'array',
        'maxItems': AiProposalValidator.maximumReceiptLines,
        'items': <String, Object>{
          'type': 'object',
          'additionalProperties': false,
          'required': _receiptLineKeys,
          'properties': <String, Object>{
            'lineId': <String, Object>{'type': 'string'},
            'rawText': <String, Object>{'type': 'string'},
            for (final key in _receiptStringFieldKeys)
              key: _fieldSchema(<String>['string', 'null']),
            'quantity': _fieldSchema(<String>['number', 'null']),
            'confidence': <String, Object>{
              'type': 'number',
              'minimum': 0,
              'maximum': 1,
            },
            'warnings': <String, Object>{
              'type': 'array',
              'items': <String, Object>{'type': 'string'},
            },
            'region': _regionSchema,
          },
        },
      },
      'warnings': <String, Object>{
        'type': 'array',
        'items': <String, Object>{'type': 'string'},
      },
    },
  };

  static Map<String, Object> get stockPhotoV1 => <String, Object>{
    'type': 'object',
    'additionalProperties': false,
    'required': <String>[
      'schemaVersion',
      'classification',
      'candidates',
      'warnings',
    ],
    'properties': <String, Object>{
      'schemaVersion': <String, Object>{
        'type': 'string',
        'const': stockPhotoVersion,
      },
      'classification': <String, Object>{
        'type': 'string',
        'enum': <String>[
          'pantry_stock',
          'household_stock',
          'medicine',
          'unrelated',
          'unknown',
        ],
      },
      'candidates': <String, Object>{
        'type': 'array',
        'maxItems': AiProposalValidator.maximumStockCandidates,
        'items': <String, Object>{
          'type': 'object',
          'additionalProperties': false,
          'required': _stockCandidateKeys,
          'properties': <String, Object>{
            'candidateId': <String, Object>{'type': 'string'},
            for (final key in <String>[
              'brand',
              'productName',
              'variant',
              'packDescription',
            ])
              key: _fieldSchema(<String>['string', 'null']),
            'quantityMinimum': <String, Object>{'type': 'number'},
            'quantityMaximum': <String, Object>{'type': 'number'},
            'confidence': <String, Object>{
              'type': 'number',
              'minimum': 0,
              'maximum': 1,
            },
            'warnings': <String, Object>{
              'type': 'array',
              'items': <String, Object>{'type': 'string'},
            },
            'region': _regionSchema,
          },
        },
      },
      'warnings': <String, Object>{
        'type': 'array',
        'items': <String, Object>{'type': 'string'},
      },
    },
  };

  static const List<String> _receiptHeaderKeys = <String>[
    'purchaseDate',
    'storeName',
    'receiptNumber',
    'currency',
    'subtotal',
    'taxTotal',
    'discountTotal',
    'total',
  ];

  static const List<String> _receiptStringFieldKeys = <String>[
    'brand',
    'productName',
    'productFamily',
    'variant',
    'packDescription',
    'unitPrice',
    'lineTotal',
    'discount',
    'tax',
    'notes',
  ];

  static const List<String> _receiptLineKeys = <String>[
    'lineId',
    'rawText',
    ..._receiptStringFieldKeys,
    'quantity',
    'confidence',
    'warnings',
    'region',
  ];

  static const List<String> _stockCandidateKeys = <String>[
    'candidateId',
    'brand',
    'productName',
    'variant',
    'packDescription',
    'quantityMinimum',
    'quantityMaximum',
    'confidence',
    'warnings',
    'region',
  ];

  static Map<String, Object> _fieldSchema(List<String> types) =>
      <String, Object>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['value', 'confidence'],
        'properties': <String, Object>{
          'value': <String, Object>{'type': types},
          'confidence': <String, Object>{
            'type': 'number',
            'minimum': 0,
            'maximum': 1,
          },
        },
      };

  static const Map<String, Object> _regionSchema = <String, Object>{
    'type': <String>['object', 'null'],
    'additionalProperties': false,
    'required': <String>['pageIndex', 'x', 'y', 'width', 'height'],
    'properties': <String, Object>{
      'pageIndex': <String, Object>{'type': 'integer', 'minimum': 0},
      'x': <String, Object>{'type': 'number', 'minimum': 0, 'maximum': 1},
      'y': <String, Object>{'type': 'number', 'minimum': 0, 'maximum': 1},
      'width': <String, Object>{
        'type': 'number',
        'exclusiveMinimum': 0,
        'maximum': 1,
      },
      'height': <String, Object>{
        'type': 'number',
        'exclusiveMinimum': 0,
        'maximum': 1,
      },
    },
  };
}

abstract final class AiProposalValidator {
  static const int maximumReceiptLines = 300;
  static const int maximumStockCandidates = 100;
  static const int maximumWarnings = 50;
  static const int maximumTextLength = 500;
  static const int maximumRawLineLength = 1000;
  static final RegExp _decimalPattern = RegExp(
    r'^(0|[1-9][0-9]{0,11})(\.[0-9]{1,4})?$',
  );
  static final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');
  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static ReceiptProposal receiptFromJson({
    required String proposalId,
    required String runId,
    required Object? json,
  }) {
    final root = _mapAt(json, r'$');
    _exactKeys(root, <String>{
      'schemaVersion',
      'classification',
      'header',
      'lines',
      'warnings',
    }, r'$');
    final version = _stringAt(root['schemaVersion'], r'$.schemaVersion');
    if (version != AiProposalSchemas.receiptVersion) {
      _fail(r'$.schemaVersion must be receipt-v1');
    }
    final classification = _receiptClassification(
      _stringAt(root['classification'], r'$.classification'),
    );
    final headerMap = _mapAt(root['header'], r'$.header');
    _exactKeys(
      headerMap,
      AiProposalSchemas._receiptHeaderKeys.toSet(),
      r'$.header',
    );
    final header = ReceiptHeaderProposal(
      purchaseDate: _stringField(
        headerMap['purchaseDate'],
        r'$.header.purchaseDate',
        semantic: _dateOrNull,
      ),
      storeName: _stringField(headerMap['storeName'], r'$.header.storeName'),
      receiptNumber: _stringField(
        headerMap['receiptNumber'],
        r'$.header.receiptNumber',
      ),
      currency: _stringField(
        headerMap['currency'],
        r'$.header.currency',
        semantic: _currencyOrNull,
      ),
      subtotal: _stringField(
        headerMap['subtotal'],
        r'$.header.subtotal',
        semantic: _decimalOrNull,
      ),
      taxTotal: _stringField(
        headerMap['taxTotal'],
        r'$.header.taxTotal',
        semantic: _decimalOrNull,
      ),
      discountTotal: _stringField(
        headerMap['discountTotal'],
        r'$.header.discountTotal',
        semantic: _decimalOrNull,
      ),
      total: _stringField(
        headerMap['total'],
        r'$.header.total',
        semantic: _decimalOrNull,
      ),
    );
    final rawLines = _listAt(root['lines'], r'$.lines');
    if (rawLines.length > maximumReceiptLines) {
      _fail(r'$.lines exceeds the 300-line safety limit');
    }
    final lines = <ReceiptLineProposal>[
      for (var index = 0; index < rawLines.length; index++)
        _receiptLine(rawLines[index], index),
    ];
    if (lines.map((line) => line.lineId).toSet().length != lines.length) {
      _fail(r'$.lines contains duplicate lineId values');
    }
    if (classification != ReceiptDocumentClassification.receipt &&
        classification != ReceiptDocumentClassification.invoice &&
        lines.isNotEmpty) {
      _fail(r'$.lines must be empty when the document is not a receipt');
    }
    return ReceiptProposal(
      id: proposalId,
      runId: runId,
      schemaVersion: version,
      classification: classification,
      header: header,
      lines: lines,
      warnings: _warnings(root['warnings'], r'$.warnings'),
    );
  }

  static StockPhotoProposal stockPhotoFromJson({
    required String proposalId,
    required String runId,
    required Object? json,
  }) {
    final root = _mapAt(json, r'$');
    _exactKeys(root, <String>{
      'schemaVersion',
      'classification',
      'candidates',
      'warnings',
    }, r'$');
    final version = _stringAt(root['schemaVersion'], r'$.schemaVersion');
    if (version != AiProposalSchemas.stockPhotoVersion) {
      _fail(r'$.schemaVersion must be stock-photo-v1');
    }
    final classification = _stockClassification(
      _stringAt(root['classification'], r'$.classification'),
    );
    final rawCandidates = _listAt(root['candidates'], r'$.candidates');
    if (rawCandidates.length > maximumStockCandidates) {
      _fail(r'$.candidates exceeds the 100-candidate safety limit');
    }
    final candidates = <StockCandidateProposal>[
      for (var index = 0; index < rawCandidates.length; index++)
        _stockCandidate(rawCandidates[index], index),
    ];
    if (candidates.map((item) => item.candidateId).toSet().length !=
        candidates.length) {
      _fail(r'$.candidates contains duplicate candidateId values');
    }
    if ((classification == StockImageClassification.medicine ||
            classification == StockImageClassification.unrelated ||
            classification == StockImageClassification.unknown) &&
        candidates.isNotEmpty) {
      _fail(r'$.candidates must be empty for quarantined or unknown images');
    }
    return StockPhotoProposal(
      id: proposalId,
      runId: runId,
      schemaVersion: version,
      classification: classification,
      candidates: candidates,
      warnings: _warnings(root['warnings'], r'$.warnings'),
    );
  }

  static ReceiptLineProposal _receiptLine(Object? value, int index) {
    final path = '\$.lines[$index]';
    final map = _mapAt(value, path);
    _exactKeys(map, AiProposalSchemas._receiptLineKeys.toSet(), path);
    final lineId = _stringAt(map['lineId'], '$path.lineId');
    final rawText = _stringAt(
      map['rawText'],
      '$path.rawText',
      maximumLength: maximumRawLineLength,
    );
    if (lineId.trim().isEmpty || rawText.trim().isEmpty) {
      _fail('$path requires non-empty lineId and rawText');
    }
    return ReceiptLineProposal(
      lineId: lineId,
      rawText: rawText,
      brand: _stringField(map['brand'], '$path.brand'),
      productName: _stringField(map['productName'], '$path.productName'),
      productFamily: _stringField(map['productFamily'], '$path.productFamily'),
      variant: _stringField(map['variant'], '$path.variant'),
      packDescription: _stringField(
        map['packDescription'],
        '$path.packDescription',
      ),
      quantity: _numberField(map['quantity'], '$path.quantity', positive: true),
      unitPrice: _stringField(
        map['unitPrice'],
        '$path.unitPrice',
        semantic: _decimalOrNull,
      ),
      lineTotal: _stringField(
        map['lineTotal'],
        '$path.lineTotal',
        semantic: _decimalOrNull,
      ),
      discount: _stringField(
        map['discount'],
        '$path.discount',
        semantic: _decimalOrNull,
      ),
      tax: _stringField(map['tax'], '$path.tax', semantic: _decimalOrNull),
      notes: _stringField(map['notes'], '$path.notes'),
      confidence: _confidence(map['confidence'], '$path.confidence'),
      warnings: _warnings(map['warnings'], '$path.warnings'),
      region: _region(map['region'], '$path.region'),
    );
  }

  static StockCandidateProposal _stockCandidate(Object? value, int index) {
    final path = '\$.candidates[$index]';
    final map = _mapAt(value, path);
    _exactKeys(map, AiProposalSchemas._stockCandidateKeys.toSet(), path);
    final minimum = _positiveNumber(
      map['quantityMinimum'],
      '$path.quantityMinimum',
      allowZero: true,
    );
    final maximum = _positiveNumber(
      map['quantityMaximum'],
      '$path.quantityMaximum',
      allowZero: true,
    );
    if (maximum < minimum) {
      _fail('$path.quantityMaximum must be at least quantityMinimum');
    }
    final candidateId = _stringAt(map['candidateId'], '$path.candidateId');
    if (candidateId.trim().isEmpty) {
      _fail('$path.candidateId cannot be empty');
    }
    return StockCandidateProposal(
      candidateId: candidateId,
      brand: _stringField(map['brand'], '$path.brand'),
      productName: _stringField(map['productName'], '$path.productName'),
      variant: _stringField(map['variant'], '$path.variant'),
      packDescription: _stringField(
        map['packDescription'],
        '$path.packDescription',
      ),
      quantityMinimum: minimum,
      quantityMaximum: maximum,
      confidence: _confidence(map['confidence'], '$path.confidence'),
      warnings: _warnings(map['warnings'], '$path.warnings'),
      region: _region(map['region'], '$path.region'),
    );
  }

  static ExtractedField<String> _stringField(
    Object? value,
    String path, {
    bool Function(String?)? semantic,
  }) {
    final map = _mapAt(value, path);
    _exactKeys(map, <String>{'value', 'confidence'}, path);
    final raw = map['value'];
    if (raw != null && raw is! String) {
      _fail('$path.value must be a string or null');
    }
    final stringValue = raw as String?;
    if (stringValue != null && stringValue.length > maximumTextLength) {
      _fail('$path.value exceeds the 500-character safety limit');
    }
    if (semantic != null && !semantic(stringValue)) {
      _fail('$path.value has an invalid format');
    }
    return ExtractedField<String>(
      value: stringValue,
      confidence: _confidence(map['confidence'], '$path.confidence'),
    );
  }

  static ExtractedField<double> _numberField(
    Object? value,
    String path, {
    required bool positive,
  }) {
    final map = _mapAt(value, path);
    _exactKeys(map, <String>{'value', 'confidence'}, path);
    final raw = map['value'];
    double? number;
    if (raw != null) {
      if (raw is! num) {
        _fail('$path.value must be a number or null');
      }
      number = raw.toDouble();
      if (!number.isFinite || (positive && number <= 0) || number > 100000) {
        _fail('$path.value is outside the accepted range');
      }
    }
    return ExtractedField<double>(
      value: number,
      confidence: _confidence(map['confidence'], '$path.confidence'),
    );
  }

  static NormalizedRegion? _region(Object? value, String path) {
    if (value == null) {
      return null;
    }
    final map = _mapAt(value, path);
    _exactKeys(map, <String>{'pageIndex', 'x', 'y', 'width', 'height'}, path);
    final pageIndex = map['pageIndex'];
    if (pageIndex is! int || pageIndex < 0 || pageIndex > 999) {
      _fail('$path.pageIndex is outside the accepted range');
    }
    final x = _unitNumber(map['x'], '$path.x', allowZero: true);
    final y = _unitNumber(map['y'], '$path.y', allowZero: true);
    final width = _unitNumber(map['width'], '$path.width');
    final height = _unitNumber(map['height'], '$path.height');
    if (x + width > 1.000001 || y + height > 1.000001) {
      _fail('$path must fit within normalized image bounds');
    }
    return NormalizedRegion(
      pageIndex: pageIndex,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  static Map<String, Object?> _mapAt(Object? value, String path) {
    if (value is! Map<Object?, Object?>) {
      _fail('$path must be an object');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        _fail('$path contains a non-string property');
      }
      result[key] = entry.value;
    }
    return result;
  }

  static List<Object?> _listAt(Object? value, String path) {
    if (value is! List<Object?>) {
      _fail('$path must be an array');
    }
    return value;
  }

  static void _exactKeys(
    Map<String, Object?> value,
    Set<String> expected,
    String path,
  ) {
    final actual = value.keys.toSet();
    if (actual.length != expected.length ||
        !actual.containsAll(expected) ||
        !expected.containsAll(actual)) {
      final missing = expected.difference(actual).join(', ');
      final extra = actual.difference(expected).join(', ');
      _fail(
        '$path has an invalid shape'
        '${missing.isEmpty ? '' : '; missing: $missing'}'
        '${extra.isEmpty ? '' : '; extra: $extra'}',
      );
    }
  }

  static String _stringAt(
    Object? value,
    String path, {
    int maximumLength = maximumTextLength,
  }) {
    if (value is! String) {
      _fail('$path must be a string');
    }
    if (value.length > maximumLength) {
      _fail('$path exceeds the allowed length');
    }
    return value;
  }

  static double _confidence(Object? value, String path) =>
      _unitNumber(value, path, allowZero: true);

  static double _unitNumber(
    Object? value,
    String path, {
    bool allowZero = false,
  }) {
    if (value is! num) {
      _fail('$path must be a number');
    }
    final number = value.toDouble();
    if (!number.isFinite ||
        number > 1 ||
        (allowZero ? number < 0 : number <= 0)) {
      _fail(
        '$path must be ${allowZero ? 'between' : 'greater than 0 and at most'} 1',
      );
    }
    return number;
  }

  static double _positiveNumber(
    Object? value,
    String path, {
    bool allowZero = false,
  }) {
    if (value is! num) {
      _fail('$path must be a number');
    }
    final number = value.toDouble();
    if (!number.isFinite ||
        number > 100000 ||
        (allowZero ? number < 0 : number <= 0)) {
      _fail('$path is outside the accepted range');
    }
    return number;
  }

  static List<String> _warnings(Object? value, String path) {
    final list = _listAt(value, path);
    if (list.length > maximumWarnings) {
      _fail('$path exceeds the 50-warning safety limit');
    }
    return <String>[
      for (var index = 0; index < list.length; index++)
        _stringAt(list[index], '$path[$index]'),
    ];
  }

  static ReceiptDocumentClassification _receiptClassification(String value) =>
      switch (value) {
        'receipt' => ReceiptDocumentClassification.receipt,
        'invoice' => ReceiptDocumentClassification.invoice,
        'medicine_leaflet' => ReceiptDocumentClassification.medicineLeaflet,
        'other' => ReceiptDocumentClassification.other,
        'unknown' => ReceiptDocumentClassification.unknown,
        _ => _fail('Unknown receipt classification'),
      };

  static StockImageClassification _stockClassification(String value) =>
      switch (value) {
        'pantry_stock' => StockImageClassification.pantryStock,
        'household_stock' => StockImageClassification.householdStock,
        'medicine' => StockImageClassification.medicine,
        'unrelated' => StockImageClassification.unrelated,
        'unknown' => StockImageClassification.unknown,
        _ => _fail('Unknown stock image classification'),
      };

  static bool _decimalOrNull(String? value) =>
      value == null || _decimalPattern.hasMatch(value);

  static bool _currencyOrNull(String? value) =>
      value == null || _currencyPattern.hasMatch(value);

  static bool _dateOrNull(String? value) {
    if (value == null) {
      return true;
    }
    if (!_datePattern.hasMatch(value)) {
      return false;
    }
    final parsed = DateTime.tryParse(value);
    return parsed != null && parsed.toIso8601String().startsWith(value);
  }

  static Never _fail(String issue) {
    throw ProposalValidationException(<String>[issue]);
  }
}
