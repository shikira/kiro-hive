#!/bin/bash
# =============================================================================
# add-issue.sh
# 開発途中でGitHub Issueを追加し、新しいリポジトリクローンを準備する
#
# Usage: bash scripts/add-issue.sh <issue_number>
# =============================================================================

set -euo pipefail

CONFIG_FILE="./config.yaml"
REPOS_DIR="./repos"

if [ $# -eq 0 ]; then
  echo "Usage: bash scripts/add-issue.sh <issue_number>"
  echo "  例: bash scripts/add-issue.sh 42"
  exit 1
fi

ISSUE_NUMBER="$1"

# --- config読み込み ---

get_config() {
  local key="$1"
  grep "^  ${key}:" "$CONFIG_FILE" 2>/dev/null | sed 's/.*: *"\(.*\)"/\1/' | sed "s/.*: *'\(.*\)'/\1/" | sed 's/.*: *//'
}

REPO_URL=$(get_config "url")
OWNER_REPO=$(get_config "owner_repo")
DEFAULT_BRANCH=$(get_config "default_branch")
BRANCH_PREFIX=$(get_config "prefix")

DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
BRANCH_PREFIX="${BRANCH_PREFIX:-feature/issue}"

# --- GitHub Issueの取得 ---

echo "GitHub Issue #${ISSUE_NUMBER} を取得中..."

ISSUE_JSON=$(gh issue view "$ISSUE_NUMBER" --repo "$OWNER_REPO" --json number,title,body)
ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
ISSUE_BODY=$(echo "$ISSUE_JSON" | jq -r '.body')

echo "  タイトル: $ISSUE_TITLE"

# --- 次のクローン番号を決定 ---

EXISTING_COUNT=$(find "$REPOS_DIR" -maxdepth 1 -name "repo-clone-*" -type d 2>/dev/null | wc -l | tr -d ' ')
CLONE_NUM=$((EXISTING_COUNT + 1))
CLONE_DIR="${REPOS_DIR}/repo-clone-${CLONE_NUM}"

# --- ブランチ名の生成 ---

BRANCH_SLUG=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-40)
BRANCH_NAME="${BRANCH_PREFIX}-${ISSUE_NUMBER}-${BRANCH_SLUG}"

echo "=== issue追加 ==="
echo "  Issue: #${ISSUE_NUMBER} ${ISSUE_TITLE}"
echo "  クローン先: $CLONE_DIR"
echo "  ブランチ: $BRANCH_NAME"

# --- クローン＆ブランチ作成 ---

mkdir -p "$REPOS_DIR"
git clone "$REPO_URL" "$CLONE_DIR"
cd "$CLONE_DIR"
git checkout -b "$BRANCH_NAME"
cd - > /dev/null

mkdir -p "${CLONE_DIR}/docs"
cat > "${CLONE_DIR}/docs/issue.md" <<EOF
# Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

${ISSUE_BODY}
EOF

echo ""
echo "=== 追加完了 ==="
echo "  クローン: $CLONE_DIR"
echo "  ブランチ: $BRANCH_NAME"
echo ""
echo "マネージャエージェントに以下を伝えてください:"
echo "  「GitHub Issue #${ISSUE_NUMBER} を ${CLONE_DIR} に追加しました。サブマネージャを起動してください。」"
