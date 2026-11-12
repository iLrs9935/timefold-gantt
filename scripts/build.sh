#!/bin/zsh
set -euo pipefail
TASK_ROOT="${0:A:h:h}"
cd "$TASK_ROOT"
swift build -c release
TASK_APP="$TASK_ROOT/dist/时序.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
cp .build/release/Timefold "$TASK_APP/Contents/MacOS/Timefold"
cp Resources/Info.plist "$TASK_APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$TASK_APP/Contents/Resources/AppIcon.icns"
fi
for TASK_LANG in en zh-Hans; do
  ditto "Resources/${TASK_LANG}.lproj" "$TASK_APP/Contents/Resources/${TASK_LANG}.lproj"
done
codesign --force --sign - "$TASK_APP"
print "已生成：$TASK_APP"
