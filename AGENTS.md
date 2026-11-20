# ellekit-panel

An app and a root helper that turn tweak injection off and on for the
jailbreak on this device (Dopamine on roothide, with ElleKit as the hooking
library).

## How injection is actually switched

The jailbreak's `systemhook-<hash>.dylib` decides, per spawned process,
whether to inject `TweakInject/*.dylib`. Its `_should_enable_tweaks` returns
false when any of these holds, checked in this order:

1. the file `<jbroot>/basebin/.safe_mode` exists (`access`, not getenv)
2. `DISABLE_TWEAKS=1` in that process's environment
3. `jbclient_dopamine_is_jailbroken()` says no
4. `_SafeMode=1` or `_MSSafeMode=1` in the environment
5. the process is xpcproxy and not on its allow list

Only (1) is global and persistent: it is a file on disk, re-checked at every
spawn, and it is what this package writes. ElleKit's own notice
`/var/mobile/.eksafemode` is **not** read by this jailbreak's injector — it
only matters to ElleKit's own launchd hook, which Dopamine does not use.

This is verified on the device: with the marker present a fresh process loads
zero `TweakInject` dylibs (132 images), without it four injection images
(139 images). `systemhook` and `libellekit.dylib` stay loaded either way;
the marker stops tweaks, not the hooking library.

A change only affects processes started afterwards. SpringBoard keeps what
it started with until it is respawned, which is what the app's respring
button does.

## Layout

    app/include/EKPanel.h        shared constants and helpers
    app/include/EKPanelPaths.m   jbroot resolution (never stored)
    app/daemon/ekpaneld.m        root helper
    app/daemon/ekpanel.h         helper-only constants
    app/App/main.m               the UIKit app
    app/res/                     Info.plist, daemon plist, maintainer scripts
    apelin/build.sh              builds the .deb

The app runs as mobile and cannot write `/basebin` (root:wheel 0755, and the
jailbreak's sandbox profile denies it). It writes a request plist under
`/var/mobile/Library/Preferences/`; the helper polls for it, applies the
action, and writes a result plist back. One exchange at a time.

## Building

`apelin_project_build` runs `apelin/build.sh`. It needs no installed
toolchain: the bootstrap's own clang 14 is enough. Notes that cost time to
learn:

- Build **arm64**. A bootstrap clang's arm64e output fails with
  "Bad CPU type in executable" on this device (A11), even on roothide.
- The helper must be signed with **no-sandbox** or the write into `/basebin`
  fails with EPERM. `apelin/build.sh` takes the entitlements from
  `ldid -e /bin/bash` and falls back to `app/res/ent.plist`. Do not sign it
  plain `ldid -S`.
- A binary placed in the project folder cannot be executed (SIGKILL); it has
  to live somewhere the jailbreak trusts, such as `$APELIN_PREFIX/usr/bin`.
- Paths in C/ObjC are kernel paths. On roothide that means
  `<jbroot>/basebin/.safe_mode`, resolved at run time with
  `EKPanelBootstrapPath`; never persist the resolved jbroot.

## Checking it

    /var/jb/usr/libexec/ellekit-panel/ekpaneld --status
    cat /var/jb/var/mobile/Library/Preferences/wiki.qaq.ellekit-panel.result.plist

`--apply enable|disable|respring|status` runs one action without the daemon.
