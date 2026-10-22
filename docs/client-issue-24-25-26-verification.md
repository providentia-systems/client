# Client issues #24–#26: implementation and verification

## Issue mapping

| Issue | Client behavior delivered |
| --- | --- |
| #24 | Browse or search the verified household item master offline, including private/catalogue-linked and zero-stock products. Names and aliases rank ahead of metadata matches. Selection saves a stable household product ID with manual origin; custom text remains explicitly unlinked. Editing text clears stale selection. Duplicates are scoped to the selected list and offer quantity adjustment or a deliberate separate line. Shopping/receipt quantity inputs select their first value on first focus, preserve ordinary later cursor behavior, and reset only after successful save. |
| #25 | Capture and submitted rows show purchased quantity, pack/measurement, unit price, currency and explicit/derived total. Saved-line summaries retain the physical receipt total separately, show remaining/over amounts, and disclose unknown/currency-invalid prices. Imported/unresolved prices are included without authorizing stock. Unsaved previews remain separate. Explicit discounts win and display a discrepancy warning. Mixed-currency/partial history totals no longer crash or masquerade as complete totals. |
| #26 | Retry awaits the actual household synchronization attempt without another receipt commit. Overlapping requests join serialized work and request a follow-up pass for mutations saved mid-run. Receipt-scoped notices never infer success from null selection. Typed queue metadata identifies the first dependency, blocked/waiting operation counts and retry timing. Home distinguishes device/account/session errors from verified home denial and exposes existing account/conflict review routes. Editor progress/errors stay beside Save, invalid fields receive focus, and failed/stale edits retain input with non-destructive saved-value review. |

## Arithmetic and persistence

Money multiplication uses BigInt and the retained decimal purchased quantity. Each line rounds HALF_UP to two decimal places, matching the backend. The purchased pack count is distinct from stock conversion; four 1 kg packs and one 4 kg pack retain different purchase meanings. Explicit line totals, including zero and discounted amounts, override the calculated preview. An overflowing optional calculation cannot discard a valid explicit total; an overflowing derived-only history amount remains unknown without breaking other purchases. Missing prices never become zero. Totals do not enqueue commands or mutate stock.

Selected manual products are checked against active same-home products inside the atomic projection/outbox transaction. Restart and another-device readback regressions verify the stable identity and manual origin. Unit-price-only receipt amounts remain consistent across restart and committed history without inventing stored amounts or duplicating stock changes.

Each API request has a 30-second deadline across response headers and body, using request-scoped cancellation while preserving the shared authenticated transport. Native connections are also bounded. A timed-out request retains immutable operation identity for response-loss recovery; cancellation is not proof the server rejected an operation. Eight real socket tests cover header/body stalls, actual abort, late responses, concurrent request isolation, external abort and transport reuse. Retry timing is labelled eligibility rather than promising an automatic timer.

Late completions, disposed controllers and home changes retain isolation. A Flutter DropdownMenu focus-state defect found during testing was corrected so saving/disabling one household's entry cannot leave the next household's product field read-only.

## Automated evidence (22 October 2026)

- Flutter 3.44.7 / Dart 3.12.2; committed dependency locks and archive checksums preserved.
- Full Flutter suite: **1,335 passed**.
- Handwritten production coverage: **81.48%** (23,161 / 28,425), required minimum 80%.
- Strict Flutter analysis: no issues.
- Dart formatting and `git diff --check`: passed.
- Contract generation, toolchain, architecture/structure verification: passed.
- Node tool tests: **31 passed**.
- Drift generation: passed; no generated source changes.
- Web release build: passed.
- Phone golden: passed with the existing baseline. Pending-only counts remain concise; additional blocked/waiting diagnostics appear for blocked work.

Focused tests also cover exact rounding boundaries, discounted/zero/unknown amounts, currency isolation, responsive prices, quantity focus/reset/failure behavior, duplicate/custom shopping items, restart/readback, account/home switching, delayed retry, no recommit, queue barriers, editor failures and production security wiring.

The restricted contributor host could not install native system packages with the canonical setup script. The pinned SDK and locked dependencies were provisioned with verified checksums, followed by normal checks (`--no-pub` after successful offline `--enforce-lockfile` resolution). No check or threshold was weakened. The PR's unchanged GitHub Actions workflows validate platform builds/packages and encrypted browser persistence; inspect the current PR checks before merging. The separate deployed-browser acceptance workflow requires an installed target and was not run here.

## Backend coordination and deployment acceptance

Backend #28 / PR #32 owns independent manual-pack selection/relinking and recommendation/count evidence. This client enables existing household product selection against the frozen contract and does not expose a pack choice that the server cannot persist.

Backend #29 / PR #32 owns actual device-binding recovery. This client preserves operation/account/device identities and clearly exposes the blockage and existing account/review routes. Repeated retry cannot bypass that recovery. Backend #30 owns calendar-date corrections/header semantics, and #31 owns historical stock rebuilding. No backend security, chronology or contract change is claimed here.

No tests were run against the user's installed household database. After deploying compatible backend/client versions, verify an offline purchase reconnects exactly once, the original blocked queue recovers through the supported binding workflow, another device sees the linked shopping product, and receipt totals/stock readback agree. Pending local stock is not proof of server acceptance.
