#!/usr/bin/env bash
# Peekix 動作確認用スクリーンショット取得スクリプト
#
# 前提:
#   - build/Peekix.app がビルド済み
#   - RTSP_URL を環境変数で渡す（または UserDefaults に rtspURL が設定済み）
#   - System Events / Screen Recording / Accessibility の権限を Terminal に付与
#
# 使い方:
#   RTSP_URL="rtsp://user:pass@host/path" scripts/capture-verification.sh
#
# 出力:
#   build/screenshots/01-normal.png        通常モード
#   build/screenshots/02-mini.png          ミニモード（タイトルバーなし）
#   build/screenshots/03-back-to-normal.png 復帰確認
#   build/screenshots/04-resized-wide.png  横に広げた後（黒帯出ないか）
#   build/screenshots/05-zoomed.png        スクロールズーム後

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Peekix.app"
OUT="$ROOT/build/screenshots"
RTSP_URL="${RTSP_URL:-${PEEKIX_RTSP_URL:-}}"

if [[ ! -d "$APP" ]]; then
  echo "ERROR: $APP not found. Build first: xcodebuild ... in App/" >&2
  exit 1
fi

mkdir -p "$OUT"
rm -f "$OUT"/*.png

# 既存プロセスを終了
osascript -e 'tell application "Peekix" to quit' >/dev/null 2>&1 || true
sleep 1

# RTSP URL を環境変数で渡して起動
if [[ -n "$RTSP_URL" ]]; then
  PEEKIX_RTSP_URL="$RTSP_URL" open -n "$APP"
else
  open -n "$APP"
fi

echo "==> 起動待機 (映像接続まで)..."
sleep 5

# ウィンドウID取得 (Peekix のフロントウィンドウ)
get_window_id() {
  /usr/bin/osascript <<'EOS'
tell application "System Events"
  tell process "Peekix"
    if (count of windows) = 0 then return ""
    set winRef to window 1
    return value of attribute "AXWindowID" of winRef as string
  end tell
end tell
EOS
}

capture() {
  local name="$1"
  local wid
  wid="$(get_window_id || true)"
  if [[ -n "$wid" ]]; then
    /usr/sbin/screencapture -l"$wid" -o -x "$OUT/$name.png" || \
      /usr/sbin/screencapture -x "$OUT/$name.png"
  else
    /usr/sbin/screencapture -x "$OUT/$name.png"
  fi
  echo "  saved $OUT/$name.png"
}

send_key() {
  # 引数: AppleScript key code
  local code="$1"
  /usr/bin/osascript <<EOS
tell application "Peekix" to activate
delay 0.3
tell application "System Events" to key code $code
EOS
}

resize_window() {
  local w="$1" h="$2"
  /usr/bin/osascript <<EOS
tell application "System Events"
  tell process "Peekix"
    set size of window 1 to {$w, $h}
  end tell
end tell
EOS
}

scroll_zoom() {
  # CGEvent で scrollWheel を送る Swift ワンライナー
  /usr/bin/swift - <<'SWIFTEOS'
import CoreGraphics
import Foundation
// 連続スクロールでズームイン
for _ in 0..<30 {
  if let ev = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 30, wheel2: 0, wheel3: 0) {
    ev.post(tap: .cghidEventTap)
  }
  usleep(30_000)
}
SWIFTEOS
}

echo "==> 1) 通常モードを撮影"
capture "01-normal"

echo "==> 2) Mキーでミニモード化"
send_key 46  # m
sleep 1
capture "02-mini"

echo "==> 3) Mキーで通常へ復帰"
send_key 46
sleep 1
capture "03-back-to-normal"

echo "==> 4) ウィンドウを横に広げて黒帯が出ないか確認"
resize_window 1200 400 || true
sleep 1
capture "04-resized-wide"

echo "==> 5) スクロールズーム"
# マウスをウィンドウ中央付近へ移動してからスクロール
/usr/bin/osascript <<'EOS' || true
tell application "System Events"
  tell process "Peekix"
    set {x, y} to position of window 1
    set {w, h} to size of window 1
  end tell
end tell
EOS
scroll_zoom || true
sleep 0.5
capture "05-zoomed"

echo
echo "完了: $OUT"
ls -la "$OUT"
