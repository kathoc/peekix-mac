#!/usr/bin/env bash
# Sparkle release helper.
#
# Prereqs (one-time):
#   1. EdDSA鍵を生成:
#        $(xcrun --find generate_keys)  # キーチェーンに保存
#      または Sparkle 配布物の `bin/generate_keys` を実行
#   2. 出力された Public key (Base64) を App/Peekix/Info.plist の SUPublicEDKey に貼る
#
# Usage:
#   Scripts/sparkle-release.sh path/to/Peekix-x.y.z.zip
#
# 出力:
#   - Sparkle署名 (sparkle:edSignature, length) を標準出力
#   - 既存の appcast.xml に手動で追記してください
set -euo pipefail

ZIP="${1:-}"
if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  echo "usage: $0 path/to/Peekix-x.y.z.zip" >&2
  exit 1
fi

DERIVED="$(xcodebuild -showBuildSettings -workspace App/Peekix.xcodeproj/project.xcworkspace -scheme Peekix 2>/dev/null | awk '/ BUILD_DIR / {print $3}')"
SPARKLE_DIR="$(find "${DERIVED:-$HOME/Library/Developer/Xcode/DerivedData}" -type d -name 'Sparkle.framework' -path '*/SourcePackages/*' 2>/dev/null | head -1 || true)"
SIGN_TOOL="$(xcrun --find sign_update 2>/dev/null || true)"
if [[ -z "$SIGN_TOOL" ]]; then
  SIGN_TOOL="$(find "${HOME}/Library/Developer/Xcode/DerivedData" -type f -name sign_update 2>/dev/null | head -1)"
fi
if [[ -z "$SIGN_TOOL" || ! -x "$SIGN_TOOL" ]]; then
  echo "sign_update が見つかりません。Sparkle配布物の bin/sign_update をPATHに置くか、SwiftPMで一度ビルドしてください。" >&2
  exit 1
fi

echo "Signing $ZIP with $SIGN_TOOL"
"$SIGN_TOOL" "$ZIP"
