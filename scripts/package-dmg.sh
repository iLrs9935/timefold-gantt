#!/bin/zsh
set -euo pipefail
TASK_ROOT="${0:A:h:h}"
cd "$TASK_ROOT"
TASK_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
TASK_NAME="Timefold-${TASK_VERSION}-macOS-arm64"
TASK_STAGE=$(mktemp -d "${TMPDIR:-/tmp/}timefold-dmg.XXXXXX")
trap 'rm -rf "$TASK_STAGE"' EXIT
./scripts/build.sh
mkdir -p dist
ditto "dist/时序.app" "$TASK_STAGE/时序.app"
ln -s /Applications "$TASK_STAGE/Applications"
sed 's/(MAINTENANCE.md)/(维护声明.md)/g; s/(LICENSE)/(LICENSE.txt)/g' SOFTWARE_GUIDE.md > "$TASK_STAGE/软件说明.md"
cp MAINTENANCE.md "$TASK_STAGE/维护声明.md"
cp LICENSE "$TASK_STAGE/LICENSE.txt"
sed 's/(MAINTENANCE.en.md)/(Maintenance.md)/g; s/(SOFTWARE_GUIDE.md)/(软件说明.md)/g; s/(LICENSE)/(LICENSE.txt)/g' SOFTWARE_GUIDE.en.md > "$TASK_STAGE/User Guide.md"
sed 's/(MAINTENANCE.md)/(维护声明.md)/g; s/(LICENSE)/(LICENSE.txt)/g' MAINTENANCE.en.md > "$TASK_STAGE/Maintenance.md"
cat > "$TASK_STAGE/安装说明.txt" <<'TXT'
时序 · macOS 桌面甘特图
适用于 macOS 13+，Apple Silicon（arm64）。

将「时序.app」拖到「Applications」文件夹，再从应用程序中打开。
默认呼出快捷键：Control + Option + G。
文字排期：Command + Shift + N。

当前发布使用临时签名，未经过 Apple Developer ID 签名与公证。
请核对下载来源和随发布提供的 SHA-256 校验值。

软件说明见「软件说明.md」，维护态度见「维护声明.md」。
TXT
cat > "$TASK_STAGE/Install.txt" <<'TXT'
Timefold · Desktop Gantt for macOS
macOS 13+ · Apple Silicon (arm64)

Drag the app into Applications, then open it from Applications.
Show / hide: Control + Option + G. Text scheduling: Command + Shift + N.
Switch languages in Settings (...) > Language / 语言.

This build is ad-hoc signed, not Apple Developer ID signed or notarized.
Verify the download source and the supplied SHA-256 checksum.
Read User Guide.md, Maintenance.md and LICENSE.txt for details.
TXT
hdiutil create -volname "时序 ${TASK_VERSION}" -srcfolder "$TASK_STAGE" -ov -format UDZO "dist/${TASK_NAME}.dmg"
hdiutil verify "dist/${TASK_NAME}.dmg"
(cd dist && shasum -a 256 "${TASK_NAME}.dmg" > "${TASK_NAME}.dmg.sha256")
