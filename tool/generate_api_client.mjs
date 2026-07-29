#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const toolDirectory = path.dirname(fileURLToPath(import.meta.url));
const rootDirectory = path.resolve(toolDirectory, '..');
const contractPath = path.join(rootDirectory, 'contracts', 'providentia-v1.json');
const tokenPath = path.join(
  rootDirectory,
  'contracts',
  'design-tokens',
  'providentia-v1.json',
);
const generatedDirectory = path.join(
  rootDirectory,
  'contracts',
  'generated',
  'providentia_api_client',
);
const checkMode = process.argv.includes('--check');

const contractBytes = await readFile(contractPath);
const tokenBytes = await readFile(tokenPath);
const contract = JSON.parse(contractBytes.toString('utf8'));
const tokens = JSON.parse(tokenBytes.toString('utf8'));
const contractSha256 = sha256(contractBytes);
const tokenSha256 = sha256(tokenBytes);

validateContract(contract);
validateTokens(tokens);

const outputs = new Map([
  [
    path.join(rootDirectory, 'contracts', 'contract.lock.json'),
    json({
      artifact: 'providentia-openapi',
      source: 'providentia-laminas',
      version: contract.info.version,
      path: 'contracts/providentia-v1.json',
      sha256: contractSha256,
    }),
  ],
  [
    path.join(
      rootDirectory,
      'contracts',
      'design-tokens',
      'contract.lock.json',
    ),
    json({
      artifact: 'providentia-design-tokens',
      source: 'providentia-laminas',
      version: tokens.version,
      path: 'contracts/design-tokens/providentia-v1.json',
      sha256: tokenSha256,
    }),
  ],
  [
    path.join(generatedDirectory, 'pubspec.yaml'),
    generatedPubspec(),
  ],
  [
    path.join(
      generatedDirectory,
      'lib',
      'providentia_api_client.dart',
    ),
    generatedClient(contractSha256),
  ],
  [
    path.join(generatedDirectory, 'generation-manifest.json'),
    json({
      generator: 'tool/generate_api_client.mjs',
      generatorVersion: 1,
      contract: '../../providentia-v1.json',
      contractVersion: contract.info.version,
      contractSha256,
      generatedFiles: [
        'pubspec.yaml',
        'lib/providentia_api_client.dart',
      ],
      generatedCodeMustNotBeEdited: true,
    }),
  ],
]);

if (checkMode) {
  const mismatches = [];
  for (const [outputPath, expected] of outputs) {
    let actual;
    try {
      actual = await readFile(outputPath, 'utf8');
    } catch {
      mismatches.push(relative(outputPath));
      continue;
    }
    if (actual !== expected) {
      mismatches.push(relative(outputPath));
    }
  }

  if (mismatches.length > 0) {
    throw new Error(
      `Generated output is stale or missing:\n${mismatches
        .map((file) => `- ${file}`)
        .join('\n')}\nRun: node tool/generate_api_client.mjs`,
    );
  }
  process.stdout.write(
    `Contract and generated client verified (${contractSha256}).\n`,
  );
} else {
  for (const [outputPath, content] of outputs) {
    await mkdir(path.dirname(outputPath), {recursive: true});
    await writeFile(outputPath, content, 'utf8');
  }
  process.stdout.write(
    `Generated Providentia Dart client from contract ${contractSha256}.\n`,
  );
}

function validateContract(document) {
  if (document.openapi !== '3.1.0') {
    throw new Error('The Phase 1 contract must use OpenAPI 3.1.0.');
  }
  if (
    document.info?.title !== 'Providentia API' ||
    document.info?.version !== '1.0.0-foundation.1'
  ) {
    throw new Error('Unexpected API title.');
  }

  const expectedOperations = new Map([
    ['/health/live', 'getLiveness'],
    ['/health/ready', 'getReadiness'],
    ['/api/v1/system/info', 'getSystemInfo'],
    ['/metrics', 'getMetrics'],
  ]);
  for (const [resourcePath, operationId] of expectedOperations) {
    if (document.paths?.[resourcePath]?.get?.operationId !== operationId) {
      throw new Error(`Missing GET ${resourcePath} (${operationId}).`);
    }
  }

  for (const schema of [
    'HealthStatus',
    'ReadinessCheck',
    'ReadinessStatus',
    'SystemInfo',
    'ProblemDetails',
  ]) {
    if (!document.components?.schemas?.[schema]) {
      throw new Error(`Missing component schema ${schema}.`);
    }
  }

  const problem = document.components.schemas.ProblemDetails;
  if (problem.description !== 'Problem Details for HTTP APIs as defined by RFC 9457.') {
    throw new Error('ProblemDetails must explicitly implement RFC 9457.');
  }
  assertRequiredFields(document, 'HealthStatus', ['status', 'timestamp']);
  assertRequiredFields(document, 'ReadinessCheck', ['status']);
  assertRequiredFields(document, 'ReadinessStatus', ['status', 'checks']);
  assertRequiredFields(document, 'SystemInfo', [
    'product',
    'apiVersion',
    'applicationVersion',
    'environment',
    'runtime',
    'databaseDriver',
    'queueAdapter',
    'queueBroker',
  ]);
  assertRequiredFields(document, 'ProblemDetails', [
    'type',
    'title',
    'status',
    'requestId',
  ]);

  const readinessChecks =
    document.components.schemas.ReadinessStatus.properties?.checks
      ?.additionalProperties?.$ref;
  if (readinessChecks !== '#/components/schemas/ReadinessCheck') {
    throw new Error('Readiness checks must use ReadinessCheck objects.');
  }
}

function validateTokens(document) {
  if (
    document.name !== 'Providentia Fresh Market foundation' ||
    document.version !== '1.0.0' ||
    document.accessibility?.visibleFocusRequired !== true ||
    document.accessibility?.reducedMotionSupported !== true
  ) {
    throw new Error('Unexpected design-token identity.');
  }
}

function generatedPubspec() {
  return `# GENERATED FILE - DO NOT EDIT.
name: providentia_api_client
description: Generated API client for the Providentia backend contract.
publish_to: none
version: 1.0.0

environment:
  sdk: '>=3.12.2 <3.13.0'

dependencies:
  http: 1.5.0
`;
}

function generatedClient(hash) {
  return `// GENERATED FILE - DO NOT EDIT.
// Source: contracts/providentia-v1.json
// Contract SHA-256: ${hash}

library;

import 'dart:convert';

import 'package:http/http.dart' as http;

final class HealthStatus {
  const HealthStatus({required this.status, required this.timestamp});

  factory HealthStatus.fromJson(Map<String, Object?> json) {
    return HealthStatus(
      status: _requiredString(json, 'status'),
      timestamp: _requiredDateTime(json, 'timestamp'),
    );
  }

  final String status;
  final DateTime timestamp;
}

final class ReadinessCheck {
  const ReadinessCheck({required this.status, this.detail});

  factory ReadinessCheck.fromJson(Map<String, Object?> json) {
    return ReadinessCheck(
      status: _requiredString(json, 'status'),
      detail: _optionalString(json, 'detail'),
    );
  }

  final String status;
  final String? detail;
}

final class ReadinessStatus {
  const ReadinessStatus({required this.status, required this.checks});

  factory ReadinessStatus.fromJson(Map<String, Object?> json) {
    final checksJson = _requiredObject(json, 'checks');
    return ReadinessStatus(
      status: _requiredString(json, 'status'),
      checks: Map<String, ReadinessCheck>.unmodifiable(
        checksJson.map(
          (String key, Object? value) => MapEntry<String, ReadinessCheck>(
            key,
            ReadinessCheck.fromJson(_objectValue(value, 'checks.$key')),
          ),
        ),
      ),
    );
  }

  final String status;
  final Map<String, ReadinessCheck> checks;
}

final class SystemInfo {
  const SystemInfo({
    required this.product,
    required this.apiVersion,
    required this.applicationVersion,
    required this.environment,
    required this.runtime,
    required this.databaseDriver,
    required this.queueAdapter,
    required this.queueBroker,
  });

  factory SystemInfo.fromJson(Map<String, Object?> json) {
    return SystemInfo(
      product: _requiredString(json, 'product'),
      apiVersion: _requiredString(json, 'apiVersion'),
      applicationVersion: _requiredString(json, 'applicationVersion'),
      environment: _requiredString(json, 'environment'),
      runtime: _requiredString(json, 'runtime'),
      databaseDriver: _requiredString(json, 'databaseDriver'),
      queueAdapter: _requiredString(json, 'queueAdapter'),
      queueBroker: _requiredString(json, 'queueBroker'),
    );
  }

  final String product;
  final String apiVersion;
  final String applicationVersion;
  final String environment;
  final String runtime;
  final String databaseDriver;
  final String queueAdapter;
  final String queueBroker;
}

final class ProblemDetails {
  const ProblemDetails({
    required this.type,
    required this.title,
    required this.status,
    required this.requestId,
    this.detail,
    this.instance,
    this.extensions = const <String, Object?>{},
  });

  factory ProblemDetails.fromJson(Map<String, Object?> json) {
    final extensions = Map<String, Object?>.of(json)
      ..remove('type')
      ..remove('title')
      ..remove('status')
      ..remove('detail')
      ..remove('instance')
      ..remove('requestId');

    return ProblemDetails(
      type: _requiredString(json, 'type'),
      title: _requiredString(json, 'title'),
      status: _integerValue(json['status'], 'status'),
      requestId: _requiredString(json, 'requestId'),
      detail: _optionalString(json, 'detail'),
      instance: _optionalString(json, 'instance'),
      extensions: Map<String, Object?>.unmodifiable(extensions),
    );
  }

  final String type;
  final String title;
  final int status;
  final String requestId;
  final String? detail;
  final String? instance;
  final Map<String, Object?> extensions;
}

final class ProvidentiaApiException implements Exception {
  const ProvidentiaApiException({
    required this.statusCode,
    required this.problem,
    this.requestId,
  });

  final int statusCode;
  final ProblemDetails problem;
  final String? requestId;

  @override
  String toString() {
    final message = problem.detail ?? problem.title;
    return 'ProvidentiaApiException($statusCode): $message';
  }
}

final class ProvidentiaApiClient {
  ProvidentiaApiClient({
    required this.baseUri,
    http.Client? httpClient,
    Map<String, String> defaultHeaders = const <String, String>{},
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _defaultHeaders = Map<String, String>.unmodifiable(defaultHeaders) {
    if (!baseUri.hasScheme || !baseUri.hasAuthority) {
      throw ArgumentError.value(baseUri, 'baseUri', 'must be absolute');
    }
  }

  final Uri baseUri;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Map<String, String> _defaultHeaders;

  Future<HealthStatus> getLiveness() async {
    final response = await _get('/health/live', accept: 'application/json');
    return HealthStatus.fromJson(_decodeObject(response.body));
  }

  Future<ReadinessStatus> getReadiness() async {
    final response = await _get('/health/ready', accept: 'application/json');
    return ReadinessStatus.fromJson(_decodeObject(response.body));
  }

  Future<SystemInfo> getSystemInfo() async {
    final response = await _get(
      '/api/v1/system/info',
      accept: 'application/json',
    );
    return SystemInfo.fromJson(_decodeObject(response.body));
  }

  Future<String> getMetrics() async {
    final response = await _get('/metrics', accept: 'text/plain');
    return response.body;
  }

  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<http.Response> _get(String path, {required String accept}) async {
    final response = await _httpClient.get(
      _endpoint(path),
      headers: <String, String>{..._defaultHeaders, 'Accept': accept},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response);
    }
    return response;
  }

  Uri _endpoint(String path) {
    return baseUri.replace(path: path, query: null, fragment: null);
  }

  ProvidentiaApiException _toException(http.Response response) {
    ProblemDetails problem;
    try {
      problem = ProblemDetails.fromJson(_decodeObject(response.body));
    } on FormatException {
      problem = ProblemDetails(
        type: 'about:blank',
        title: 'HTTP request failed',
        status: response.statusCode,
        requestId: response.headers['x-request-id'] ?? 'unavailable',
        detail: response.body.isEmpty ? null : response.body,
      );
    }
    return ProvidentiaApiException(
      statusCode: response.statusCode,
      problem: problem,
      requestId: response.headers['x-request-id'] ?? problem.requestId,
    );
  }
}

Map<String, Object?> _decodeObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return decoded;
}

Map<String, Object?> _requiredObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected "$key" to be an object.');
  }
  return value;
}

Map<String, Object?> _objectValue(Object? value, String key) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected "$key" to be an object.');
  }
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  return _stringValue(json[key], key);
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  return value == null ? null : _stringValue(value, key);
}

String _stringValue(Object? value, String key) {
  if (value is! String) {
    throw FormatException('Expected "$key" to be a string.');
  }
  return value;
}

int _integerValue(Object? value, String key) {
  if (value is! int) {
    throw FormatException('Expected "$key" to be an integer.');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Expected "$key" to be an RFC 3339 date-time.');
  }
  return parsed;
}
`;
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function assertRequiredFields(document, schemaName, expected) {
  const actual = document.components.schemas[schemaName].required;
  if (
    !Array.isArray(actual) ||
    actual.length !== expected.length ||
    expected.some((field) => !actual.includes(field))
  ) {
    throw new Error(
      `${schemaName} required fields changed: expected ${expected.join(', ')}`,
    );
  }
}

function json(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function relative(filePath) {
  return path.relative(rootDirectory, filePath);
}
