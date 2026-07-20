#!/usr/bin/env bash

# <#
# .SYNOPSIS
#     Upgrades GitHub Actions 'uses:' references to the SHA of their latest release.
# .DESCRIPTION
#     For each action found in .github/workflows/*.yml:
#       1. Looks up the latest release tag via the GitHub API
#       2. Resolves that tag to a full commit SHA
#       3. Rewrites in-place as:  owner/repo@<sha>  # v<latest>
#     Already-pinned SHAs are re-evaluated against the latest release and
#     updated if a newer version is available.
#     Local './' actions are always skipped.
# .PARAMETER WorkflowDir
#     Path to the workflows folder. Default: .github/workflows
# .PARAMETER Token
#     GitHub PAT. Defaults to $env:GITHUB_TOKEN if not supplied.
# .PARAMETER WhatIf
#     Dry-run — prints changes without writing any files.
# .EXAMPLE
#     .\pin-actions-latest.ps1 -WhatIf
#     .\pin-actions-latest.ps1
#     .\pin-actions-latest.ps1 -Token ghp_xxxx
# #>

set -euo pipefail

# Argument Parsing
WORKFLOW_DIR=".github/workflows"
TOKEN="${GITHUB_TOKEN:-}"
WHAT_IF=false

usage() {
    echo "Usage: $0 [--workflow-dir <dir>] [--token <token>] [--what-if]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workflow-dir)
            WORKFLOW_DIR="$2"
            shift 2
            ;;
        --token)
            TOKEN="$2"
            shift 2
            ;;
        --what-if)
            WHAT_IF=true
            shift
            ;;
        *)
            usage
            ;;
    esac
done

if [[ -z "$TOKEN" ]]; then
    echo "::warning::No GitHub token found. Set \$GITHUB_TOKEN or pass --token." >&2
fi

# Shared API Curl Helper
gh_curl() {
    local url="$1"
    if [[ -n "$TOKEN" ]]; then
        curl -sH "User-Agent: pin-actions-latest-sh" -H "Authorization: Bearer $TOKEN" "$url"
    else
        curl -sH "User-Agent: pin-actions-latest-sh" "$url"
    fi
}

# In-memory Caches (Associative Arrays)
declare -A LATEST_TAG_CACHE
declare -A SHA_CACHE

get_latest_tag() {
    local action="$1"
    if [[ -n "${LATEST_TAG_CACHE[$action]:-}" ]]; then
        echo "${LATEST_TAG_CACHE[$action]}"
        return 0
    fi

    # Try releases/latest first (most actions use proper releases)
    local res
    res=$(gh_curl "https://api.github.com/repos/$action/releases/latest")
    local tag
    tag=$(echo "$res" | jq -r '.tag_name // empty' 2>/dev/null || true)

    if [[ -n "$tag" && "$tag" != "null" ]]; then
        LATEST_TAG_CACHE["$action"]="$tag"
        echo "$tag"
        return 0
    fi

    # Fall back to tags list (some actions only publish tags, not releases)
    res=$(gh_curl "https://api.github.com/repos/$action/tags?per_page=1")
    tag=$(echo "$res" | jq -r '.[0].name // empty' 2>/dev/null || true)

    if [[ -n "$tag" && "$tag" != "null" ]]; then
        LATEST_TAG_CACHE["$action"]="$tag"
        echo "$tag"
        return 0
    fi

    echo "::warning::  Could not find any release or tag for $action — skipping." >&2
    return 1
}

get_commit_sha() {
    local action="$1"
    local ref="$2"
    local key="${action}@${ref}"

    if [[ -n "${SHA_CACHE[$key]:-}" ]]; then
        echo "${SHA_CACHE[$key]}"
        return 0
    fi

    # /commits/{ref} resolves branch names, tags, and tag objects uniformly
    local res
    res=$(gh_curl "https://api.github.com/repos/$action/commits/$ref")
    local sha
    sha=$(echo "$res" | jq -r '.sha // empty' 2>/dev/null || true)

    if [[ -n "$sha" && "$sha" != "null" ]]; then
        SHA_CACHE["$key"]="$sha"
        echo "$sha"
        return 0
    else
        echo "::warning::  Could not resolve SHA for $action@$ref — skipping." >&2
        return 1
    fi
}

# Process YML files
shopt -s nullglob
files=("$WORKFLOW_DIR"/*.yml)

if [[ ${#files[@]} -eq 0 ]]; then
    echo "No .yml files found in $WORKFLOW_DIR"
    exit 0
fi

for file in "${files[@]}"; do
    tmp_file=$(mktemp)
    file_changed=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Regex to capture uses: pattern
        if [[ "$line" =~ ^([[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*)([^@[:space:]]+)@([^[:space:]#]+)([[:space:]]*#.*)?$ ]]; then
            prefix="${BASH_REMATCH[1]}"
            action="${BASH_REMATCH[3]}"
            current_ref="${BASH_REMATCH[4]}"

            # Skip local reusable workflows
            if [[ "$action" == ./* ]]; then
                echo "$line" >> "$tmp_file"
                continue
            fi

            # Split owner/repo from any subpath (e.g. github/codeql-action/upload-sarif)
            IFS='/' read -r -a parts <<< "$action"
            repo="${parts[0]}/${parts[1]}"

            latest_tag=$(get_latest_tag "$repo" || true)
            if [[ -z "$latest_tag" ]]; then
                echo "$line" >> "$tmp_file"
                continue
            fi

            sha=$(get_commit_sha "$repo" "$latest_tag" || true)
            if [[ -z "$sha" ]]; then
                echo "$line" >> "$tmp_file"
                continue
            fi

            new_line="${prefix}${action}@${sha}  # ${latest_tag}"

            if [[ "$new_line" != "$line" ]]; then
                short_sha="${sha:0:12}..."
                printf "  %-45s %s -> %s  (%s)\n" "$action" "$current_ref" "$latest_tag" "$short_sha"
                file_changed=true
            fi
            echo "$new_line" >> "$tmp_file"
        else
            echo "$line" >> "$tmp_file"
        fi
    done < "$file"

    if [[ "$file_changed" == true ]]; then
        echo -e "\033[36m[$(basename "$file")]\033[0m"
        if [[ "$WHAT_IF" == false ]]; then
            mv "$tmp_file" "$file"
        else
            rm -f "$tmp_file"
        fi
    else
        rm -f "$tmp_file"
    fi
done

if [[ "$WHAT_IF" == true ]]; then
    echo -e "\n\033[33m[WhatIf] No files were written.\033[0m"
else
    echo -e "\n\033[32mDone.\033[0m"
fi