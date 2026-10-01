#!/usr/bin/env bash
# Pulls the latest hmm-kit into Packages/HmmKit (git subtree, squashed). hmm-kit is never edited here: change it in
# its own repository first, then run this.
#
#   Tools/sync-hmmkit.sh            # main
#   Tools/sync-hmmkit.sh v0.2.0     # a tag or branch
set -euo pipefail
REF="${1:-main}"
REMOTE="${HMMKIT_REMOTE:-https://github.com/AhmedHeshamEG/hmm-kit.git}"
cd "$(git rev-parse --show-toplevel)"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Commit or stash your changes first." >&2
  exit 1
fi
git subtree pull --prefix=Packages/HmmKit "$REMOTE" "$REF" --squash -m "chore: sync hmm-kit ($REF)"
