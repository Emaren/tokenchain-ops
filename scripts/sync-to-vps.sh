#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <local_path> <user@host:/remote/path>"
  exit 1
fi

LOCAL_PATH="$1"
REMOTE_PATH="$2"

rsync -avz --delete \
  --exclude '.git' \
  --exclude 'node_modules' \
  --exclude '.next' \
  "$LOCAL_PATH" "$REMOTE_PATH"
