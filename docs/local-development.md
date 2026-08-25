# Local backend and client testing

This is the supported developer handoff for the pinned API contract. It tests
the production-shaped login-link flow, session restoration, homes,
invitations, roles, and homeowner account management against one local Providentia
backend. The backend's canonical
[client/user testing runbook](https://github.com/providentia-systems/backend/blob/main/docs/deployment/client-user-testing.md)
contains the complete security and cross-device acceptance matrix.

## 1. Start the backend and email delivery

From the backend checkout, either start the published stack or build from the
verified handover. Approval links open this Flutter homeowner client; the
backend exposes JSON proof, review, and decision endpoints but no approval
page. Keep the Flutter web origin in the backend CORS list. For the default
loopback ports, start the chosen stack with the explicit allowlist and
homeowner app-link base:

```bash
CORS_ALLOWED_ORIGINS='http://127.0.0.1:3000,http://localhost:3000,http://127.0.0.1:8081,http://localhost:8081' \
HOMEOWNER_APP_LINK_BASE='http://localhost:8081/homeowner' \
  bash scripts/setup-prebuilt.sh
```

```bash
CORS_ALLOWED_ORIGINS='http://127.0.0.1:3000,http://localhost:3000,http://127.0.0.1:8081,http://localhost:8081' \
HOMEOWNER_APP_LINK_BASE='http://localhost:8081/homeowner' \
  bash scripts/setup-development.sh \
    --handover /absolute/path/Pantry_Stock_Project_Handover_2026-07-29.zip
```

Supplying the complete list explicitly makes the local handoff independent of
a stale generated environment or previously created container. If an
installation already has `.env.prebuilt.local` or
`.env.development.local`, add the same `CORS_ALLOWED_ORIGINS=...` line there
and rerun the corresponding setup command so Docker recreates the API service.

Both paths start the API, database, queue, notification worker, and Mailpit.

Confirm the API before launching Flutter:

```bash
curl --fail-with-body http://127.0.0.1:8080/health/live
curl --fail-with-body http://127.0.0.1:8080/health/ready
curl --fail-with-body http://127.0.0.1:8080/api/v1/system/info
```

Open Mailpit at `http://127.0.0.1:8025`. An accepted API request without a
delivered message is not a successful onboarding test.

Before requesting a login link, confirm that the running backend contract
contains the JSON operations `proveLoginLinkApproval`,
`reviewLoginLinkApproval`, and `decideLoginLinkApproval`. No HTML route or form
POST is part of the supported backend surface.

## 2. Prepare the client

The client accepts Flutter `>=3.44.7 <4.0.0` and Dart
`>=3.12.2 <4.0.0`. This permits newer stable Flutter 3.x releases while CI
retains `3.44.7` as the reproducible minimum baseline. A pubspec checks the SDK
already selected by the `flutter` command; it cannot install or update Flutter.

### Ubuntu and Debian-based Linux prerequisites

Install Flutter's Linux desktop build tools and the Libsecret development and
runtime packages required by `flutter_secure_storage`:

```bash
sudo apt-get update
sudo apt-get install -y \
  clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev \
  liblzma-dev libsecret-1-0 libsecret-1-dev libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good zip
```

For a first Snap installation, classic confinement is required:

```bash
sudo snap install flutter --classic
```

For an existing Flutter Snap, refresh it to the current stable release:

```bash
sudo snap refresh flutter --channel=latest/stable
```

Validate both the Flutter toolchain and the native Libsecret package before
resolving the client:

```bash
flutter --version
flutter doctor -v
flutter devices
pkg-config --modversion libsecret-1
```

The Flutter SDK does not need to be exactly `3.44.7`; for example, `3.44.9`
satisfies the supported range. `flutter pub get` downloads Dart packages, not
the Flutter SDK itself.

The upstream Linux secure-storage plugin documents a possible later Snap/GLib
linker mismatch on Ubuntu. That problem reports undefined references such as
`g_task_set_static_name` or `g_once_init_enter_pointer`; it is different from a
missing `libsecret-1` package. If that linker error occurs, use the
[official Flutter Linux archive](https://docs.flutter.dev/install/manual)
or install the repository's verified baseline archive outside the checkout:

```bash
tool/install_flutter_linux.sh /absolute/path/to/sdk-parent
export PATH="/absolute/path/to/sdk-parent/flutter/bin:$PATH"
```

From the client checkout, run:

```bash
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
node tool/generate_api_client.mjs --check
node tool/verify_structure.mjs
node --test tool/*.test.mjs
```

The client contract must remain byte-for-byte aligned with the reviewed
backend artifact and its recorded SHA-256. Do not hand-edit generated Dart.

## 3. Run the client

For web, use `localhost` for both the page and API. Port `8081` is fixed because
the backend credentialed-CORS allowlist must contain the exact origin.

```bash
flutter run -d chrome \
  --web-hostname=localhost \
  --web-port=8081 \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp \
  --dart-define=PROVIDENTIA_ENVIRONMENT=development \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://localhost:8080 \
  --dart-define=PROVIDENTIA_HOMEOWNER_APP_LINK_BASE=http://localhost:8081/homeowner
```

For a desktop target on the backend workstation:

```bash
flutter run -d linux \
  --dart-define=PROVIDENTIA_ENVIRONMENT=development \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://127.0.0.1:8080 \
  --dart-define=PROVIDENTIA_HOMEOWNER_APP_LINK_BASE=providentia://login-link/homeowner
```

Replace `linux` with an available `windows`, `macos`, or iOS simulator/device
identifier as appropriate. Native release builds require HTTPS; cleartext HTTP
is restricted to the development loopback profile.

For Android over ADB, map the device loopback to the host first:

```bash
adb reverse tcp:8080 tcp:8080
flutter run -d <android-device-id> \
  --dart-define=PROVIDENTIA_ENVIRONMENT=development \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://127.0.0.1:8080
```

The loopback golden path is same-workstation (or ADB-reversed) testing. To
open the approval link on a genuinely different device, expose the API through
a trusted reachable HTTPS endpoint, configure the backend's homeowner app-link
base for the installed client (or its HTTPS PWA route), allow that client origin
in CORS, and point Flutter at the same reachable API. Never expose loopback
development secrets publicly.

## 4. Verify the login-link flow

Use a new email address for the first pass, then repeat with the same email
from another installation.

1. Enter the email in the originating client and choose **Send login link**.
2. Confirm the client shows its waiting screen and Mailpit receives one neutral
   message without revealing whether the address already exists.
3. Open the login link with the Providentia homeowner app. The link capability
   remains in the URI fragment, is cleared from browser history on web, and is
   held only in memory until the decision. Opening it must show a review page;
   it must not approve the request by itself.
4. Choose **Approve login**. The reviewing client must not
   receive the originating client's application session.
5. Return to the originating client. It polls the backend and exchanges its
   private poll token, state, and PKCE verifier. A deep link may return focus as
   a convenience, but is not required.
6. Confirm `GET /api/v1/me` bootstraps the account. A first-time person gets
   exactly one editable `My home` as `owner`; an existing person gets their
   existing homes without another default home.

The login request expires after 15 minutes. **Resend**, **Cancel**, and retry
must clear the prior protected pending proof. A lost or ambiguous exchange
response is single-use and requires a new login-link request.

Use only the newest message with subject **Approve your Providentia login**.
Sending a new link retires the previous request, so an older link correctly
becomes unavailable. The client removes the `approval` fragment before review
and never places it in a cookie, persistent store, log, or route name. After a
failed proof, request a new link and open that fresh message once.

## 5. Verify homes, invitations, and roles

- One default/active home opens automatically. Multiple homes show the home
  chooser; the account and sign-out actions remain available even with no
  active home.
- Rename `My home` in **Home settings**, close the client, and confirm the same
  home and session restore on relaunch.
- As an `owner` or permitted `manager`, invite another email and choose its
  home role. The invitee completes the ordinary login-link flow, sees the
  pending invitation, accepts its current revision, and can then switch homes.
- Verify `owner`, `manager`, `member`, and `viewer` screens expose only actions
  allowed by the server permission policy. Platform roles are separate and do
  not grant private-home access.
- Before the first administrator login, set protected backend
  `PLATFORM_BOOTSTRAP_ADMIN_EMAILS` to the exact test address and restart (or
  recreate) the backend so startup validation applies. Complete the ordinary
  login-link flow for that address, then verify list/grant/revoke in
  **Account**. Onboard the delegated address through its own login link and
  confirm the backend rejects removal of the final active administrator.

## 6. Verify persistent sessions and sign-out

The backend enforces approximately 15-minute access credentials, sliding
30-day web inactivity, and sliding 60-day native inactivity. Production HTTPS
web sessions use Secure HttpOnly cookies and a required CSRF value. The
isolated loopback HTTP profile relaxes only the cookie's Secure attribute;
native refresh credentials remain in platform secure storage and access
credentials remain in memory.

Close and reopen each client to confirm restoration. In **Account → Signed-in
devices**, confirm the current installation is identified, expired sessions are
not presented as active, and another device can be revoked. Sign out with an
expired access credential as well: native uses its rotating refresh credential
as logout proof, web uses its refresh cookie plus CSRF, and local state stays
cleared even if remote cleanup cannot be completed.

## Current integration boundary

Login-link onboarding, session/device management, current-user bootstrap,
multiple homes, invitations, home governance, editable home settings, and
platform-administrator controls are composed against API `1.13.2`. Household
inventory, purchase, and shopping-list screens still include local Drift
projections; those screens alone are not proof of cross-device convergence for
every backend resource. Catalog consent/contribution, platform-role moderation,
household reporting, data governance, and household AI are production-composed
behind their exact home-permission or platform-role gates. Their visible routes
and focused tests are not substitutes for live backend, cross-device, provider,
or supported-platform acceptance. Use the synchronization tests and backend
runbook for those boundaries.
