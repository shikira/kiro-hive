#!/bin/bash
# =============================================================================
# setup-repos.sh (kiro-hive)
# GitHub Issueを取得し、issue数分のリポジトリクローン＆ブランチを作成する
#
# Usage: bash scripts/setup-repos.sh [config_file]
# 前提: gh auth login 済みであること
# =============================================================================

set -euo pipefail

CONFIG_FILE="${1:-config.yaml}"
REPOS_DIR="./repos"

# --- config.yaml のパース ---

get_config() {
  local key="$1"
  grep "^  ${key}:" "$CONFIG_FILE" 2>/dev/null | sed 's/.*: *"\(.*\)"/\1/' | sed "s/.*: *'\(.*\)'/\1/" | sed 's/.*: *//'
}

REPO_URL=$(get_config "url")
OWNER_REPO=$(get_config "owner_repo")
DEFAULT_BRANCH=$(get_config "default_branch")
BRANCH_PREFIX=$(get_config "prefix")
LABELS=$(get_config "labels")
STATE=$(get_config "state")
MILESTONE=$(get_config "milestone")
LIMIT=$(get_config "limit")

if [ -z "$REPO_URL" ] || [ -z "$OWNER_REPO" ]; then
  echo "ERROR: repository.url と repository.owner_repo を config.yaml に設定してください"
  exit 1
fi

DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
BRANCH_PREFIX="${BRANCH_PREFIX:-feature/issue}"
STATE="${STATE:-open}"
LIMIT="${LIMIT:-10}"

# --- gh 認証チェック ---

if ! gh auth status &>/dev/null; then
  echo "ERROR: gh auth login を先に実行してください"
  exit 1
fi

echo "=== kiro-hive: リポジトリセットアップ ==="
echo "リポジトリ: $OWNER_REPO"
echo "デフォルトブランチ: $DEFAULT_BRANCH"
echo ""

# --- GitHub Issueの取得 ---

echo "GitHub Issueを取得中..."

GH_ARGS="--repo $OWNER_REPO --state $STATE --limit $LIMIT --json number,title,body,labels"

if [ -n "$LABELS" ]; then
  GH_ARGS="$GH_ARGS --label $LABELS"
fi

if [ -n "$MILESTONE" ]; then
  GH_ARGS="$GH_ARGS --milestone $MILESTONE"
fi

ISSUES_JSON=$(gh issue list $GH_ARGS)
ISSUE_COUNT=$(echo "$ISSUES_JSON" | jq length)

if [ "$ISSUE_COUNT" -eq 0 ]; then
  echo "ERROR: 対象のGitHub Issueが見つかりません"
  echo "  フィルタ条件: state=$STATE, labels=$LABELS, milestone=$MILESTONE"
  exit 1
fi

echo "検出されたissue数: $ISSUE_COUNT"
echo ""

# --- reposディレクトリの準備 ---

mkdir -p "$REPOS_DIR"

# --- 各issueに対してクローン＆ブランチ作成 ---

for i in $(seq 0 $((ISSUE_COUNT - 1))); do
  ISSUE_NUMBER=$(echo "$ISSUES_JSON" | jq -r ".[$i].number")
  ISSUE_TITLE=$(echo "$ISSUES_JSON" | jq -r ".[$i].title")
  ISSUE_BODY=$(echo "$ISSUES_JSON" | jq -r ".[$i].body")

  CLONE_NUM=$((i + 1))
  CLONE_DIR="${REPOS_DIR}/repo-clone-${CLONE_NUM}"

  # ブランチ名用にタイトルを正規化
  BRANCH_SLUG=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-40)
  BRANCH_NAME="${BRANCH_PREFIX}-${ISSUE_NUMBER}-${BRANCH_SLUG}"

  echo "--- Issue ${CLONE_NUM}/${ISSUE_COUNT} (#${ISSUE_NUMBER}) ---"
  echo "  タイトル: $ISSUE_TITLE"
  echo "  クローン先: $CLONE_DIR"
  echo "  ブランチ: $BRANCH_NAME"

  if [ -d "$CLONE_DIR" ]; then
    echo "  既存のクローンを検出。最新化します..."
    cd "$CLONE_DIR"
    git fetch origin
    git checkout "$DEFAULT_BRANCH"
    git pull origin "$DEFAULT_BRANCH"
    git checkout -B "$BRANCH_NAME"
    cd - > /dev/null
  else
    echo "  クローン中..."
    git clone "$REPO_URL" "$CLONE_DIR"
    cd "$CLONE_DIR"
    git checkout -b "$BRANCH_NAME"
    cd - > /dev/null
  fi

  # issueの内容をクローン内に保存（ワーカーが参照できるように）
  mkdir -p "${CLONE_DIR}/docs"
  cat > "${CLONE_DIR}/docs/issue.md" <<EOF
# Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

${ISSUE_BODY}
EOF

  echo "  完了"
  echo ""
done

echo "=== セットアップ完了 ==="
echo ""

# --- サマリー出力 ---

echo "=== クローン一覧 ==="
for i in $(seq 0 $((ISSUE_COUNT - 1))); do
  CLONE_NUM=$((i + 1))
  CLONE_DIR="${REPOS_DIR}/repo-clone-${CLONE_NUM}"
  ISSUE_NUMBER=$(echo "$ISSUES_JSON" | jq -r ".[$i].number")
  ISSUE_TITLE=$(echo "$ISSUES_JSON" | jq -r ".[$i].title")
  if [ -d "$CLONE_DIR" ]; then
    CURRENT_BRANCH=$(cd "$CLONE_DIR" && git branch --show-current)
    echo "  [${CLONE_NUM}] #${ISSUE_NUMBER} ${ISSUE_TITLE}"
    echo "       ${CLONE_DIR} -> branch: ${CURRENT_BRANCH}"
  fi
done
