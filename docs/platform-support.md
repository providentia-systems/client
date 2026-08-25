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
| Chrome | Latest two supported releases | Web compile only; browser matrix pending |
| Firefox | Latest two supported releases | Web compile only; browser matrix pending |
| Safari | 15.6+ | Web compile only; browser matrix pending |
| Edge | Latest two supported releases | Web compile only; browser matrix pending |

The earlier Ubuntu 26.04 statement is not carried forward because the official
Flutter table verified for this phase ends at Ubuntu 24.04 LTS.

Required release formats remain future acceptance work:

- Android App Bundle plus test APK
- signed iOS archive
- signed Windows installer or MSIX
- signed and notarized macOS application
- AppImage and Debian package
- hosted authenticated Flutter web/PWA build

Phase 1 CI uploads non-production build proofs only. Android local release
configuration uses the debug key; other targets are not production-signed. CI
does not claim notarization, installer quality, browser compatibility, Arm64
coverage, or store acceptance.

The first Linux release lane is x86-64. Its desktop camera plugin uses the
host's GTK and GStreamer runtime; exact AppImage host packages and Debian
dependencies are versioned in `tools/agent-requirements.json` and
`packaging/linux/APPIMAGE-RUNTIME.md`.

`path_provider_android` is deliberately locked to 2.2.23, the last reviewed
pre-JNI implementation. Its 2.3.x Android native-asset graph otherwise places
`libdartjni.so` in Linux bundles even though the desktop client has no JNI
runtime edge. Upgrade that pin only after Android and clean-host Linux package
gates prove the JNI packages and library remain absent.
