# Phase 9–10 release engineering and certification

Status: release automation implemented; protected credentials and external
acceptance evidence remain environment-owned release inputs.

Providentia is proprietary software. These workflows package the application
for authorized distribution and do not add or imply an open-source licence.

## Release outcomes

| Workflow | Produced evidence | Trust boundary |
|---|---|---|
| `release-android.yml` | Signed Android App Bundle and signed release test APK | Upload-key fingerprint must match the protected SHA-256 value |
| `release-apple.yml` | Provisioned iOS IPA and signed/notarized macOS installer package | Apple team, provisioning profile, signing identities and notarization account |
| `release-windows.yml` | Signed x64 MSIX | PFX subject must equal the MSIX publisher and its thumbprint must match |
| `release-linux.yml` | x86-64 AppImage and Debian package with detached OpenPGP signatures | AppImage tool is checksum-pinned; package signatures use the protected key |
| `release-web.yml` | Production PWA archive plus optional protected deployment hook | HTTPS API URL and, for publication, authenticated deployment hook |
| `browser-acceptance.yml` | Per-browser PWA persistence plus bound numeric email-code verification, bootstrap, refresh and logout evidence | Deployed HTTPS target, dedicated synthetic account and operator-controlled test mailbox |

Each platform release contains SHA-256 checksums, a CycloneDX 1.5 dependency
SBOM, an in-toto/SLSA-compatible provenance statement and a release manifest.
The provenance statement records the GitHub source commit and workflow run. It
is build evidence, not a claim that GitHub or a third party cryptographically
signed the statement.

## Protected configuration

Configure release secrets only in the `production-release` environment and
acceptance-test secrets only in `production-acceptance`. Both environments
must have required reviewers. Repository variables may contain public URLs and
public tool digests; credentials and private keys must remain secrets.

### Shared

- Variable `PRODUCTION_API_BASE_URL`: absolute HTTPS Laminas API origin.

### Android

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_EXPECTED_CERT_SHA256`

The checked-in Gradle project currently has development signing for local
builds. Release automation removes that signature, applies the protected upload
key and verifies both the AAB and APK. A release is rejected when the observed
certificate fingerprint differs from the protected value.

### Apple

- `APPLE_SIGNING_CERTIFICATE_P12_BASE64`
- `APPLE_SIGNING_CERTIFICATE_PASSWORD`
- `APPLE_TEAM_ID`
- `IOS_PROVISIONING_PROFILE_BASE64`
- `APPLE_IOS_SIGNING_IDENTITY`
- `APPLE_MACOS_APPLICATION_IDENTITY`
- `APPLE_MACOS_INSTALLER_IDENTITY`
- `APPLE_NOTARY_KEY_P8_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- Optional variable `IOS_EXPORT_METHOD`, default `app-store-connect`.

The provisioning profile's team identifier is verified before export. macOS
publication requires a successful blocking notarization request and a validated
stapled ticket.

### Windows

- `WINDOWS_SIGNING_PFX_BASE64`
- `WINDOWS_SIGNING_PFX_PASSWORD`
- `WINDOWS_PACKAGE_IDENTITY_NAME`
- `WINDOWS_PACKAGE_PUBLISHER`
- `WINDOWS_EXPECTED_CERT_THUMBPRINT`

The generated MSIX is a full-trust packaged classic desktop application. The
certificate subject must exactly equal the publisher in the package manifest.
Both `signtool` and `Get-AuthenticodeSignature` must report a valid signature.

### Linux

- `LINUX_SIGNING_KEY_BASE64`
- `LINUX_SIGNING_KEY_ID`
- `LINUX_SIGNING_PASSPHRASE`
- Variable `APPIMAGETOOL_URL`
- Variable `APPIMAGETOOL_SHA256`

The Debian package and AppImage receive detached armored signatures. Production
APT distribution additionally requires the operator's signed repository
metadata; a detached package signature is not represented as an APT repository
signature.

Linux camera capture uses the distribution GStreamer registry. The Debian
package declares `libegl1`, `libgles2`, `libsecret-1-0`, `libgstreamer1.0-0`,
`libgstreamer-plugins-base1.0-0`,
`gstreamer1.0-plugins-base`, and `gstreamer1.0-plugins-good`; the x86-64
AppImage documents the same required
host packages in its embedded `APPIMAGE-RUNTIME.md`. Packaging fails if the
desktop camera plugin is missing or has an unresolved native link dependency.

### Hosted web and browser acceptance

- `WEB_DEPLOY_WEBHOOK_URL`
- `WEB_DEPLOY_WEBHOOK_TOKEN`
- Variable `E2E_API_BASE_URL`: absolute HTTPS API origin. The legacy secret of
  the same name is accepted temporarily while deployments migrate it to a
  variable.
- Secret `E2E_USER_EMAIL`: dedicated synthetic account address. Do not use a
  person's mailbox or an account with production household information.
- Variable `E2E_MAILBOX_IMAP_HOST`
- Optional variable `E2E_MAILBOX_IMAP_PORT`, default `993`
- Optional variable `E2E_MAILBOX_IMAP_SECURE`, which must remain `true`
- Optional variable `E2E_MAILBOX_IMAP_FOLDER`, default `INBOX`
- Optional variable `E2E_MAILBOX_TIMEOUT_SECONDS`, default `120` and bounded
  from 30 to 300 seconds
- Secret `E2E_MAILBOX_IMAP_USER`
- Secret `E2E_MAILBOX_IMAP_PASSWORD`, preferably an app-specific,
  read-only mailbox credential

The deployment hook receives only source/run metadata and the PWA archive
checksum. It is responsible for obtaining the workflow artifact using its own
least-privilege GitHub identity and performing an atomic hosted deployment.

Browser automation covers Chrome, Firefox, Playwright WebKit and Edge. WebKit
is an engine-level gate and is not evidence of physical Safari acceptance.
Chrome runs the authenticated mailbox flow. The other engines run the PWA and
persistence checks without requesting another email, keeping a workflow retry
inside the backend's five-attempt per-address window.

Authenticated browser acceptance uses the API 2.1.0 email-code protocol. It
requests a challenge for a fresh installation, reads only a newly arrived
verification message addressed to the controlled synthetic account, and enters
the code through the same browser's JSON API context. It verifies that an
incorrect binding token fails and that a consumed code cannot be replayed.

The harness checks `/api/v1/me`, the authorized home list, installation versus
account-device identity, secure cookie attributes, another tab's cookie
session, refresh rotation, and logout revocation. The synthetic account must
already have a home for this release acceptance scenario. New account/profile
creation is covered by the onboarding workflow tests.

TLS IMAP and API waits are bounded. Evidence contains check outcomes and timing,
not mailbox contents, addresses, numeric codes, challenge bindings, CSRF proofs
or cookie values. The parser accepts only the backend verification template
and rejects ambiguous code messages. Reserve the mailbox for automated
acceptance and restrict its credentials to reading where supported. Only the
Chrome job reads it; other engines test PWA persistence without sending codes.

## Fail-closed behavior

Tag builds and manual runs with `publish=true` fail when any required protected
credential, certificate identity, endpoint or pinned tool digest is missing.
Manual artifact-only runs may explicitly skip a platform when credentials are
absent; the workflow writes that outcome to the run summary and produces no
unsigned substitute. No workflow labels development-signed or ad-hoc output as
a production artifact.

## External evidence that cannot be manufactured by CI

Attach the following to the release record before certification:

1. Android installation, upgrade and camera/media permission results on at
   least one currently supported physical phone and one supported tablet.
2. iOS installation and upgrade from TestFlight on supported physical iPhone
   and iPad hardware, including camera, photo-library, background/resume and
   secure credential behavior.
3. macOS Gatekeeper launch results on Intel and Apple Silicon, plus the
   notarization request identifier.
4. Windows clean install, upgrade, uninstall and SmartScreen/certificate result
   on supported x64 Windows; Arm64 requires a separate native build and must not
   be inferred from x64.
5. AppImage and Debian clean-install/upgrade tests on supported distributions,
   including desktop integration and local database persistence.
6. Real Safari testing on current macOS and iOS, in addition to WebKit CI.
7. Chrome, Firefox and Edge tests against the hosted PWA, including offline
   reload, IndexedDB persistence, numeric email-code verification in the requesting browser,, session refresh and logout.
8. A dedicated synthetic account and controlled mailbox proving authenticated
   cross-device data convergence without exposing production household
   information.
9. Store-console validation screenshots or exported reports for Google Play,
   App Store Connect and Microsoft Partner Center where those channels are
   selected.

Evidence must record version, commit, platform/OS version, hardware, tester,
timestamp, outcome and linked defect. Missing evidence remains an open release
gate; it is never converted into a passing checkbox by documentation alone.

## Release sequence

1. Merge only green quality, contract and structural checks.
2. Create the semantic `v<version>` tag from the approved commit.
3. Let every protected platform workflow complete without substitution.
4. Verify each artifact against its `SHA256SUMS` and platform signature.
5. Archive SBOM, provenance, release manifest and external device evidence.
6. Invoke hosted deployment and store uploads only from the protected release
   environment.
7. Run browser acceptance against the deployed immutable web version.
8. Promote only after device, hosted authentication, backup and rollback gates
   are attached to the release record.
