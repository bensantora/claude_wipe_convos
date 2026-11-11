#!/usr/bin/env bash
# Delete Claude Code conversation data only. Never touches .credentials.json,
# settings.json, plugins/, skills/ or ~/.claude.json.
# Per-project memory/ directories under projects/ are preserved.
set -euo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

[ -d "$CFG" ] || { echo "Config dir not found: $CFG" >&2; exit 1; }
CFG="$(cd "$CFG" && pwd -P)"

# Refuse to run while claude is active
if pgrep -x claude >/dev/null || pgrep -f '@anthropic-ai/claude-code' | grep -qvx "$$"; then
    echo "Refusing to run: a claude process is active:" >&2
    pgrep -a -x claude >&2 || true
    echo "Exit all Claude Code sessions and try again." >&2
    exit 1
fi

# Build the list of targets (null-delimited)
targets=()

# projects/: everything inside each project dir except memory/
if [ -d "$CFG/projects" ]; then
    while IFS= read -r -d '' p; do
        targets+=("$p")
    done < <(find "$CFG/projects" -mindepth 2 -maxdepth 2 ! -name memory -print0)
fi

# history.jsonl (file) and the other conversation dirs (contents only)
[ -e "$CFG/history.jsonl" ] && targets+=("$CFG/history.jsonl")
for d in file-history shell-snapshots session-env sessions; do
    if [ -d "$CFG/$d" ]; then
        while IFS= read -r -d '' p; do
            targets+=("$p")
        done < <(find "$CFG/$d" -mindepth 1 -maxdepth 1 -print0)
    fi
done

if [ "${#targets[@]}" -eq 0 ]; then
    echo "Nothing to delete in $CFG."
    exit 0
fi

echo "Config dir: $CFG"
echo "The following will be PERMANENTLY deleted:"
echo
du -shc -- "${targets[@]}" 2>/dev/null | sed 's/^/  /'
echo
echo "Preserved: .credentials.json, settings.json, plugins/, skills/, projects/*/memory/, $HOME/.claude.json"
echo
read -r -p "Type 'yes' to delete: " ans
[ "$ans" = "yes" ] || { echo "Aborted."; exit 1; }

# Re-check right before deleting
if pgrep -x claude >/dev/null; then
    echo "A claude process started meanwhile. Aborting." >&2
    exit 1
fi

for t in "${targets[@]}"; do
    case "$t" in
        "$CFG"/projects/*|"$CFG"/history.jsonl|"$CFG"/file-history/*|"$CFG"/shell-snapshots/*|"$CFG"/session-env/*|"$CFG"/sessions/*)
            rm -rf -- "$t" ;;
        *)
            echo "Skipping unexpected path: $t" >&2 ;;
    esac
done

echo "Done."
