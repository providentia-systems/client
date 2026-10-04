# Providentia AppImage runtime

The x86-64 AppImage deliberately uses the supported distribution GStreamer
runtime rather than embedding a second plugin registry. Install these host
packages before launching it:

- `libegl1`
- `libgles2`
- `libgtk-3-0`
- `libsecret-1-0`
- `libgstreamer1.0-0`
- `libgstreamer-plugins-base1.0-0`
- `gstreamer1.0-plugins-base`
- `gstreamer1.0-plugins-good`
- `xdg-user-dirs`

`xdg-user-dirs` provides `xdg-user-dir`, used by Linux directory discovery. It
is required on minimal profiles even when native shared-library checks pass.
The Debian package declares these runtime packages in its dependency metadata;
AppImage users must install them on the host. Neither package moves an existing
household database or changes its directory-selection policy.

The release build fails if `libcamera_desktop_plugin.so` is absent or has an
unresolved link dependency on the packaging host. Debian launch verification
also requires a visible Flutter first frame and rejects startup exceptions from
a fresh temporary profile. Merely surviving until a timeout is not acceptance.
The headless verification environment additionally needs `xvfb` and `x11-utils`;
these are test tools, not application runtime dependencies.
