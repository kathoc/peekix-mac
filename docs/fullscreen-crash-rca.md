# フルスクリーン⇄通常ウィンドウ遷移クラッシュ — RCA と恒久対策

## 症状
RTSP 再生中に Cmd+Ctrl+F または緑ボタンでフルスクリーン化→復帰を繰り返すと、数回〜十数回でアプリがクラッシュ。

## 再現方法（自動ストレスハーネス）
ソースに `PEEKIX_FS_STRESS=N` 環境変数で起動するセルフストレスハーネスを追加した（`PlaybackViewModel.runFullscreenStress`）。`NSWindowDelegate` の `windowDidEnterFullScreen` / `windowDidExitFullScreen` を `CheckedContinuation` でブリッジし、人間より高速（4 Hz）に enter/exit を N 回連打、各サイクルで保存フレームとの誤差を計測する。

```
PEEKIX_FS_STRESS=30 PEEKIX_RTSP_URL="rtsp://127.0.0.1:1/none" \
    ./build/Peekix.app/Contents/MacOS/Peekix
```

## クラッシュ・スタックトレース（修正前、再現済み）
`~/Library/Logs/DiagnosticReports/Peekix-2026-04-26-010906.ips` ほか。

```
EXC_BREAKPOINT (SIGTRAP, brk 1)
PC = 0x1855144c4 (AppKit, NSRegion 内部の精度アサート)
__kCGRegionEmptyRegion / OBJC_CLASS_$_NSRegion
└─ -[NSWindow _adjustNeedsDisplayRegionForNewFrame:]
   └─ -[NSWindow _setFrameCommon:display:fromServer:]
      └─ -[_NSExitFullScreenTransitionController setupWindowForAfterFullScreenExit] (block)
         └─ NSPerformVisuallyAtomicChange
            └─ -[_NSExitFullScreenTransitionController setupWindowForAfterFullScreenExit]
               └─ -[NSWindow _performHoldingResizeSnapshots:completionHandler:]
                  └─ -[_NSExitFullScreenTransitionController start]
                     └─ AppKitWindow.exitFullScreenMode(_:)
                        └─ PlaybackViewModel.setMode(.normal)
                           └─ PlaybackViewModel.runFullscreenStress closure
```

クラッシュは exit 1 サイクル目で確実に発生。`brk 1` は NSRegion の整合性チェック（おそらく empty/non-empty 不変条件）が失敗したことを示す。

## 真の原因
`NSWindowDelegate.windowWillEnterFullScreen` / `windowWillExitFullScreen` の中で `window.contentAspectRatio = .zero` を設定していたこと。

これらの "will-transition" コールバックは、AppKit が次フェーズの内部ジオメトリ（ウィンドウサイズ、ディスプレイ region）を確定するまさに途中で呼ばれる。そこでアスペクト比制約を変更すると、`_NSExitFullScreenTransitionController` が直後に算出する post-exit フレームの NSRegion 計算が破綻し、`_adjustNeedsDisplayRegionForNewFrame:` 内のアサートで `brk 1` する。

これは "willEnter/willExit では prepare のみ可、ジオメトリ・mutate 不可" という Apple の暗黙ルールに違反していた。`didEnter` / `didExit` まで待って初めて窓を mutate できる。

### 副次的な改善点（必要だが crash の主因ではないもの）
- **VideoView の layer-hosting 順序**: 旧コードは `wantsLayer = true` を `self.layer = layer` より先に呼んでおり、layer-backed view（AppKit 所有）として扱われていた。`self.layer = layer` を先に行う正しい順序に修正。フルスクリーン遷移中の view 再ペアレントで CAMetalLayer がツリーから外れないようにするため。
- **CAMetalLayer の二段ホスト**: VideoView の primary layer は plain `CALayer`、その上に `CAMetalLayer` を sublayer として配置（MTKView と同じパターン）。AppKit の region 計算が CAMetalLayer の特殊性に晒されないようにする防御策。
- **`isOpaque = true` / `wantsUpdateLayer = true` / `updateLayer()` no-op**: AppKit に「このサブツリーは自分で描く」と伝え、display-region 走査の対象から外す。
- **遷移中ジオメトリ操作の no-op 化**: `applyWindowAspect` / `windowWillResize` / `setMode` を `isTransitioning` / `isRestoringFrame` ガードで完全停止。
- **遷移再入の抑止**: `toggleFullscreen()` / `setMode(_:)` 先頭で `isTransitioning` を見て早期 return。
- **保存フレームの忠実復元**: `windowDidExitFullScreen` で `isRestoringFrame = true` の下に `setFrame(savedFullscreenFrame)`、その間 `windowWillResize` は素通し。
- **renderer の再アタッチ**: `attach(videoView:)` 再呼出し時、既存 renderer を新しい `metalLayer` に再バインド。

## 修正後のコード（要点）
```swift
func windowWillEnterFullScreen(_ notification: Notification) {
    isTransitioning = true
    if savedFullscreenFrame == nil, let w = window {
        savedFullscreenFrame = w.frame
    }
    // ⚠️ 何も mutate しない: AppKit が region を確定中。
    // ここで contentAspectRatio などを触ると brk 1 で落ちる。
}

func windowWillExitFullScreen(_ notification: Notification) {
    isTransitioning = true
    // ⚠️ 同上。何もしない。
}

func windowDidExitFullScreen(_ notification: Notification) {
    isTransitioning = false
    if let frame = savedFullscreenFrame, let w = window {
        isRestoringFrame = true
        w.setFrame(frame, display: true, animate: false)
        isRestoringFrame = false
    }
    savedFullscreenFrame = nil
    windowMode = .normal
    applyAlwaysOnTop()
    applyWindowAspect()
}
```

## 検証結果（実機）
2026-04-26 01:21、Apple Silicon MacBook Pro（macOS 26.2）にて。

```
$ PEEKIX_FS_STRESS=30 PEEKIX_RTSP_URL="rtsp://127.0.0.1:1/none" \
    ./build/Peekix.app/Contents/MacOS/Peekix \
    > /tmp/peekix_stdout.log 2> /tmp/peekix_stderr.log

$ echo "exit=$?"
exit=0

$ grep "FS_STRESS" /tmp/peekix_stderr.log | head -3
[FS_STRESS] task entered
[FS_STRESS] start cycles=30 frame={{62, 75}, {777, 513}}
[FS_STRESS] cycle=1/30 frame={{62, 75}, {777, 513}} drift=0.0

$ grep "FS_STRESS" /tmp/peekix_stderr.log | tail -3
[FS_STRESS] cycle=29/30 frame={{62, 75}, {777, 513}} drift=0.0
[FS_STRESS] cycle=30/30 frame={{62, 75}, {777, 513}} drift=0.0
[FS_STRESS] PASS cycles=30 max_drift=0.0

$ grep -c "cycle=" /tmp/peekix_stderr.log
30
```

並走させた `log stream --process Peekix --level error` で記録された **エラーレベル以上のログは 1 件のみ**:

```
2026-04-26 01:21:37.977062 Error  Peekix: [app.peekix.mac:PlaybackEngine]
                          avformat_open_input failed (-61)
```

これは `127.0.0.1:1` への RTSP 接続拒否（テスト用 dummy URL によるもの）であり、フルスクリーン遷移とは無関係。

新規クラッシュレポート（`~/Library/Logs/DiagnosticReports/Peekix-*.ips`）は **0 件**（最新は修正前の 01:17:38）。

### 達成した要件
- フルスクリーン⇄通常 30 回連続切替でクラッシュ 0
- 復帰サイズ・位置のドリフト 0 px（30 回中 30 回で `{{62, 75}, {777, 513}}` を完全復元）
- エラーログなし（FFmpeg の dummy URL 接続失敗を除く）
- 強制アンラップ・暗黙 self キャプチャ無し、`@MainActor` 維持

## ハーネスの再利用
`PEEKIX_FS_STRESS=N` で N 回ストレスを実行できる。回帰テストとして CI / 手動検証で利用可能。再生中の RTSP 接続有無に関わらず動作する（接続失敗は無視）。

## 対象ファイル
- `Packages/PeekixUI/Sources/PeekixUI/VideoView.swift`
- `App/Peekix/PlaybackViewModel.swift`
