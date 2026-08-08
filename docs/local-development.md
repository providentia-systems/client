# Local backend and client testing

This is the supported handoff for testing the current client against the
Providentia backend on one development workstation. Keep the
`providentia-systems/backend` and `providentia-systems/client` checkouts as
sibling directories when convenient, but no command depends on that layout.

The client pins OpenAPI `1.7.0` with 86 generated operations. Backend `main`
currently publishes `1.10.0` and retains the compatibility routes used here.
Do not regenerate the client merely to remove that visible version difference.

## 1. Start and provision the backend

The full source-build path requires Docker with Compose v2, `unzip`,
`sha256sum`, `curl`, `jq`, and `openssl`. From the backend checkout, run:

```bash
./scripts/setup-development.sh \
  --handover /absolute/path/Pantry_Stock_Project_Handover_2026-07-29.zip
```

The script starts MySQL, Redis, Mailpit, the API and workers, applies
migrations, imports the verified handover, and creates or safely reuses:

- one verified development account;
- one home owned by that account;
- `.providentia-development.json`, protected with mode `0600`.

Confirm readiness and display only the credentials needed for interactive
client login:

```bash
curl --fail http://127.0.0.1:8080/health/ready
jq -r '"Email: \(.email)\nPassword: \(.password)"' \
  .providentia-development.json
```

The handoff also contains tokens for backend tooling. Do not pass its
`accessToken`, `refreshToken`, `homeId`, or `deviceId` to Flutter. The client
accepts no build-time bearer token or home authorization shortcut.

The published-container alternative is `bash scripts/setup-prebuilt.sh`; see
the backend's
[published-image guide](https://github.com/providentia-systems/backend/blob/main/docs/deployment/prebuilt-images.md).

## 2. Prepare the client

Install the repository-pinned Flutter `3.44.7`/Dart `3.12.2` toolchain. From
the client checkout, run:

```bash
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
node tool/generate_api_client.mjs --check
node tool/verify_structure.mjs
node --test tool/*.test.mjs
```

## 3. Run Chrome on the fixed development origin

Use `localhost` for both the web page and API. Do not mix `localhost` and
`127.0.0.1` in this browser flow: host-only, `SameSite=Strict` development
cookies require a consistent site. Port `8081` is fixed because the backend
CORS allowlist must contain the exact credentialed browser origin.

```bash
flutter run -d chrome \
  --web-hostname=localhost \
  --web-port=8081 \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp \
  --dart-define=PROVIDENTIA_ENVIRONMENT=development \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://localhost:8080
```

Open `http://localhost:8081`, enter the handoff email and password, and select
or create a home. The account menu remains reachable from every household
section and provides **Change home** and **Sign out**.

The source and prebuilt backend development profiles allow
`http://localhost:8081` by default. A custom browser origin must be added to
the backend's explicit `CORS_ALLOWED_ORIGINS`; wildcard credentialed CORS is
not supported.

## 4. Run the Linux desktop client

On Ubuntu, the Flutter Linux build dependencies include:

```bash
sudo apt-get install \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libsecret-1-dev
```

Ensure the desktop session has an available, unlocked Secret Service/keyring;
the client creates a device identity and stores only the native refresh token
in secure platform storage. The access token remains in memory. Then run:

```bash
flutter run -d linux \
  --dart-define=PROVIDENTIA_ENVIRONMENT=development \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://127.0.0.1:8080
```

Use the same handoff email and password. Native clients use bearer sessions
obtained by the interactive login flow; they do not consume the handoff token.

## 5. Run an Android debug build over ADB

With an emulator or USB-debuggable device listed by `flutter devices`, map its
loopback port to the host backend before launching:

```bash
adb reverse tcp:8080 tcp:8080
flutter run -d <android-device-id> \
  --dart-define=PROVIDENTIA_ENVIRONMENT=development \
  --dart-define=PROVIDENTIA_API_BASE_URL=http://127.0.0.1:8080
```

Run `adb reverse` again after reconnecting or restarting the device. The
Android debug network policy permits cleartext traffic only to loopback hosts,
and `RuntimeConfiguration` independently enforces the same API boundary.
Release builds retain the HTTPS-only boundary; a LAN HTTP address is not an
accepted substitute.

## 6. Create additional users and roles

User creation, verification, invitations, and role changes are backend-owned
for this test phase. From the backend checkout, provision a verified test user
and place it in the development home as `manager`, `member`, or `viewer`:

```bash
./scripts/provision-development-user.sh \
  --email tester@example.test \
  --role member
```

Read the generated password from the protected handoff, then use **Sign out**
in the client and log in as that user:

```bash
jq -r '.testUsers[]?
  | select(.email == "tester@example.test")
  | "Email: \(.email)\nPassword: \(.password)\nHome role: \(.role)"' \
  .providentia-development.json
```

Use `--role none` when the account should be created without adding or changing
a home membership. It does not remove a membership created by an earlier run.

Home roles are `owner`, `manager`, `member`, and `viewer`. Platform roles such
as `platform_administrator`, `catalog_curator`, and `catalog_reviewer` are a
separate authorization domain and grant no private-home access. The setup
account is the development home's owner; making it a platform administrator is
an explicit backend CLI action, not a client bootstrap requirement. Follow the
backend's canonical
[client/user testing guide](https://github.com/providentia-systems/backend/blob/main/docs/deployment/client-user-testing.md)
for platform-role grants, invitation lifecycle checks, and cleanup.

## Current limitations

- The current API 1.7 composition exposes local-development email/password
  compatibility only. Production backend configuration disables password login
  by default. Backend API 1.10 publishes passwordless operations, but the
  client pin, adapter, and deep-link flow do not yet adopt them, so the client
  does not show a nonfunctional passwordless toggle.
- There is no client registration, email-verification, password-reset, member
  invitation, invitation-acceptance, or platform-administration screen yet.
- Home selection, home creation, session restoration, **Change home**, and
  **Sign out** are reachable. Other home-governance methods may exist in code
  without a composed screen.
- Inventory, purchase, and shopping-list screens are currently backed mostly
  by local Drift data. Their changes are not a reliable cross-device or
  client/backend acceptance test.
- Home-role restrictions are enforced by the backend, but the local-only
  household UI is not yet fully gated by the effective role. In particular, do
  not treat a viewer's local controls as proof of server write permission.
- No live Flutter/backend integration test currently runs from
  `integration_test/`; use this smoke workflow and record which assertions
  crossed the API boundary.
