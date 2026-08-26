# Agent environment guide — Providentia homeowner client

Read `AGENTS.md` first; it is the contributor contract. This file adds the
practical bootstrap for coding-agent sandboxes so a session can build, test,
and debug locally from the first minute.

## Fast start

```bash
bash tools/agent-setup.sh
source .agent-env
```

The bootstrap is idempotent and proven inside managed agent sandboxes: it
installs the checksum-pinned Flutter SDK (`toolchain.json`) and Node runtime
into `.agent-tools/`, runs code generation, the full test suite with
coverage, the Linux release build, the Debian package, and the bounded
Xvfb/D-Bus launch smoke. Everything it downloads comes from `pub.dev` and
`storage.googleapis.com`, both reachable through sandbox egress proxies.

After sourcing `.agent-env`:

```bash
flutter test                      # full suite
flutter analyze                   # fatal analysis gate
dart format --set-exit-if-changed lib test
dart run build_runner build --delete-conflicting-outputs
bash tools/verify_structure.sh    # structure/boundary gates (see tools/)
```

Check exit codes, not just output. CI (`.github/workflows/`) additionally
builds all six platforms; locally the Linux target is the proving ground.

## Backend binding

`PROVIDENTIA_API_BASE_URL` is a compile-time `--dart-define` (validated in
`lib/core/config/runtime_configuration.dart`): HTTPS-only outside loopback
development, origin-only, and deliberately without any end-user UI to change
it — one backend, multiple fixed-aim clients.

## Contract synchronization

`contracts/providentia-v1.json` and its lock are frozen inputs copied from
`providentia-systems/backend` at an exact published contract version.
Regenerate the facade with the repo's generation tooling only after the
backend publishes; never hand-edit generated bindings. Generated code,
adapters, tests, and the backend change move together.
