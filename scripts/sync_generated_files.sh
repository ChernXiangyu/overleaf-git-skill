#!/usr/bin/env bash
# One-way sync of build outputs into an Overleaf project, via Overleaf's git integration.
#
# The pattern: files your code generates (tables, figures, a macros file) are pushed from here and are never
# edited on Overleaf. Files your coauthors write in the Overleaf editor are only pulled, never pushed, because a
# push can destroy the comments and tracked changes attached to them.
#
# Copy this into your project, set the four variables below, and run it after your build.
#
#   SOURCE   the directory your build writes into
#   CLONE    a clone of the Overleaf project, OUTSIDE any cloud-synced folder (Dropbox/iCloud/OneDrive)
#   PUSH     files and directories to send to Overleaf (they are mirrored, so deletions propagate)
#   PULL     files written on Overleaf; copied back into SOURCE as a backup and never pushed
#
# PULL files are never pushed, not even once, so put the first version of a prose file into the project by hand
# (Overleaf's upload button, or a single deliberate `git add <file> && git push`) before running this.
# Every PUSH entry must exist in SOURCE; the script stops rather than pushing a half-built set of outputs.
#
# First-time setup (the user types the token so it is never seen by anyone else):
#   git clone https://git.overleaf.com/<project-id> "$CLONE"
#   git -C "$CLONE" config core.fileMode false     # Overleaf does not preserve the execute bit
set -euo pipefail

SOURCE="${SOURCE:-$(cd "$(dirname "$0")/.." && pwd)/report}"
CLONE="${CLONE:-$HOME/.cache/overleaf/my-paper}"
PUSH=(tables figures numbers.tex references.bib)
PULL=(paper.tex)

cd "$CLONE"
git pull --ff-only origin main            # stops here if the clone and Overleaf have diverged

for f in "${PULL[@]}"; do                 # Overleaf owns these: back them up, never push them
    [ -f "$f" ] && cp "$f" "$SOURCE/$f"
done

for f in "${PUSH[@]}"; do
    [ -e "$SOURCE/$f" ] || { echo "missing: $SOURCE/$f -- run the build first; nothing was pushed" >&2; exit 1; }
    if [ -d "$SOURCE/$f" ]; then
        mkdir -p "$f"
        rsync -a --delete --exclude '.*' "$SOURCE/$f/" "$f/"
    else
        cp "$SOURCE/$f" .
    fi
done

git add -A "${PUSH[@]}"
if git diff --cached --quiet; then
    echo "Overleaf is already up to date."
    exit 0
fi
git commit -q -m "sync generated files $(date +%F)"

# While a coauthor is typing, Overleaf commits their keystrokes ahead of us and the push is rejected. Our commit
# touches only generated files, so rebasing it onto their prose cannot conflict: retry a few times.
for i in 1 2 3 4 5; do
    if git push -q origin main 2>/dev/null; then
        echo "pushed (try $i)"
        for f in "${PULL[@]}"; do [ -f "$f" ] && cp "$f" "$SOURCE/$f"; done   # refresh after any rebase
        exit 0
    fi
    [ "$i" = 5 ] && { echo "push rejected 5 times; someone is editing on Overleaf, try again later" >&2; exit 1; }
    sleep 5
    git pull -q --rebase origin main
done
