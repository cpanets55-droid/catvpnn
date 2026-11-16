# CatVPN Nord

Flutter VPN client. Android connects using WireGuard; iOS uses the system
IKEv2 VPN service with NordVPN service credentials and can export a WireGuard
configuration when those credentials are missing. iOS does not expose traffic
byte counters through NEVPNManager, so the UI shows unavailable counters.

## Jailbreak packages

Distribution repository: <https://wormfake.github.io/catvpnn/>.
Build source: <https://github.com/wormfake/catvpnn>.
GitHub Pages serves the repository; GitHub Actions or Codemagic compiles the app.

Each build emits **three different Debian packages**. Install exactly one:

| Package | Debian architecture | Installed application |
| --- | --- | --- |
| `com.catvpn.nord.rootful` | `iphoneos-arm` | `/Applications/CatVPNNord.app` |
| `com.catvpn.nord.rootless` | `iphoneos-arm64` | `/var/jb/Applications/CatVPNNord.app` |
| `com.catvpn.nord.roothide` | `iphoneos-arm64e` | `/Applications/CatVPNNord.app` inside RootHide's jbroot |

Choose by the jailbreak's `dpkg --print-architecture`, **not by the phone's CPU
or whether the package manager is Cydia or Sileo**. The pre-install script checks
this value even if someone attempts to force a mismatching package. The packages
also conflict with one another to prevent simultaneous installation.

The current Flutter/Xcode project requires **iOS 15.0 or newer**, including the
rootful package. Rootful does not imply support for iOS 13/14 or 32-bit devices.
The packager reads MinimumOSVersion from the app and its frameworks and uses
the highest value as its firmware dependency.

RootHide uses its own entitlement profile. Its shell resolves /Applications
inside jbroot; no randomized .jbroot-* directory is hard-coded. The app uses
system frameworks and bundle-relative Flutter frameworks. New dependencies on
jailbreak libraries must be rebuilt with the RootHide SDK instead of merely
changing the package architecture.

References: [Theos rootless layout](https://theos.dev/docs/rootless),
[RootHide paths](https://github.com/roothide/Developer/blob/master/roothide.md),
[RootHide entitlements](https://github.com/roothide/Developer/blob/master/entitlements.md).

### Upgrade from the old 1.0.4 packages

Remove the old rootless/RootHide package using its package manager **before**
installing the new package. Those old installers copied the app into a fixed
external container or installed it using TrollStore. The new installer refuses
an in-place upgrade from those versions so that two installations of the same
bundle ID are not registered together. If an independently installed TrollStore
copy remains, remove that copy through TrollStore first. Export any settings you
need before removing an old installation.

New packages let dpkg own the app directory, register it with uicache, and
unregister it before removal. They do not delete arbitrary app containers,
silently ignore signing errors, or invoke TrollStore to install another app.

## Build

Use Flutter **3.50.0** and Xcode on macOS (local, GitHub Actions, or Codemagic):

```sh
flutter pub get
flutter analyze --no-fatal-infos
flutter test
python3 -m unittest discover -s scripts/tests -v
flutter build ios --release --no-codesign
python3 scripts/package_jailbreak.py
```

The output is `dist/jailbreak/`, containing `debs/*.deb`, the Packages indexes,
Release, and build-manifest.json with source/binary checksums. By default the
Debian version comes from the built app's version and build number; for this
source version the filenames end with `_1.0.5+2_<architecture>.deb`.
The output directory must be empty. `--output <new-directory>` and `--version`
are available for a separate release. No existing published package is overwritten.

The packager signs nested Mach-O binaries and frameworks before signing the app,
then runs `codesign --verify --deep --strict`. A signing failure stops packaging.
It requires macOS codesign: packaging tests run on Windows/Linux, but an IPA
compiled before a source change cannot contain that change.

The iOS workflow builds only the three jailbreak DEBs and APT indexes; it does
not create sideload or TrollStore IPAs. The GitHub artifact is
CatVPN-Nord-Jailbreak-DEBs.
The Codemagic workflow publishes the same files as build artifacts.
Both use the same packaging script. A green Pages deployment only confirms the
repository files were published, not that the application was compiled.

Before publishing, test launch, VPN permission, connect/disconnect, server
switching, background/resume, reinstall, and removal on each target jailbreak.
Host tests and codesign verification do not establish compatibility on a device.
Upload the new DEBs before replacing all Packages indexes and Release together;
keep the site's existing HTML/icon/IPA assets. No workflow auto-deploys packages.

Nord credentials can be entered in the app. For a private build, the existing
NORD_TOKEN, NORD_PRIV_KEY, NORD_USER, and NORD_PASS build variables remain
supported. Do not distribute a binary containing your personal credentials.
