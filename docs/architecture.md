# Providentia client architecture

## Dependency direction

`lib/app` is the composition shell. `lib/features` contains bounded feature
registrations. `lib/core` owns cross-cutting ports and adapters. The generated
contract client is an infrastructure dependency constructed only in core
networking and adapted by core synchronization.

Feature and widget source may not import:

- `package:http`
- the generated API client
- Drift, SQLite3, sqflite, or any other SQLite implementation
- `dart:io` or `dart:html`

Both a source-only Node verifier and a Dart architecture test enforce the rule.
Feature presentation depends on application-owned repositories and
controllers, not transport or persistence packages.

The synchronization dependency chain is explicit:

- presentation depends on `AppSynchronization`;
- `SyncCoordinator` implements that application port and depends on
  `LocalSyncStore`, `SyncRemoteGateway`, `ConnectivityProbe`,
  `AuthenticationRecovery`, `SyncMetrics`, `RetryPolicy`, and an injected
  clock;
- feature mutation use cases depend only on `LocalMutationRepository`;
- the Drift adapter implements the mutation and sync-store ports, while the
  generated-client adapter implements the remote gateway;
- `main.dart` is the only composition root that selects those concrete
  adapters.

Both source-only and Dart architecture tests reject presentation-to-adapter,
domain-to-framework, and generated-client dependency reversals.

## Phase boundaries

Phase 1 includes:

- real platform runners
- application composition shell
- core and bounded-feature namespace shells
- public runtime configuration validation
- generated API transport proof
- CI and quality gates

Phase 3 adds the Fresh Market design system, adaptive application shell, Drift
schema/migration, transactional local repositories, tombstones, media metadata,
conflicts, cursor storage, and the durable client-operation outbox.

Phase 4 adds authorized snapshot bootstrap, push/pull adapters generated from
the backend contract, process-death recovery, bounded retry, five exact server
result classifications, atomic page-and-cursor application, and explicit sync
outcomes for presentation.

Phase 5–8 inventory, purchasing, shopping, intelligence, catalog, and reporting
models and workspaces now exist. In the current production composition, the
visible household inventory, purchase, and list workflows are still backed
primarily by local Drift projections. Identity, session, authorized-home
selection, health checks, and the narrow synchronization gateway are connected
to the backend. A visible workspace is therefore not, by itself, evidence of
end-to-end server integration.

## Runtime configuration

The public values `PROVIDENTIA_API_BASE_URL` and `PROVIDENTIA_ENVIRONMENT`
enter the application through `--dart-define`. The API value is a server origin,
not an `/api` path prefix, and must use HTTPS except for loopback development.

Authentication is established only through the interactive identity session.
No bearer token or home ID is accepted as runtime bootstrap configuration.
Database credentials, tokens, AI provider keys, server encryption keys, and
queue credentials must never be compiled into Flutter. See
[local development](local-development.md) for the supported launch topology.
