# Providentia AppImage camera runtime

The x86-64 AppImage deliberately uses the supported distribution GStreamer
runtime rather than embedding a second plugin registry. Install these host
packages before launching it:

- `libegl1`
- `libgtk-3-0`
- `libsecret-1-0`
- `libgstreamer1.0-0`
- `libgstreamer-plugins-base1.0-0`
- `gstreamer1.0-plugins-base`
- `gstreamer1.0-plugins-good`

The Debian package declares the same packages in its dependency metadata. The
release build fails if `libcamera_desktop_plugin.so` is absent or has an
unresolved link dependency on the packaging host.
