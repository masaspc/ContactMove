#!/bin/bash
# ContactMoveKit のユニットテストと、アプリのシミュレータビルドを実行する。
# Mac 上で実行すること(Xcode 16 以上)。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> ContactMoveKit: swift test"
(cd ContactMoveKit && swift test)

if command -v xcodebuild >/dev/null 2>&1; then
  SIM_NAME="${SIM_NAME:-iPhone 16}"
  echo "==> xcodebuild: シミュレータ ($SIM_NAME) 向けビルド"
  xcodebuild -project ContactMove.xcodeproj \
    -scheme ContactMove \
    -destination "platform=iOS Simulator,name=$SIM_NAME" \
    build | tail -20
else
  echo "xcodebuild が見つからないためアプリのビルドはスキップしました"
fi
