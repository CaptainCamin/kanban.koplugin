#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="$SCRIPT_DIR/kanban.koplugin.zip"

if ! command -v zip >/dev/null 2>&1; then
    printf '%s\n' 'Error: the zip command is required to package the plugin.' >&2
    exit 1
fi

cd "$SCRIPT_DIR"
rm -f "$ARCHIVE"

zip -r -X "$ARCHIVE" kanban.koplugin -x \
    '*/.DS_Store' \
    '*/._*' \
    '*/Thumbs.db' \
    '*/desktop.ini' \
    '*/.git/*' \
    '*/.svn/*' \
    '*/.hg/*' \
    '*/.idea/*' \
    '*/.vscode/*' \
    '*/.history/*' \
    '*~' \
    '*.swp' \
    '*.swo'
