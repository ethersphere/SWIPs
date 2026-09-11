#!/bin/sh
# Provision ground-truth sources for an adversarial SWIP review.
#
# Clones the Swarm client and the incentives contracts into a scratch directory at
# the CURRENT TIP OF TRUNK, so the review reasons about what is on master today --
# not a stale local checkout, not one of several, and never the user's own working
# tree (which may be dirty or mid-rebase).
#
# Shallow and single-branch: tip commit of the remote's default branch only, no
# history, no other branches. That is all a review needs and it clones in seconds.
#
# Usage:   sh fetch-sources.sh <scratch-dir>
# Cleanup: sh fetch-sources.sh --clean <scratch-dir>
# Output:  one line per repo: <name>\t<path>\t<branch>\t<sha>\t<committed date>

set -e

if [ "$1" = "--clean" ]; then
  [ -n "$2" ] || { echo "usage: $0 --clean <scratch-dir>" >&2; exit 2; }
  # Takes the same <scratch-dir> as the fetch path; the suffix is appended here so
  # a caller can never point --clean at a directory it did not create.
  case "$2" in
    */swip-review-sources) target="$2" ;;
    *) target="$2/swip-review-sources" ;;
  esac
  [ -d "$target" ] || { echo "nothing to clean at $target"; exit 0; }
  rm -rf "$target"
  echo "removed $target"
  exit 0
fi

[ -n "$1" ] || { echo "usage: $0 <scratch-dir>" >&2; exit 2; }
dir="$1/swip-review-sources"
mkdir -p "$dir"

for repo in bee storage-incentives; do
  target="$dir/$repo"
  if [ ! -d "$target/.git" ]; then
    git clone --depth 1 --single-branch --quiet \
      "https://github.com/ethersphere/$repo.git" "$target" >&2 || {
        echo "FAILED to clone $repo -- review cannot be grounded against it" >&2
        continue
      }
  fi
  branch=$(git -C "$target" rev-parse --abbrev-ref HEAD)
  sha=$(git -C "$target" rev-parse --short HEAD)
  date=$(git -C "$target" log -1 --format=%cd --date=short)
  printf '%s\t%s\t%s\t%s\t%s\n' "$repo" "$target" "$branch" "$sha" "$date"
done
