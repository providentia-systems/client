# Step 3: reviewed intake and private export retrieval

This extends existing Client PR #19 on `fix/step-1-authoritative-sync`, paired
with backend #23 and Admin #11. Earlier Step 1 and 2 changes are preserved.
Implementation is committed. Keep draft pending the remaining paired acceptance
and earlier release blockers; do not merge or deploy from isolated test success.

## AI evidence review and ordinary handoff

The production AI review now retains typed observation, duplicate, discrepancy
and source evidence from authoritative extraction responses. Relevant controls
submit current revisions through generated API operations and reload the latest
extraction after success, conflict or uncertain response. No automatic mutation
retry, cached success fallback, regeneration, evidence hiding or identifier
coercion is used. Exact-digest duplicates are immutable; unresolved/duplicate
observations and unresolved/rejected discrepancies prevent acceptance/handoff.

Receipt handoff preserves raw receipt wording independently from display labels.
Stock candidates preserve quantity ranges and ambiguity; stock media extraction
requires an existing open count target before transmission. Both paths present
normal review/confirmation instead of an information-only completion message.
Neither creates stock movements: the ordinary second human confirmation is
still required to commit a receipt or close a stock count.

Deterministic home/extraction/candidate identifiers make repeated handoff resume
existing drafts and lines. Manual edits and exclusions survive recovery. Review
resume records contain account, extraction and kind identifiers only; actual
review state is re-read from the backend. Corrupt, unbound, foreign-account or
unknown-kind references cannot become extraction requests.

A reproduced bug that made an incomplete handoff disable further review was
fixed without marking evidence accepted. Revocation and late-response guards
remain in the production workspace composition.

## Export retrieval and explicit saving

Completed account/home export requests expose Download only when authorized and
eligible. The repository refreshes authoritative metadata, requests a short-lived
single-use token with the current revision, and places the token only in the
retrieval POST body. Both responses must be private/no-store; artifact format,
request ID, scope and home are checked before exposure. One consumed-token or
revision race triggers one authoritative refresh and fresh issuance, not token
reuse. Foreign, cancelled, expired, revoked or malformed artifacts fail closed.

Retrieval and saving are separate actions: Download, then Save export copy or
Discard downloaded copy. Private application buffers are zeroed on discard,
expiry, route disposal, logout and scope invalidation. A delayed result cannot
repopulate a retired controller. Save errors are safely classified without raw
paths, provider messages, token values or private payloads in UI text.

Browser saving uses a temporary Blob URL with cleanup and accurately describes
handoff to the browser. Desktop saving uses the existing picker and writes only
after a destination is chosen. Android uses the locked picker. iOS uses an owned
protected, backup-excluded temporary-file/document-picker adapter with cleanup
on startup, completion, cancellation and explicit discard. User-saved copies are
outside application control. Physical platform behavior is not certified by
widget tests; Android's already handed-off native picker cannot be claimed to
support revocation without actual platform acceptance.

## Contract, persistence and validation

Canonical API version 2.1.0, document digest (SHA-256):

```
f6591ae866efbcc9e661528c7f595da0d7093d959d64c66c09b0c5be1dcb7c58
```

All canonical/generated/facade/lock/verification pins are paired with backend
and Admin. No dependency upgrade, destructive migration, operation-ID rewrite
or private-data reset is part of this batch. Existing local records hold scoped
resume hints; existing receipt/count identifiers support durable retries.

Use the existing pinned SDK, then:

```sh
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub --fatal-infos --fatal-warnings
flutter test --no-pub --coverage
```

Source lifecycle run 34902081798, Flutter 3.44.7 / Dart 3.12.2, passed strict
analysis and **1026 tests**, with handwritten coverage **20025/25015 = 80.05%**.
The existing 80% ratchet was not reduced. Its formatted production/test source
was committed as 1026c89b2f5ec228c85a1bb94faaff9e0f7b38d1. Later documentation
changes do not substitute for current-head normal Flutter CI/platform results.

New regression evidence includes actual export page Save/Discard controls;
expiry, late download after disposal/account switch, missing platform saver and
safe error classification; production generated export adapter negative cases;
account/home-isolated Drift resume storage; strict evidence-to-handoff checks;
and a file-backed Drift receipt reopen that retains manual edits, the same two
lines, unchanged operation count and no automatic receipt commit.

Backend live run 34901244406 passed actual export request -> encrypted worker ->
API restart -> production Dart retrieval on SQLite, MySQL 8.4.6 and MariaDB
11.8.3. It verifies home/account content, foreign/cancelled requests, single-use
tokens and a real token-consumption race. It pinned the already corrected export
adapter at b45b0dce6a778db6b070f979fcac6dbe01740662. Details and runtime snapshots
are in backend `docs/releases/step-3-cross-application-workflows.md`.

## Still required before release

The complete real-backend/generated-client/controller/ordinary receipt and
multi-image stock workflow across all three database modes, including integrated
lost-response/restart races and final movement effects, is not yet demonstrated
by these separate tests. The live Admin/publication/second-household-device
journey also remains unexecuted. Browser and every native file-picker lifecycle
need actual platform acceptance; a successful build is not a save/cancel test.
Record current-head normal coverage, architecture and platform gates separately.

Earlier Step 1 durable outbox provenance/dependency/order and permission-cache
lifecycle release blockers are unchanged. Step 4 general resilience is not
included. No live paid AI request, production operation, merge or deployment
was made, and no identity login/onboarding contract was changed.

## Rollout and rollback

After outstanding acceptance and separate authorization, deploy the compatible
backend before the paired applications. Preserve database and current build
references. Pre-Step-3 Client reference:
5b5a35ce212d488080a0442f0c2af34efc189c62.
Rollback paired builds without removing backend evidence/authorization guards.
Do not rewrite ordinary draft IDs, replay receipt commits or duplicate stock
movements. Existing scoped resume hints are non-authoritative and need no
production data migration; explicitly user-saved export copies remain user-owned.
