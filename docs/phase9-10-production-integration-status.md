# Phase 9–10 production integration status

- Date: 2026-08-09
- Flutter target: `1.0.0+10`
- Authoritative backend review: `providentia-systems/backend` API `1.11.1`

## Contract baseline

The Flutter repository pins the reviewed OpenAPI `1.11.1` artifact, validates
its SHA-256 lock, and deterministically generates a callable Dart method and
operation-registry entry for all 155 published operations. Generated transport
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
| Browser/native platforms | Web, Android, iOS, Windows, macOS, and Linux share the same polling/exchange authority; platform return links are convenience only |
| Release engineering | Fail-closed signing/package/deployment workflows remain for Android, Apple, Windows, Linux, web, and browser acceptance |

Only the login-link workflow is production onboarding evidence; development
compatibility surfaces do not satisfy this acceptance boundary.

## Connected acceptance boundary

Against the API `1.11.1` development stack, the production composition can:

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
   allows it; and
8. exercise health plus protocol-v2/paged synchronization foundations.

The backend's canonical
[client/user testing runbook](https://github.com/providentia-systems/backend/blob/main/docs/deployment/client-user-testing.md)
is the acceptance source for browser fragment capture, cross-device approval,
concurrent requests, expiry races, session duration, invitation lifecycle,
role isolation, and final-administrator protection.

## Remaining production gates

The current login-link and account-management boundary does not make every
Phase 5–8 workspace cross-device authoritative. Inventory, count, receipt,
shopping, catalog, private-product, AI-review, and feedback models must finish
their typed synchronization adoption and two-device convergence evidence.

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

Phase 9 exits when the complete API `1.11.1` login-link, session, home,
invitation, role, and administration path passes against a live deployment on
every selected platform, including expiry, retry, revoked membership, and
cross-home isolation.

Phase 10 exits only after typed synchronization closes the remaining household
gates, two-device offline tests prove no duplicate movements, queued AI
recovery is idempotent, and every selected platform has signed artifacts plus
independent device/browser acceptance evidence. Workflows and placeholders are
not release evidence.
