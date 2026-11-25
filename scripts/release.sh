#!/bin/zsh
# Cuts a release: checks the repo is ready, tags it and pushes the tag. The
# push triggers .github/workflows/release.yml, which builds Kools.zip and
# publishes the GitHub Release.
#
#   scripts/release.sh patch|minor|major   next version after the latest v* tag
#   scripts/release.sh 1.2.3               an exact version
#   scripts/release.sh patch --dry-run     run every check, change nothing
#
# With no v* tag yet, patch/minor/major count from 0.3.0 (the version in bundle.sh).
set -euo pipefail

cd "${0:A:h}/.."

usage() { echo "usage: scripts/release.sh patch|minor|major|X.Y.Z [--dry-run]" >&2; exit 2; }

[[ $# -ge 1 && $# -le 2 ]] || usage
bump="$1"
dry_run=false
if [[ ${2:-} == "--dry-run" ]]; then dry_run=true; elif [[ -n "${2:-}" ]]; then usage; fi

fail() { echo "error: $1" >&2; exit 1; }

# MARK: Repository state

[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "releases are cut from main; you are on $(git rev-parse --abbrev-ref HEAD)."
[[ -z "$(git status --porcelain)" ]] || fail "the working tree has uncommitted changes. Commit or stash them first."
git fetch --quiet origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not in sync with origin/main. Push or pull first."

# MARK: Version

latest="$(git tag --list 'v[0-9]*' --sort=-v:refname | head -1)"
base="${latest#v}"
base="${base:-0.3.0}"

case "$bump" in
    major|minor|patch)
        parts=("${(@s:.:)base}")
        major=${parts[1]} minor=${parts[2]} patch=${parts[3]}
        case "$bump" in
            major) version="$((major + 1)).0.0" ;;
            minor) version="$major.$((minor + 1)).0" ;;
            patch) version="$major.$minor.$((patch + 1))" ;;
        esac
        # With no tag yet, 0.3.0 is itself the first release.
        [[ -z "$latest" && "$bump" == "patch" ]] && version="0.3.0"
        ;;
    [0-9]*.[0-9]*.[0-9]*) version="$bump" ;;
    *) usage ;;
esac
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "'$version' is not a version like 1.2.3."
tag="v$version"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && fail "tag $tag already exists."

echo "Latest tag: ${latest:-none}"
echo "New tag:    $tag"

# MARK: Checks

echo "Running tests..."
swift test 2>&1 | tail -3

if $dry_run; then
    echo "Dry run: stopping before tagging. Nothing was changed."
    exit 0
fi

# MARK: Tag and push

git tag -a "$tag" -m "Kools $version"
git push origin "$tag"
echo "Pushed $tag. Watch the build: gh run watch  (or https://github.com/kumudithaperera/Kools/actions)"
