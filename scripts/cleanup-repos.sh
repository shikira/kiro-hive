#!/bin/bash
# =============================================================================
# cleanup-repos.sh
# クローンしたリポジトリを削除する
#
# Usage: bash scripts/cleanup-repos.sh [--force]
# =============================================================================

set -euo pipefail

REPOS_DIR="./repos"

if [ ! -d "$REPOS_DIR" ]; then
  echo "repos ディレクトリが見つかりません。"
  exit 0
fi

CLONE_DIRS=($(find "$REPOS_DIR" -maxdepth 1 -name "repo-clone-*" -type d | sort))

if [ ${#CLONE_DIRS[@]} -eq 0 ]; then
  echo "クリーンアップ対象のクローンがありません。"
  exit 0
fi

echo "=== クリーンアップ対象 ==="
for dir in "${CLONE_DIRS[@]}"; do
  if [ -d "$dir/.git" ]; then
    BRANCH=$(cd "$dir" && git branch --show-current)
    STATUS=$(cd "$dir" && git status --porcelain | wc -l | tr -d ' ')
    echo "  $dir (branch: $BRANCH, uncommitted: $STATUS files)"
  else
    echo "  $dir (not a git repo)"
  fi
done
echo ""

if [ "${1:-}" != "--force" ]; then
  read -p "削除しますか？ (y/N): " CONFIRM
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "キャンセルしました。"
    exit 0
  fi
fi

for dir in "${CLONE_DIRS[@]}"; do
  echo "削除中: $dir"
  rm -rf "$dir"
done

echo ""
echo "=== クリーンアップ完了 ==="
