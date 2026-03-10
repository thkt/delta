# delta

[English](README.md)

Claude Codeプラグイン。コンテキストウィンドウのcompaction前にDelta（計画と実装の差分）を生成し、セッション間で失われるコンテキストを保存します。

## 課題

Claude Codeで長いセッションを続けていると、コンテキストウィンドウが埋まってauto-compactが発動する。このとき、SOW/Specに書かれていない発見・設計変更・判断が失われる。

```text
セッション開始 → 調査 → 実装 → 発見・判断が蓄積 → auto-compact → 全部消える
```

deltaはこの「消える」直前に、計画との差分を記録するプラグインです。

## Delta とは

Deltaは計画（SOW/Spec）と実際の実装の間に生じた差分を記録するファイルです。

- **Discoveries** - 実装中に発見した問題や制約
- **Design Changes** - SOW/Specからの変更とその理由
- **Decisions** - 計画に記録されていない、議論中に下した判断
- **Pending** - 未完了のタスクと次のアクション

## 仕組み

```mermaid
flowchart TD
    subgraph main [" "]
        A["context-monitor<br>(PostToolUse)"] -->|"≤35%: 提案<br>≤25%: 即時要求"| B["/delta<br>(Skill)"]
        B --> C["/compact<br>(手動実行)"]
    end

    B --> D[("delta-SESSION_ID.md")]
    E["session-start-compact<br>(SessionStart)"] -.->|"auto-compact<br>フォールバック"| D

    style main fill:none,stroke:none
```

1. **context-monitor**（PostToolUse hook）がブリッジファイル経由でコンテキスト残量を監視
   - **WARNING**（残量35% 以下）: `/delta` の実行を提案
   - **CRITICAL**（残量25% 以下）: `/delta` の即時実行を要求
   - 5回のツール呼び出しごとにデバウンス
2. **`/delta` スキル**が現在のセッションコンテキストからDeltaファイルを生成
3. **session-start-compact**（SessionStart hook）がauto-compactを検知し、トランスクリプトからDeltaを自動生成するフォールバック

## インストール

```bash
claude plugin add thkt/delta
```

## プラグイン構成

```text
.claude-plugin/
  plugin.json          # プラグインメタデータ（名前、バージョン、説明）
  marketplace.json     # プラグインレジストリ登録
hooks/
  hooks.json           # hook 登録（PostToolUse + SessionStart）
  context-monitor.sh   # コンテキストウィンドウ残量監視
  session-start-compact.sh  # auto-compact フォールバック Delta 生成
skills/
  delta/
    SKILL.md           # /delta スキル定義
tests/
  test-helpers.sh      # テストユーティリティ（assert_eq, assert_contains 等）
  test-context-monitor.sh        # 16 テスト
  test-session-start-compact.sh  # 13 テスト
```

## 設定

### context-monitor の閾値

`hooks/context-monitor.sh` を編集して調整できます。

| 変数                 | デフォルト | 説明                              |
| -------------------- | ---------- | --------------------------------- |
| `WARNING_THRESHOLD`  | 35         | 警告を出す残量 %                  |
| `CRITICAL_THRESHOLD` | 25         | 緊急警告を出す残量 %              |
| `STALE_SECONDS`      | 60         | ブリッジファイルの有効期限（秒）  |
| `DEBOUNCE_CALLS`     | 5          | 警告間の PostToolUse 呼び出し回数 |

### ブリッジファイル

context-monitorは `$TMPDIR/claude-ctx-{session_id}.json` を読み取ります。このファイルはstatusline hook（本プラグインには含まれません）が書き込みます。

```json
{ "remaining_pct": 42, "ts": 1710000000 }
```

## 依存関係

- **zsh** - hookスクリプトがzshを使用
- **jq** - JSON出力に必要（context-monitorは警告パスのみ、session-start-compactは常時）

## テスト実行

```bash
zsh tests/test-context-monitor.sh
zsh tests/test-session-start-compact.sh
```

## ライセンス

MIT
