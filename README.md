# kiro-hive

GitHub Issueを投げ込むと、複数のAIエージェントが蜂のように並列で開発を回し、それぞれPRとして成果物を持ち帰るフレームワークです。Kiro CLIのカスタムエージェント＋サブエージェント機能で動作します。

## アーキテクチャ

```
ユーザ
  ↕
マネージャエージェント（全体統括・ユーザ問い合わせ集約）
  ├── サブマネージャエージェント（Issue #42 担当）
  │     ├── ワーカーエージェント（ドキュメント作成）
  │     └── ワーカーエージェント（実装・テスト）
  ├── サブマネージャエージェント（Issue #43 担当）
  │     ├── ワーカーエージェント
  │     └── ワーカーエージェント
  └── ...
```

各issueは独立したリポジトリクローン上で作業するため、Git操作が競合しません。

```
project-root/
├── .kiro/agents/          # エージェント設定
│   ├── manager.json       # マネージャ
│   ├── sub-manager.json   # サブマネージャ
│   └── worker.json        # ワーカー
├── prompts/               # 各エージェントのシステムプロンプト
│   ├── manager-prompt.md
│   ├── sub-manager-prompt.md
│   └── worker-prompt.md
├── repos/                 # 同一リポジトリの複数クローン（自動生成）
│   ├── repo-clone-1/      # Issue #42 用
│   ├── repo-clone-2/      # Issue #43 用
│   └── ...
├── scripts/               # ユーティリティスクリプト
│   ├── setup-repos.sh     # GitHub Issue取得＆クローン＆ブランチ作成
│   ├── add-issue.sh       # issue追加
│   └── cleanup-repos.sh   # クローン削除
└── config.yaml            # リポジトリURL・フィルタ条件等の設定
```

## 前提条件

- [Kiro CLI](https://kiro.dev/docs/cli/) がインストール済みであること
- [GitHub CLI (gh)](https://cli.github.com/) がインストール済みで `gh auth login` 済みであること
- `jq` がインストール済みであること
- Git がインストール済みであること
- 対象リポジトリへのpush権限があること

## セットアップ

### 1. config.yaml を編集

対象リポジトリの情報とissueのフィルタ条件を設定します。

```yaml
repository:
  url: "https://github.com/your-org/your-repo.git"
  owner_repo: "your-org/your-repo"    # gh cli用（owner/repo形式）
  default_branch: "main"

github_issues:
  labels: "multi-agent"    # このラベルが付いたissueを対象にする
  state: "open"
  limit: 10
```

### 2. GitHub Issueを作成

対象リポジトリにissueを作成し、`config.yaml` で指定したラベル（デフォルト: `multi-agent`）を付与します。

```bash
# issueの作成例
gh issue create --repo your-org/your-repo \
  --title "ユーザ認証機能の追加" \
  --body "## 概要\nメールアドレスとパスワードによる認証機能を追加する\n\n## 受け入れ基準\n- ログイン/ログアウトが動作すること" \
  --label "multi-agent"
```

### 3. リポジトリクローンを準備

GitHub Issueを取得し、issue数分のクローン＆ブランチを自動作成します。

```bash
bash scripts/setup-repos.sh
```

実行結果:
```
=== マルチissue駆動開発: リポジトリセットアップ ===
リポジトリ: your-org/your-repo
GitHub Issueを取得中...
検出されたissue数: 2

--- Issue 1/2 (#42) ---
  タイトル: ユーザ認証機能の追加
  クローン先: repos/repo-clone-1
  ブランチ: feature/issue-42-ユーザ認証機能の追加
  完了

--- Issue 2/2 (#43) ---
  タイトル: APIレート制限の実装
  クローン先: repos/repo-clone-2
  ブランチ: feature/issue-43-apiレート制限の実装
  完了

=== セットアップ完了 ===
```

## 使い方

### 開発を開始する

```bash
kiro-cli --agent manager
```

マネージャエージェントが起動したら、以下のように指示します:

```
GitHub Issueを取得して、並列開発を開始してください。
```

マネージャが自動的に:
1. `gh issue list` でissueを取得
2. 各issueにサブマネージャエージェントを割り当て
3. サブマネージャがワーカーエージェントを起動して開発を進める

### 開発フロー（各issue）

サブマネージャが以下のフェーズを順に進めます:

```
要件定義 → 基本仕様書 → 詳細仕様書 → タスク分割 → 実装 → テスト → コミット・PR作成
```

各フェーズの成果物は対応するクローンディレクトリの `docs/` 配下に作成されます。
PR作成時は `gh pr create` で自動的にissueとリンクされます。

### ユーザへの問い合わせ

サブマネージャやワーカーが判断できない事項は、マネージャ経由でユーザに問い合わせが来ます。
問い合わせは一つずつシーケンシャルに提示されるので、順番に回答してください。

```
[#42] 問い合わせ:
  フェーズ: 基本仕様
  質問: 認証方式はJWT以外にOAuthも対応しますか？
  選択肢: (A) JWTのみ (B) JWT + OAuth2.0
```

### 途中でissueを追加する

```bash
# issue番号を指定して新しいクローンを準備
bash scripts/add-issue.sh 44

# マネージャに追加を伝える（kiro-cliのチャットで）
# 「GitHub Issue #44 を repos/repo-clone-3 に追加しました。サブマネージャを起動してください。」
```

### 進捗を確認する

マネージャに「進捗を教えてください」と聞くと、以下の形式で報告されます:

```
=== 進捗レポート ===
[#42] ステータス: 実行中
  タイトル: ユーザ認証機能の追加
  フェーズ: 実装
  担当ディレクトリ: repos/repo-clone-1
[#43] ステータス: 完了
  タイトル: APIレート制限の実装
  フェーズ: PR作成
  担当ディレクトリ: repos/repo-clone-2
```

### クリーンアップ

開発完了後、クローンしたリポジトリを削除します。

```bash
# 確認プロンプトあり
bash scripts/cleanup-repos.sh

# 確認なしで削除
bash scripts/cleanup-repos.sh --force
```

## エージェント設定のカスタマイズ

### モデルを変更する

各エージェントの `.kiro/agents/*.json` で `model` フィールドを変更できます。

```json
{
  "model": "claude-sonnet-4"
}
```

### issueのフィルタ条件を変更する

`config.yaml` の `github_issues` セクションで調整できます。

```yaml
github_issues:
  labels: "multi-agent,sprint-1"   # 複数ラベルでAND条件
  state: "open"                     # open / closed / all
  milestone: "v2.0"                 # マイルストーンでフィルタ
  limit: 20                         # 最大取得数
```

### ツール権限を調整する

`allowedTools` でエージェントが承認なしに使えるツールを制御できます。
セキュリティを強化したい場合は `write` や `shell` を `allowedTools` から外してください。

### プロンプトをカスタマイズする

`prompts/` ディレクトリの各Markdownファイルを編集することで、エージェントの振る舞いを調整できます。
プロジェクト固有のコーディング規約やアーキテクチャ方針を追記すると効果的です。

## 制約事項

- サブエージェント内では `web_search`、`web_fetch`、`grep`、`glob` ツールが使えません。ファイル検索は `shell` ツール経由で `find` / `grep` コマンドを使用します。
- サブエージェントの並列実行数はKiro CLIの内部制限に依存します。
- 各クローンは独立したディレクトリなので、issue間でコードを共有する変更がある場合はマージ後に手動調整が必要です。
- `gh auth login` が完了していないと GitHub Issue の取得・PR作成ができません。

## ライセンス

MIT
