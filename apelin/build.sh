#!/bin/sh
# Builds the ellekit-panel package: an app, a root helper and its launch daemon.
set -eu
: "${APELIN_PACKAGE_DIR:?run this through apelin_project_build}"
: "${APELIN_PROJECT_ROOT:?}" "${APELIN_BOOTSTRAP:?}" "${APELIN_ARCHITECTURE:?}"
: "${APELIN_BUILD_ID:?}" "${TMPDIR:?}"
cd "$APELIN_PROJECT_ROOT"

stage=$(mktemp -d "${TMPDIR:?}stage.XXXXXX")
trap 'rm -rf -- "${stage:?}"' EXIT
out="${TMPDIR:?}out"
rm -rf -- "${out:?}"
mkdir -p "$out"

if [ "$APELIN_BOOTSTRAP" = rootless ]; then
    BDEF=-DAPELIN_BOOTSTRAP_ROOTLESS=1
else
    BDEF=-DAPELIN_BOOTSTRAP_ROOTHIDE=1
fi
BASE="-fobjc-arc -O2 -Iapp/include -Iapp/daemon $BDEF"

# The package is arm64e on roothide and arm64 on rootless, but every binary
# carries BOTH slices. A bootstrap clang emits arm64e in an ABI this device's
# kernel rejects ("Bad CPU type"), while an arm64-only binary in an arm64e
# package would not run on a device that only has arm64e. A universal binary
# lets each device pick the slice it accepts.
for slice in arm64 arm64e; do
    clang -arch $slice $BASE -framework UIKit -framework Foundation \
        -o "$out/ellekit-panel.$slice" app/App/main.m app/include/EKPanelPaths.m
    clang -arch $slice $BASE -framework Foundation \
        -o "$out/ekpaneld.$slice" app/daemon/ekpaneld.m app/include/EKPanelPaths.m
done
lipo -create -output "$out/ellekit-panel" "$out/ellekit-panel.arm64" "$out/ellekit-panel.arm64e"
lipo -create -output "$out/ekpaneld" "$out/ekpaneld.arm64" "$out/ekpaneld.arm64e"
rm -f "$out/ellekit-panel.arm64" "$out/ellekit-panel.arm64e" \
      "$out/ekpaneld.arm64" "$out/ekpaneld.arm64e"

# The helper needs no-sandbox: the jailbreak's profile otherwise refuses
# writes into /basebin. Take the bootstrap's own entitlements when it has them.
ent="${TMPDIR:?}ent.plist"
if ! ldid -e /bin/bash >"$ent" 2>/dev/null || [ ! -s "$ent" ]; then
    cp app/res/ent.plist "$ent"
fi
ldid -S "$out/ellekit-panel"
ldid -S"$ent" "$out/ekpaneld"
rm -f -- "$ent"

app="$stage$APELIN_PREFIX/Applications/ElleKitPanel.app"
mkdir -p "$app"
cp "$out/ellekit-panel" "$app/ellekit-panel"
cp app/res/Info.plist "$app/Info.plist"
cp app/res/icons/*.png "$app/"

mkdir -p "$stage$APELIN_PREFIX/usr/libexec/ellekit-panel"
cp "$out/ekpaneld" "$stage$APELIN_PREFIX/usr/libexec/ellekit-panel/ekpaneld"

mkdir -p "$stage$APELIN_PREFIX/Library/LaunchDaemons"
sed "s|@PREFIX@|$APELIN_PREFIX|g" app/res/wiki.qaq.ellekit-panel.daemon.plist \
    >"$stage$APELIN_PREFIX/Library/LaunchDaemons/wiki.qaq.ellekit-panel.daemon.plist"

chmod 755 "$app/ellekit-panel" "$stage$APELIN_PREFIX/usr/libexec/ellekit-panel/ekpaneld"

mkdir -p "$stage/DEBIAN"
sed "s|@PREFIX@|$APELIN_PREFIX|g" app/res/postinst >"$stage/DEBIAN/postinst"
sed "s|@PREFIX@|$APELIN_PREFIX|g" app/res/postrm >"$stage/DEBIAN/postrm"
chmod 755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/postrm"
sed "s|@ARCH@|$APELIN_ARCHITECTURE|g" app/res/control.in >"$stage/DEBIAN/control"

mkdir -p "$APELIN_PACKAGE_DIR"
dpkg-deb -b --root-owner-group "$stage" "$APELIN_PACKAGE_DIR/" >/dev/null
ls -l "$APELIN_PACKAGE_DIR"
