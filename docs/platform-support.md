# Supported platforms and build evidence

The upstream support baseline comes from Flutter 3.44.7 documentation. A
platform is not claimed as release-verified until the corresponding CI build
and release test pass.

| Target | Upstream Flutter 3.44.7 baseline | Phase 1 CI proof |
|---|---|---|
| Android | API 24–37 | Debug APK compile on Ubuntu; no device certification yet |
| iOS | iOS 13–26 | Unsigned release compile on macOS; no device/signing proof yet |
| Windows | Windows 10/11, x64 and Arm64 | Release compile on `windows-2025`; runner architecture only |
| macOS | macOS 10.15–26, x64 and Arm64 | Release compile on `macos-15`; runner architecture only |
| Debian | Debian 10–13, x64 and Arm64 | No Debian runner in Phase 1 |
| Ubuntu | Ubuntu 20.04–24.04 LTS, x64 and Arm64 | Release compile on Ubuntu 24.04 x64 |
| Chrome | Current release meeting the secure-storage features below | Web compile plus required PR synthetic WASM/WebCrypto persistence probe; final CI outcome required |
| Firefox | Feature-gated, version acceptance pending | Runtime browser matrix pending |
| Safari | Feature-gated, version acceptance pending | Runtime browser matrix pending; no Safari 15.6+ guarantee |
| Edge | Feature-gated, version acceptance pending | Runtime browser matrix pending |

Browser storage requires HTTPS (or a browser-trusted loopback context),
WebCrypto PBKDF2/AES-GCM, Web Locks, IndexedDB database enumeration and strict
transaction durability, OPFS directory inspection, and the pinned SQLite WASM.
The app refuses unsupported/unreadable storage rather than falling back to
plaintext or an ephemeral database. Unlock uses a separate local-data passphrase;
account sign-in remains the existing email-code flow. See
[database security](local-database-security.md) for loss/recovery and legacy
browser-data handling. The October repair workspace cannot run Chromium because
of environment process-socket restrictions; the final PR CI probe is the
required real-browser evidence, and does not certify a complete browser matrix.

The earlier Ubuntu 26.04 statement is not carried forward because the official
Flutter table verified for this phase ends at Ubuntu 24.04 LTS.

Protected Phase 9–10 workflows implement these release formats:

- Android App Bundle plus test APK
- signed iOS archive
- signed Windows installer or MSIX
- signed and notarized macOS application
- AppImage and Debian package
- hosted authenticated Flutter web/PWA build

Routine pull-request CI and local commands still produce non-production build
proofs. Android local release configuration uses the debug key. The protected
release workflows require environment-owned signing identities and fail closed
when those inputs are absent; their existence alone does not claim device,
notarization, installer, browser, Arm64, or store acceptance.

The first Linux release lane is x86-64. Its desktop camera plugin uses the
host's GTK and GStreamer runtime; exact AppImage host packages and Debian
dependencies are versioned in `tools/agent-requirements.json` and
`packaging/linux/APPIMAGE-RUNTIME.md`.

`path_provider_android` is deliberately locked to 2.2.23, the last reviewed
pre-JNI implementation. Its 2.3.x Android native-asset graph otherwise places
`libdartjni.so` in Linux bundles even though the desktop client has no JNI
runtime edge. Upgrade that pin only after Android and clean-host Linux package
gates prove the JNI packages and library remain absent.
