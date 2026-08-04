#!/usr/bin/env bash
#
# pin-actions-latest.sh
#
# Upgrades GitHub Actions 'uses:' references to the SHA of their latest release.
#
# For each action found in .github/workflows/*.yml:
#   1. Looks up the latest release tag via the GitHub API (cached with a 24h TTL)
#   2. Resolves that tag to a full commit SHA
#   3. Rewrites in-place as:  owner/repo@<sha>  # v<latest>
#
# Usage:
#   ./pin-actions-latest.sh [-d WORKFLOW_DIR] [-t TOKEN] [-n] [-f]
#
#   -d WORKFLOW_DIR   Path to the workflows folder. Default: .github/workflows
#   -t TOKEN          GitHub PAT. Defaults to $GITHUB_TOKEN if not supplied.
#   -n                Dry-run (WhatIf) - prints changes without writing any files.
#   -f                ForceRefresh - bypass the cache and always fetch the latest tag.
#   -h                Show this help.
#
# Requires: bash 4+, curl, jq

set -euo pipefail

WORKFLOW_DIR=".github/workflows"
TOKEN="${GITHUB_TOKEN:-}"
DRY_RUN=false
FORCE_REFRESH=false

usage() {
    grep '^#' "$0" | sed -e '1d' -e 's/^# \{0,1\}//'
    exit 1
}

while getopts ":d:t:nfh" opt; do
    case "$opt" in
        d) WORKFLOW_DIR="$OPTARG" ;;
        t) TOKEN="$OPTARG" ;;
        n) DRY_RUN=true ;;
        f) FORCE_REFRESH=true ;;
        h) usage ;;
        \?) echo "Unknown option: -$OPTARG" >&2; usage ;;
        :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
    esac
done

if [[ -z "$TOKEN" ]]; then
    echo "No GitHub token found. Set the GITHUB_TOKEN environment variable or pass -t." >&2
    exit 1
fi

for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command '$cmd' not found in PATH." >&2
        exit 1
    fi
done

CACHE_FILE=".github/pin-cache.json"
CACHE_TTL_SECONDS=$((24 * 60 * 60))

# Load cache into a working file, or start with an empty object
mkdir -p "$(dirname "$CACHE_FILE")"
if [[ -f "$CACHE_FILE" ]] && jq empty "$CACHE_FILE" >/dev/null 2>&1; then
    cp "$CACHE_FILE" /tmp/pin-cache.working.json
else
    echo '{}' > /tmp/pin-cache.working.json
fi
CACHE_WORKING=/tmp/pin-cache.working.json

AUTH_HEADER="Authorization: Bearer $TOKEN"
UA_HEADER="User-Agent: pin-actions-latest-sh"

cache_get() {
    # cache_get <action> <field>
    jq -r --arg a "$1" --arg f "$2" '.[$a][$f] // empty' "$CACHE_WORKING"
}

cache_set() {
    # cache_set <action> <field> <value>
    local tmp
    tmp=$(mktemp)
    jq --arg a "$1" --arg f "$2" --arg v "$3" \
        '.[$a] = ((.[$a] // {}) + {($f): $v})' "$CACHE_WORKING" > "$tmp"
    mv "$tmp" "$CACHE_WORKING"
}

now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

seconds_since() {
    # seconds_since <iso8601 timestamp>
    local ts_epoch now_epoch
    ts_epoch=$(date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || echo 0)
    now_epoch=$(date -u +%s)
    echo $((now_epoch - ts_epoch))
}

get_latest_tag() {
    local action="$1"
    local cached_tag cached_checked age

    if [[ "$FORCE_REFRESH" == false ]]; then
        cached_tag=$(cache_get "$action" "latestTag")
        cached_checked=$(cache_get "$action" "lastChecked")
        if [[ -n "$cached_tag" && -n "$cached_checked" ]]; then
            age=$(seconds_since "$cached_checked")
            if (( age < CACHE_TTL_SECONDS )); then
                echo "$cached_tag"
                return 0
            fi
        fi
    fi

    local resp tag
    resp=$(curl -sf -H "$AUTH_HEADER" -H "$UA_HEADER" \
        "https://api.github.com/repos/$action/releases/latest" || true)
    tag=$(echo "${resp:-}" | jq -r '.tag_name // empty' 2>/dev/null || true)

    if [[ -z "$tag" ]]; then
        resp=$(curl -sf -H "$AUTH_HEADER" -H "$UA_HEADER" \
            "https://api.github.com/repos/$action/tags?per_page=1" || true)
        tag=$(echo "${resp:-}" | jq -r '.[0].name // empty' 2>/dev/null || true)
    fi

    if [[ -n "$tag" ]]; then
        cache_set "$action" "latestTag" "$tag"
        cache_set "$action" "lastChecked" "$(now_iso)"
        echo "$tag"
        return 0
    fi

    cached_tag=$(cache_get "$action" "latestTag")
    if [[ -n "$cached_tag" ]]; then
        echo "Failed to fetch latest tag for $action - using cached (possibly stale) tag." >&2
        echo "$cached_tag"
        return 0
    fi

    echo ""
    return 1
}

get_commit_sha() {
    local action="$1"
    local ref="$2"
    local cached_tag cached_sha sha resp

    cached_tag=$(cache_get "$action" "latestTag")
    cached_sha=$(cache_get "$action" "sha")
    if [[ "$cached_tag" == "$ref" && -n "$cached_sha" ]]; then
        echo "$cached_sha"
        return 0
    fi

    resp=$(curl -sf -H "$AUTH_HEADER" -H "$UA_HEADER" \
        "https://api.github.com/repos/$action/commits/$ref" || true)
    sha=$(echo "${resp:-}" | jq -r '.sha // empty' 2>/dev/null || true)

    if [[ -n "$sha" ]]; then
        cache_set "$action" "sha" "$sha"
        if [[ -z "$(cache_get "$action" "lastChecked")" ]]; then
            cache_set "$action" "lastChecked" "$(now_iso)"
        fi
        echo "$sha"
        return 0
    fi

    if [[ -n "$cached_sha" ]]; then
        echo "Failed to fetch SHA for $action@$ref - using cached SHA." >&2
        echo "$cached_sha"
        return 0
    fi

    echo ""
    return 1
}

if [[ ! -d "$WORKFLOW_DIR" ]]; then
    echo "Workflow directory not found: $WORKFLOW_DIR" >&2
    exit 1
fi

ANY_UPDATES=false

shopt -s nullglob
for file in "$WORKFLOW_DIR"/*.yml; do
    FILE_CHANGED=false
    tmpfile=$(mktemp)

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Match:  [leading ws][- ]uses: owner/repo[/path]@ref [# comment]
        if [[ "$line" =~ ^([[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_./-]+)?)@([^[:space:]#]+)([[:space:]]*#.*)?$ ]]; then
            prefix="${BASH_REMATCH[1]}"
            action="${BASH_REMATCH[3]}"
            current_ref="${BASH_REMATCH[5]}"

            if [[ "$action" == ./* ]]; then
                echo "$line" >> "$tmpfile"
                continue
            fi

            repo=$(echo "$action" | cut -d'/' -f1,2)

            latest_tag=$(get_latest_tag "$repo" || true)
            if [[ -z "$latest_tag" ]]; then
                echo "$line" >> "$tmpfile"
                continue
            fi

            sha=$(get_commit_sha "$repo" "$latest_tag" || true)
            if [[ -z "$sha" ]]; then
                echo "$line" >> "$tmpfile"
                continue
            fi

            new_line="${prefix}${action}@${sha} # ${latest_tag}"

            if [[ "$new_line" != "$line" ]]; then
                printf "[Update] %-45s %s -> %s  (%s...)\n" "$action" "$current_ref" "$latest_tag" "${sha:0:12}"
                FILE_CHANGED=true
                ANY_UPDATES=true
            fi

            echo "$new_line" >> "$tmpfile"
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "$file"

    if [[ "$FILE_CHANGED" == true && "$DRY_RUN" == false ]]; then
        mv "$tmpfile" "$file"
        echo "[File updated] $(basename "$file")"
    else
        rm -f "$tmpfile"
    fi
done

cp "$CACHE_WORKING" "$CACHE_FILE"

if [[ "$ANY_UPDATES" == false ]]; then
    echo "No updates needed."
else
    echo "Done."
fi