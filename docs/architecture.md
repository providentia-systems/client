# Phase 1 client architecture

## Dependency direction

`lib/app` is the composition shell. `lib/features` contains bounded feature
registrations. `lib/core` owns cross-cutting ports and adapters. The generated
contract client is an infrastructure dependency constructed only in
`lib/core/networking`.

Feature and widget source may not import:

- `package:http`
- the generated API client
- Drift, SQLite3, sqflite, or any other SQLite implementation
- `dart:io` or `dart:html`

Both a source-only Node verifier and a Dart architecture test enforce the rule.
Later feature presentation code will depend on application-owned repositories,
not transport or persistence packages.

## Phase boundaries

Phase 1 includes:

- real platform runners
- application composition shell
- core and bounded-feature namespace shells
- public runtime configuration validation
- generated API transport proof
- CI and quality gates

Phase 1 excludes:

- authentication and home workflows (Phase 2)
- Drift schema, migrations, repositories, outbox, and design-system widgets
  (Phase 3)
- synchronization protocol behavior (Phase 4)
- migrated product workflows and visual parity (Phase 5)

The marker types in deferred core directories state the owning phase and contain
no fake implementation.

## Runtime configuration

Only public values such as `PROVIDENTIA_API_BASE_URL` and
`PROVIDENTIA_ENVIRONMENT` may enter the application through `--dart-define`.
The API URL must use HTTPS except for loopback development. Database
credentials, AI provider keys, server encryption keys, and queue credentials
must never be compiled into Flutter.
