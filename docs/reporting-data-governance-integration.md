# Reporting and data-governance integration

This client slice implements the P3 report and privacy-request boundaries for
the pinned backend API `1.18.0`, SHA-256
`fb7f18cc8d2e0f7aaf3ec9f1bd3039316c6f44af0023110936778a8d616a6759`.
It does not change generated contract bytes. Both slices are composed in the
authenticated production Account & access flow.

## Household reports

`GeneratedHouseholdReportRepository` invokes the four current home-report
operations for inventory, purchases, consumption, and suggestions. Each
response is mapped into a closed domain projection that preserves fixed-point
decimal strings, evidence metadata, input watermarks, report range/policy
metadata, suggestion facts, and price comparisons.

Before mapping, the adapter recursively inspects every response value. Any
nested `homeId` that differs from the route home rejects the complete load.
Missing, mismatched, or malformed envelopes and facts are classified as an
invalid response; HTTP authentication, authorization, conflict, and transport
failures use a detail-free taxonomy. Backend problem details are never exposed
to the reporting controller.

## Account and home data governance

The data-governance feature has independent domain, application,
infrastructure, and presentation layers for:

- account export and account erasure requests;
- home export and home erasure requests;
- bounded account/home request lists and their lifecycle status; and
- optimistic, expected-revision cancellation.

Account actions are available only for an authenticated session. Home export,
home request history, and home cancellation derive from the active policy's
`data.export` permission; home erasure derives independently from
`data.erasure`. These client capabilities hide or disable commands but never
replace backend authorization.

Erasure submission requires an `ErasureConfirmation` value that can only be
created from the exact phrase `ERASE`. The generated adapter validates request
kind, scope, UUID, revision, status, dates, disclosures, and nested home
attribution. It maps only the public request projection. Raw subject/requester
IDs, artifact storage fields, backend failure reasons, problem details, and
other response extensions are discarded before application or UI state.

## Evidence and remaining gate

Focused adapter tests cover complete report mapping, nested cross-home
rejection, all governance request/list/cancel routes, revision bodies, closed
failure classification, and raw-detail suppression. Application and widget
tests cover fail-closed permission derivation, cross-home cancellation denial,
exact erasure confirmation, hidden denied actions, and safe failure copy.

`production_bootstrap_app.dart` creates route-owned controllers from the
credentialed generated client. Household reports require the exact
`reports.read` permission for the currently active home. Authenticated users
retain account export/erasure access without a selected home; home governance
actions derive only from `data.export` and `data.erasure`. Platform roles grant
none of these household capabilities.

The production boundary owns both the outer session navigator and the nested
workspace navigator. Authentication loss, catalog-role loss, home changes, and
permission loss dismiss protected routes before their controllers are disposed.
Late async responses are generation-guarded and cannot notify or retain report
or governance data after route disposal.

Live authenticated backend evidence, accessibility/golden review, and
supported-platform CI remain required before production acceptance.
