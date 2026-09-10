# Local backend and client testing

This is the supported developer handoff for the pinned API contract. It tests
the production-shaped email-code flow, session restoration, homes,
invitations, roles, and homeowner account management against one local Providentia
backend. The backend's canonical
[client/user testing runbook](https://github.com/providentia-systems/backend/blob/main/docs/deployment/client-user-testing.md)
contains the complete security and cross-device acceptance matrix.

## 1. Start the backend and email delivery

From the backend checkout, start the development stack built from the matching
branch. The API and notification worker send numeric codes; there is no
backend login page or client callback URL. Keep the Flutter web origin in the
backend CORS list:

```bash
CORS_ALLOWED_ORIGINS='http://127.0.0.1:3000,http://localhost:3000,http://127.0.0.1:8081,http://localhost:8081' \
  bash scripts/setup-prebuilt.sh
```

```bash
CORS_ALLOWED_ORIGINS='http://127.0.0.1:3000,http://localhost:3000,http://127.0.0.1:8081,http://localhost:8081' \
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

Before requesting a code, confirm that the running backend contract contains
`requestEmailCode` and `verifyEmailCode`. Use the coordinated API 2.0.0 branch;
old prebuilt images do not expose the new authentication contract.

## 2. Prepare the client

The client accepts Flutter `>=3.44.7 <4.0.0` and Dart
`>=3.12.2 <4.0.0`. This permits newer stable Flutter 3.x releases while CI
retains `3.44.7` as the reproducible minimum baseline. A pubspec checks the SDK
already selected by the `flutter` command; it cannot install or update Flutter.

### Guided Ubuntu client setup

The supported beginner path builds and launches the native homeowner client
from a clean Ubuntu or Debian x86-64 desktop. Run it as the signed-in desktop
user, not with `sudo`:

```bash
git clone https://github.com/providentia-systems/client.git
cd client
bash tools/setup-ubuntu-client.sh
```

Enter only the public origin of the matching Providentia backend, such as
`https://inventory.example.com` or `https://inventory.example.com:8443`.
The value must not contain credentials, a path, query, or fragment. Plain HTTP
is accepted only for `localhost` or `127.0.0.1` in development. The script:

1. installs the Linux desktop, Libsecret, camera/media, and build packages;
2. downloads the repository's checksum-pinned Node and Flutter runtimes into
   the ignored `.agent-tools/` directory;
3. resolves the locked dependencies and verifies the pinned API bindings;
4. builds the release with that public backend origin; and
5. warns when backend readiness is unavailable, then launches the client from
   the generated Linux bundle.

For unattended building, or to build before DNS is live, pass the origin and
skip launch:

```bash
bash tools/setup-ubuntu-client.sh \
  --api-url https://inventory.example.com \
  --no-launch
```

Use `--skip-system-packages` only after installing the packages listed below.
Rerun the same command after pulling a newer release or when the public backend
origin changes. The origin is compiled into that client build; the script does
not store server, database, administrator, or AI-provider credentials. The
separate `tools/agent-setup.sh` remains the contributor/CI bootstrap and is not
the end-user launcher.

### Network, browser, and firewall boundary

The native client makes outbound HTTPS requests to the configured API origin.
A normal installation needs no inbound client firewall rule. Publish only the
reverse-proxy HTTPS port (normally TCP 443, or the explicitly chosen custom
port). Keep MySQL/MariaDB 3306, Redis 6379, PHP-FPM 9000, metrics, and container
management sockets on private networks; none belongs in a client URL.

Browser builds have an additional boundary: the backend must allow the exact
browser origin (scheme, host, and port) in `CORS_ALLOWED_ORIGINS`, and production
cookies require HTTPS. CORS is not a firewall and does not make a private API
public. If an OPNsense or another gateway fronts the server, forward the public
HTTPS port only, retain internal service isolation, and verify both
`/health/live` and `/health/ready` through the public hostname before onboarding.
The backend deployment guide owns the authoritative proxy, certificate,
Compose, secret-generation, and firewall procedure.

### AI-provider handoff

The client setup command configures the API origin only. Never put an AI key in
this repository, a Dart define, a desktop launcher, or browser storage. An
authorized homeowner creates a provider profile through the product workflow;
the backend encrypts the credential in its configured vault and performs all
provider calls. `ai.credentials.use` authorizes bring-your-own provider
credentials, while `ai.platform.use` is reserved for operator-funded usage.
Receipt and stock-count results remain proposals until the user reviews and
accepts them. Follow the matching backend release's `docs/deployment/ai-byok.md`
for provider allowlists, vault keys, worker operation, quotas, and readiness.

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
  --dart-define=PROVIDENTIA_API_BASE_URL=http://localhost:8080
```

For a desktop target on the backend workstation:

```bash
flutter run -d linux \
  --dart-define=PROVIDENTIA_ENVIRONMENT=development \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://127.0.0.1:8080
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

The loopback workflow uses the same workstation or ADB reverse. Reading email
on another device is sufficient: enter the number in the requesting client.
For a client on a different network, expose the API through trusted HTTPS and
configure its exact origin in the client and the backend CORS allowlist.

## 4. Verify numeric email sign-in

1. Enter an email address and choose **Send code**.
2. Confirm Mailpit receives **Your Providentia verification code**. The public
   challenge response must not contain the code.
3. Enter the eight digits in the same client. Wrong codes remain on the form;
   expiry, five failed attempts or successful use require a new challenge.
4. Complete name, country and privacy agreement for a new account. Only Namibia
   is initially published. Other countries require administrator activation.
5. Create a home when your account group allows it, or accept a pending
   invitation. New standalone accounts may own one home by default; invited
   accounts use their country's configured invited-account group.
6. Repeat from another installation and verify the account and homes remain
   the same. Verify an old consumed code cannot sign in again.

Codes expire after ten minutes. Resend has a 60-second cooldown, replaces the
prior code, and does not remove rate limits. No user should need to click an
authentication link or open a backend URL.

## 5. Verify home groups, invitations and profiles

- A single authorized home opens directly; multiple homes show the chooser.
- Home settings support name, description, photo, country/region/city, map
  location, currency and timezone. Creation uses the selected country's
  administrator-configured currency and timezone.
- Invitation access is disabled in the default home group. Enable it in the
  separate admin client and configure total/role quotas before inviting.
- Invite a second email, sign in with its code, then accept or decline the
  pending invitation. Acceptance rechecks current invitation authority.
- Individual member permissions support inherit/allow/deny, bounded by the
  home group's delegable permissions. Verify `permissions.manage` can edit
  those overrides without granting membership removal or role management.
- Move the home to a less permissive group. Existing members and records remain;
  additions above current quotas fail and disabled actions disappear.
- Verify two homes never share permissions or private inventory.
- In Account, edit the name/avatar, verify an additional email, make it primary,
  then remove the old email. Removing the last verified email is refused.
- Bootstrap the system owner with the backend `system:owner` command. Operator
  approval, account/home group assignment and administrative inspection belong
  only in the separate admin client.

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

Email-code onboarding, session/device management, current-user bootstrap,
multiple homes, invitations, home governance, and editable home settings are
composed against API `2.0.0`. Household
inventory, purchase, and shopping-list screens still include local Drift
projections; those screens alone are not proof of cross-device convergence for
every backend resource. Catalog consent and homeowner contributions, household
reporting, data governance, and household AI are production-composed behind
their exact home-permission gates. Administration and moderation are excluded
from this client. Visible routes and focused tests are not substitutes for live
backend, cross-device, provider, or supported-platform acceptance. Use the
synchronization tests and backend runbook for those boundaries.
