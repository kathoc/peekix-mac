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
#   Scripts/sparkle-release.sh path/to/Peekix.app [output.zip]
#
# 動作:
#   - .app をクリーンステージにコピーし、xattr/.DS_Store/AppleDouble を除去
#   - ditto でシンボリックリンクを保ったまま zip 化（リソースフォークも除外）
#   - sign_update でEdDSA署名し、length と sparkle:edSignature を出力
#
# 出力は appcast.xml の <enclosure> に手動で反映してください。
set -euo pipefail

APP="${1:-}"
OUT="${2:-}"

if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: $0 path/to/Peekix.app [output.zip]" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ -z "$OUT" ]]; then
  OUT="Peekix-${VERSION}.zip"
fi

STAGE_DIR="$(mktemp -d -t peekix-stage)"
trap 'rm -rf "$STAGE_DIR"' EXIT

echo "Staging $APP -> $STAGE_DIR"
ditto "$APP" "$STAGE_DIR/Peekix.app"
xattr -cr "$STAGE_DIR/Peekix.app"
find "$STAGE_DIR/Peekix.app" \( -name '._*' -o -name '.DS_Store' \) -delete

echo "Verifying code signature on staged bundle"
codesign --verify --deep --strict "$STAGE_DIR/Peekix.app"

echo "Packaging $OUT (preserving symlinks, no resource forks)"
rm -f "$OUT"
ditto -c -k --keepParent --norsrc --noextattr --noacl "$STAGE_DIR/Peekix.app" "$OUT"

# Self-test: extracted bundle must keep symlinks and pass codesign.
TEST_DIR="$(mktemp -d -t peekix-verify)"
trap 'rm -rf "$STAGE_DIR" "$TEST_DIR"' EXIT
unzip -q "$OUT" -d "$TEST_DIR"
if [[ ! -L "$TEST_DIR/Peekix.app/Contents/Frameworks/Sparkle.framework/Versions/Current" ]]; then
  echo "ERROR: Sparkle.framework symlinks were not preserved in $OUT" >&2
  exit 1
fi
codesign --verify --deep --strict "$TEST_DIR/Peekix.app"

SIGN_TOOL="$(xcrun --find sign_update 2>/dev/null || true)"
if [[ -z "$SIGN_TOOL" ]]; then
  SIGN_TOOL="$(find "${HOME}/Library/Developer/Xcode/DerivedData" -type f -name sign_update 2>/dev/null | head -1)"
fi
if [[ -z "$SIGN_TOOL" || ! -x "$SIGN_TOOL" ]]; then
  echo "sign_update が見つかりません。Sparkle配布物の bin/sign_update をPATHに置くか、Xcodeで一度ビルドしてください。" >&2
  exit 1
fi

echo "Signing $OUT with $SIGN_TOOL"
"$SIGN_TOOL" "$OUT"
