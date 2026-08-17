---
name: install-ios-dev-build
description: Build, sign, install, and launch the current ReFineID code on a connected development iPhone. Use when asked to put a build on the dev phone or test on a real device.
---

# Install a development build on the dev iPhone

`Scripts/install-ios-development.sh` builds an optimized Profile-configuration
build, signs it, installs it on one connected iPhone, and launches it. It
overrides the version on the command line, so repeated device builds create no
version-only Git changes.

## Steps

1. Find the connected device's identifier. Use the UUID of a device shown as
   `available (paired)`:

   ```sh
   xcrun devicectl list devices
   ```

2. Run the lint gate and confirm `lint gate PASS` before building:

   ```sh
   ./Scripts/lint.sh
   ```

3. Build, sign, install, and launch on that device:

   ```sh
   ./Scripts/install-ios-development.sh <device-identifier>
   ```

   Success ends with `installed and launched ReFineID <version> (<build>)`.

## Notes

- The device must be connected, paired, trusted, with developer mode enabled.
- This installs a development build. Never distribute it as a release.
- Building commits nothing. Commit and push happen separately in the main
  thread, only after the lint gate passes and the build is clean.
