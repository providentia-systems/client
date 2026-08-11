# Phase 9–10 production integration status

- Date: 2026-08-11
- Flutter target: `1.0.0+10`
- Authoritative backend review: `providentia-systems/backend` API `1.12.0`

## Contract baseline

The Flutter repository pins the reviewed OpenAPI `1.12.0` artifact, validates
its SHA-256 lock, and deterministically generates a callable Dart method and
operation-registry entry for all 156 published operations. Generated transport
stays behind application-owned adapters so authentication, authorization,
session storage, and home lifecycle rules are explicit and testable.

The synchronization gateway retains protocol-v2 push and paged bootstrap. A
contract update may not regress those semantics while adopting onboarding.

## Composed production boundary

| Capability | Current client implementation |
|---|---|
| Login-link onboarding | Email is entered in the originating client; it creates private poll/state/PKCE proofs, starts a generic request, polls with lifecycle-aware backoff, and exchanges once after browser approval |
| Cross-device approval | The email may be opened in any browser; a deep/platform link is optional and never carries or authorizes the client session |
| Pending request safety | Protected short-lived storage, 15-minute request boundary plus server-authoritative final status check, cancel/resend/expiry UI, and restart after an ambiguous single-use exchange |
| Current-user bootstrap | `GET /api/v1/me` supplies identity, current session, homes, roles, active home, pending invitations, and platform roles |
| Session restoration | Approximately 15-minute access credentials; sliding 30-day web inactivity and 60-day native inactivity enforced by the backend |
| Credential storage | Native refresh credential only in OS secure storage; access credential in memory; web session in Secure HttpOnly cookies with required CSRF |
| Logout | Local state clears immediately; native submits the rotating refresh credential as proof, web submits cookie plus CSRF, and remote cleanup is bounded |
| Signed-in devices | Current device is labelled; active sessions can be reviewed/revoked; revoked or expired rows are not shown as signed in |
| Homes | First approved new person receives one editable `My home` as owner; sole default/active home auto-opens; multiple homes use the chooser |
| Invitations | Recipient pending invitations are visible and accepted by expected revision; owner/manager invitation controls are permission-gated |
| Home governance | Editable name/locale/currency/timezone; owner/manager/member/viewer sections and actions derive from server permission policies |
| Platform administration | Visible only for current users with the platform-administrator role; supports list/grant/confirmed revoke and handles the final-active-admin safeguard |
| Catalog sharing and administration | Active-home permissions expose three independent, revision-bound consent choices without implicit submission. Product identity additionally requires server consent, an active-home item, exact allowlisted preview, and fresh per-item checkbox. Current-user reviewer/curator roles expose real proposal, contribution, conflict, validated icon metadata, merge, and reversal workflows with permission/role/session-loss dismissal. Live acceptance remains open |
| Household AI | Account & access exposes a route only for the active home's exact `ai.read`; `ai.use` and `ai.manage` remain independent. One selected image is re-encoded, original/prepared bytes are route-owned and cleared, every candidate is explicitly reviewed, and the result is a non-mutating handoff to ordinary purchasing/inventory commands |
| Browser/native platforms | Web, Android, iOS, Windows, macOS, and Linux share the same polling/exchange authority; platform return links are convenience only |
| Release engineering | Fail-closed signing/package/deployment workflows remain for Android, Apple, Windows, Linux, web, and browser acceptance |

Only the login-link workflow is production onboarding evidence; development
compatibility surfaces do not satisfy this acceptance boundary.

## Connected acceptance boundary

Against the API `1.12.0` development stack, the production composition can:

1. start and approve a neutral login-link request for a new or existing email;
2. complete the private exchange in the originating client and bootstrap the
   authoritative account;
3. restore/rotate native or browser sessions, list devices, revoke a device,
   and sign out deterministically;
4. auto-open one authorized default/active home or choose between multiple
   homes;
5. rename the onboarding home and manage permitted memberships, invitations,
   roles, and policies;
6. accept recipient invitations without disturbing an unrelated active home;
7. manage platform administrators when the current user's platform role
   allows it;
8. manage independent catalog-sharing consent and use the sanitized catalog
   workbench when current home permissions and platform roles allow it; and
9. open private household reports only with the active home's exact
   `reports.read` permission;
10. request account exports/erasure for any authenticated account and expose
    home data-governance actions only from `data.export`/`data.erasure`;
11. load the active home's AI workspace with exact capabilities, explicitly
    consent to one sanitized image, review every candidate, and receive a
    non-mutating ordinary-command handoff; and
12. exercise health plus protocol-v2/paged synchronization foundations.

The backend's canonical
[client/user testing runbook](https://github.com/providentia-systems/backend/blob/main/docs/deployment/client-user-testing.md)
is the acceptance source for browser fragment capture, cross-device approval,
concurrent requests, expiry races, session duration, invitation lifecycle,
role isolation, and final-administrator protection.

## Remaining production gates

The current login-link and account-management boundary does not make every
Phase 5–8 workspace cross-device authoritative. Inventory, count, receipt,
shopping, catalog, private-product, and feedback models must finish their typed
synchronization adoption and two-device convergence evidence. Household AI is
production-composed through the backend contract, but live provider/backend
acceptance and any later ordinary-command draft integration remain open; review
never auto-mutates inventory or purchases.

Catalog consent settings, explicit per-item product-identity contribution, and
the role-scoped moderation workbench are now production-composed with focused
privacy, revision, callback, validation, and revocation tests. Consent changes
and inventory selection never submit an item; contribution requires a separate
checkbox and current server consent. Curator icon metadata is revision-bound
and validated before transport. Live backend acceptance remains open and is
not claimed as completed production evidence.

The local Drift database is not application-encrypted. Device storage
protection, session-loss clearing, and revoked-home purge reduce exposure but
do not replace database encryption. Selecting and proving an encryption and
key-lifecycle design, or recording an explicit release-risk decision, is a
Phase 10 release gate; encryption is not a completed control.

Production publication also remains fail-closed until external release
evidence is supplied through reviewer-protected environments:

- Android upload/signing key and Play signing configuration;
- Apple distribution certificate, provisioning profile, App Store Connect
  issuer/key, macOS Developer ID, and notarization credentials;
- Windows trusted code-signing certificate;
- Linux signing identity and publication destination;
- production web origin, deployment hook, TLS, same-site API topology, and
  credentialed CORS;
- privacy-policy/support URLs and store metadata; and
- physical Android/iOS and independent Safari/macOS acceptance evidence.

The production edge must permit the camera for PWA capture and preserve the
same-site cookie topology required by browser sessions.

## Phase exit criteria

Phase 9 exits when the complete API `1.12.0` login-link, session, home,
invitation, role, and administration path passes against a live deployment on
every selected platform, including expiry, retry, revoked membership, and
cross-home isolation.

Phase 10 exits only after typed synchronization closes the remaining household
gates, two-device offline tests prove no duplicate movements, queued AI
recovery is idempotent, and every selected platform has signed artifacts plus
independent device/browser acceptance evidence. Workflows and placeholders are
not release evidence.
