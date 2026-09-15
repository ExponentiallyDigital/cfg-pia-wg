#!/bin/bash
#
# pin-actions-latest.sh
#
# Pins GitHub Actions 'uses:' references to the commit SHA of their latest release, then checks every pin.
#
# For each action found in .github/workflows/*.yml (and *.yaml):
#   1. Looks up the latest release tag via the GitHub API (cached with a 24h TTL)
#   2. Resolves that tag to a full commit SHA (cached against the tag it was resolved from)
#   3. Rewrites in-place as:  owner/repo@<sha> # v<latest>
# When the API cannot answer (offline, rate limit, bad token) the tag and SHA come from `git ls-remote`,
# which needs no token. Last of all every pin is checked against the tag named in its comment, again
# with `git ls-remote`.
#
# Each action gets one status line:
#   ok          already pinned to its latest tag's commit
#   UPDATED     a newer release was pinned
#   FIXED       same version, but the pinned SHA was not that tag's commit
#   PINNED      a tag or branch reference was replaced by a SHA
#   SKIPPED     the newest tag is older than the pinned one (downgrade guard)
#   UNRESOLVED  the tag or SHA could not be looked up; the line is left as it is
#
# Exit codes:
#   0  every pin matches its tag, or could not be checked because git could not reach GitHub
#   1  a pin does not match its tag, or the workflow directory is missing
#
# Usage:
#   ./pin-actions-latest.sh [-d WORKFLOW_DIR] [-t TOKEN] [-n] [-f] [-v]
#
#   -d WORKFLOW_DIR   Path to the workflows folder. Default: .github/workflows
#   -t TOKEN          GitHub PAT. Defaults to $GITHUB_TOKEN. Without one the API allows 60 requests an hour.
#   -n                Dry run - prints changes without writing any workflow files.
#   -f                ForceRefresh - bypass the tag cache and always fetch the latest tag.
#   -v                Verbose - also print every API request and its HTTP status, tag counts, cache ages and git lookups.
#   -h                Show this help.
#
# Requires: bash 4.4+, curl, jq, git. Set NO_COLOR to turn off colours.

set -euo pipefail

WORKFLOW_DIR=".github/workflows"
TOKEN="${GITHUB_TOKEN:-}"
DRY_RUN=false
FORCE_REFRESH=false
VERBOSE=false

usage() {
    # The header comment only, not every comment in the file.
    sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p}' "$0"
    exit "${1:-0}"
}

while getopts ":d:t:nfvh" opt; do
    case "$opt" in
        d) WORKFLOW_DIR="$OPTARG" ;;
        t) TOKEN="$OPTARG" ;;
        n) DRY_RUN=true ;;
        f) FORCE_REFRESH=true ;;
        v) VERBOSE=true ;;
        h) usage 0 ;;
        \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
        :) echo "Option -$OPTARG requires an argument." >&2; usage 1 ;;
    esac
done

for cmd in curl jq git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command '$cmd' not found in PATH." >&2
        exit 1
    fi
done

if [[ -n "${NO_COLOR:-}" ]]; then
    GREEN="" YELLOW="" RED="" WHITE="" RESET=""
else
    ESC=$'\033'
    GREEN="${ESC}[32m" YELLOW="${ESC}[33m" RED="${ESC}[31m" WHITE="${ESC}[97m" RESET="${ESC}[0m"
fi

STARTED=$(date +%s)
CACHE_FILE=".github/pin-cache.json"
CACHE_TTL_SECONDS=$((24 * 60 * 60))
SEMVER_RE='^v?[0-9]+(\.[0-9]+){0,2}$'
SHA_RE='^[0-9a-f]{40}$'
# Matches:  [leading ws][- ]uses: owner/repo[/path]@ref [# comment]
USES_RE='^([[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_./-]+)?)@([^[:space:]#]+)([[:space:]]*#.*)?$'
TAG_IN_COMMENT_RE='v?[0-9]+(\.[0-9]+){0,2}'

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Load cache into a working file, or start with an empty object
CACHE_WORKING="$WORK/cache.json"
mkdir -p "$(dirname "$CACHE_FILE")"
if [[ -f "$CACHE_FILE" ]] && jq -e 'type == "object"' "$CACHE_FILE" >/dev/null 2>&1; then
    cp "$CACHE_FILE" "$CACHE_WORKING"
else
    if [[ -f "$CACHE_FILE" ]]; then
        echo -e "${YELLOW}  cache    $CACHE_FILE is not valid JSON; starting empty${RESET}"
    fi
    echo '{}' > "$CACHE_WORKING"
fi

AUTH_ARGS=()
if [[ -n "$TOKEN" ]]; then
    AUTH_ARGS=(-H "Authorization: Bearer $TOKEN")
fi

API_CALLS=0
API_DOWN=false
HTTP_STATUS=""

vlog() {
    if [[ "$VERBOSE" == true ]]; then
        echo "  VERBOSE: $*"
    fi
}

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

format_age() {
    local s="$1"
    if (( s < 3600 )); then
        echo "$((s / 60))m"
    elif (( s < 172800 )); then
        echo "$((s / 3600))h"
    else
        echo "$((s / 86400))d"
    fi
}

short() {
    echo "${1:0:12}"
}

# is_older <candidate> <current>
# Returns 0 (true) if candidate is an older version than current.
# Non-semver-looking values (e.g. a commit SHA with no comment tag) are
# treated as "unknown", never blocked, since there is nothing to compare.
is_older() {
    local candidate="${1#v}" current="${2#v}"
    [[ -z "$candidate" || -z "$current" ]] && return 1
    [[ "$candidate" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || return 1
    [[ "$current" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || return 1
    [[ "$candidate" == "$current" ]] && return 1
    local highest
    highest=$(printf '%s\n%s\n' "$candidate" "$current" | sort -V | tail -n1)
    [[ "$highest" == "$current" ]]
}

highest_semver() {
    # Reads tag names on stdin and prints the highest plain semver tag.
    # On a tie (v4 and v4.0.0) the longer, more specific name wins.
    { grep -E "$SEMVER_RE" || true; } |
        awk '{ v = $0; sub(/^[vV]/, "", v); n = split(v, p, "."); while (n < 3) p[++n] = 0
               printf "%s.%s.%s\t%d\t%s\n", p[1], p[2], p[3], length($0), $0 }' |
        sort -t $'\t' -k1,1V -k2,2n | tail -n 1 | cut -f 3
}

format_http_status() {
    if [[ -z "$1" ]]; then
        echo "no response"
    elif [[ "$1" == "403" || "$1" == "429" ]]; then
        echo "HTTP $1 (rate limit?)"
    else
        echo "HTTP $1"
    fi
}

api_get() {
    # api_get <url> <outfile>; sets HTTP_STATUS, empty when there was no response
    if [[ "$API_DOWN" == true ]]; then
        HTTP_STATUS=""
        return 0
    fi
    API_CALLS=$((API_CALLS + 1))
    HTTP_STATUS=$(curl -s --max-time 20 -o "$2" -w "%{http_code}" "${AUTH_ARGS[@]}" \
        -H "User-Agent: pin-actions-latest-sh" -H "Accept: application/vnd.github+json" "$1" || true)
    if [[ "$HTTP_STATUS" == "000" ]]; then
        HTTP_STATUS=""
    fi
    vlog "GET $1 -> $(format_http_status "$HTTP_STATUS")"
}

###############################################################################
# Tags straight from git: no token, no API quota. The fallback and the check.
###############################################################################
tags_file() {
    echo "$WORK/tags_${1//\//__}"
}

fetch_remote_tags() {
    # Writes "<tag> <commit sha>" lines for the repo; writes nothing when git cannot reach it.
    local out raw
    out=$(tags_file "$1")
    raw="$out.raw"
    if GIT_TERMINAL_PROMPT=0 git ls-remote --tags "https://github.com/$1.git" > "$raw" 2>/dev/null; then
        # An annotated tag is listed twice; its ^{} line is the commit it points at, and wins.
        awk '{ ref = $2; sub(/^refs\/tags\//, "", ref)
               if (ref ~ /\^\{\}$/) { sub(/\^\{\}$/, "", ref); peeled[ref] = $1 } else { plain[ref] = $1 } }
             END { for (r in plain) print r, ((r in peeled) ? peeled[r] : plain[r])
                   for (r in peeled) if (!(r in plain)) print r, peeled[r] }' "$raw" > "$out"
    fi
    rm -f "$raw"
}

remote_ok() {
    [[ -f "$(tags_file "$1")" ]]
}

remote_find_tag() {
    # The tag name as git lists it, allowing for a comment that adds or drops the leading v.
    awk -v a="$2" -v b="v$2" -v c="${2#v}" \
        '$1 == a { print a; found = 1; exit } $1 == b { hb = 1 } $1 == c { hc = 1 }
         END { if (!found) { if (hb) print b; else if (hc) print c } }' "$(tags_file "$1")"
}

remote_sha() {
    awk -v t="$2" '$1 == t { print $2; exit }' "$(tags_file "$1")"
}

tag_for_commit() {
    local names best
    if ! remote_ok "$1"; then
        echo "unknown, git could not reach GitHub"
        return 0
    fi
    names=$(awk -v s="$2" '$2 == s { print $1 }' "$(tags_file "$1")")
    if [[ -z "$names" ]]; then
        echo "not a tagged commit"
        return 0
    fi
    best=$(highest_semver <<< "$names")
    if [[ -n "$best" ]]; then
        echo "$best"
    else
        echo "${names%%$'\n'*}"
    fi
}

###############################################################################
# Lookups. Results come back in R_* variables, never on stdout, so status lines can't leak into them.
###############################################################################
resolve_latest_tag() {
    local repo="$1" cached_tag cached_checked age failure="" page=1 count tag="" src="API"
    R_TAG="" R_SRC="" R_FAIL=""

    cached_tag=$(cache_get "$repo" "latestTag")
    cached_checked=$(cache_get "$repo" "lastChecked")
    if [[ "$FORCE_REFRESH" == false && -n "$cached_tag" && -n "$cached_checked" ]]; then
        age=$(seconds_since "$cached_checked")
        if (( age < CACHE_TTL_SECONDS )); then
            vlog "$repo cached tag $cached_tag, checked $(format_age "$age") ago"
            R_TAG="$cached_tag" R_SRC="cache $(format_age "$age")"
            return 0
        fi
        vlog "$repo cached tag $cached_tag is $(format_age "$age") old, past the 24h TTL"
    fi

    # Primary source of truth: scan the FULL tag list and pick the highest
    # semantic version. We deliberately do NOT trust /releases/latest as
    # authoritative here: that endpoint returns the release with the most
    # recent *publish event*, not the highest version number. If a
    # maintainer edits or re-publishes an old release (changelog fix,
    # security note, archival cleanup, etc.), its published_at timestamp
    # bumps and GitHub will report it as "latest" even though far newer
    # tags exist - which is exactly what happened with actions/setup-java
    # returning v1.4.5 while v5.7.0 existed.
    : > "$WORK/alltags"
    while (( page <= 10 )); do
        api_get "https://api.github.com/repos/$repo/tags?per_page=100&page=$page" "$WORK/resp.json"
        if [[ "$HTTP_STATUS" != "200" ]]; then
            failure="tags API $(format_http_status "$HTTP_STATUS")"
            # A partial list could crown the wrong tag.
            : > "$WORK/alltags"
            break
        fi
        jq -r '.[].name' "$WORK/resp.json" >> "$WORK/alltags"
        count=$(jq 'length' "$WORK/resp.json")
        if (( count < 100 )); then
            break
        fi
        page=$((page + 1))
    done

    tag=$(highest_semver < "$WORK/alltags")
    if [[ -z "$failure" ]]; then
        vlog "$repo tags API: $(wc -l < "$WORK/alltags" | tr -d ' ') tags over $page page(s), highest semver ${tag:-none}"
    fi

    # Fallback: repo has no semver-looking tags at all (rare - e.g. an
    # action that only ever cuts GitHub Releases without matching git
    # tags). Only in that case do we trust /releases/latest.
    if [[ -z "$tag" && -z "$failure" ]]; then
        api_get "https://api.github.com/repos/$repo/releases/latest" "$WORK/resp.json"
        if [[ "$HTTP_STATUS" == "200" ]]; then
            tag=$(jq -r '.tag_name // empty' "$WORK/resp.json")
            src="releases API"
        else
            failure="no semver tags, releases API $(format_http_status "$HTTP_STATUS")"
        fi
    fi

    if [[ -z "$tag" && -n "$failure" ]] && remote_ok "$repo"; then
        tag=$(cut -d ' ' -f 1 "$(tags_file "$repo")" | highest_semver)
        src="git"
    fi

    if [[ -n "$tag" ]]; then
        cache_set "$repo" "latestTag" "$tag"
        cache_set "$repo" "lastChecked" "$(now_iso)"
        R_TAG="$tag" R_SRC="$src"
        return 0
    fi

    if [[ -n "$cached_tag" ]]; then
        R_TAG="$cached_tag" R_SRC="stale cache, $failure"
        return 0
    fi

    R_FAIL="${failure:-no usable tag in tags or releases}, git could not list tags"
}

resolve_commit_sha() {
    local repo="$1" tag="$2" cached_sha cached_sha_tag sha="" src="" failure="" name
    R_SHA="" R_SHA_SRC="" R_SHA_FAIL=""

    cached_sha=$(cache_get "$repo" "sha")
    cached_sha_tag=$(cache_get "$repo" "shaTag")
    vlog "$repo cached sha $(short "$cached_sha") is for tag ${cached_sha_tag:-(not recorded)}"
    # A cached SHA is only good for the tag it was resolved from. Matching on latestTag instead once paired a
    # freshly found tag with the previous tag's SHA, and wrote that pair into the workflows.
    if [[ -n "$cached_sha" && "$cached_sha_tag" == "$tag" ]]; then
        R_SHA="$cached_sha" R_SHA_SRC="cache"
        return 0
    fi

    api_get "https://api.github.com/repos/$repo/commits/$tag" "$WORK/resp.json"
    if [[ "$HTTP_STATUS" == "200" ]]; then
        sha=$(jq -r '.sha // empty' "$WORK/resp.json")
        src="API"
    fi
    if [[ -z "$sha" ]]; then
        failure="commits API $(format_http_status "$HTTP_STATUS")"
        if remote_ok "$repo"; then
            name=$(remote_find_tag "$repo" "$tag")
            if [[ -n "$name" ]]; then
                sha=$(remote_sha "$repo" "$name")
                src="git"
            fi
        fi
    fi

    if [[ -n "$sha" ]]; then
        cache_set "$repo" "sha" "$sha"
        cache_set "$repo" "shaTag" "$tag"
        R_SHA="$sha" R_SHA_SRC="$src"
        return 0
    fi

    R_SHA_FAIL="$failure, git could not resolve it"
}

###############################################################################
# Find every uses: line
###############################################################################
if [[ ! -d "$WORKFLOW_DIR" ]]; then
    echo -e "${RED}Workflow directory not found: $WORKFLOW_DIR${RESET}" >&2
    exit 1
fi

shopt -s nullglob
FILES=("$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml)
E_FILE=() E_IDX=() E_ORIG=() E_PREFIX=() E_ACTION=() E_REPO=() E_REF=() E_TAG=() E_NEW=() E_STATUS=() E_DETAIL=()
REPOS=()
declare -A SEEN_REPO=()

for file in "${FILES[@]}"; do
    mapfile -t lines < "$file"
    for i in "${!lines[@]}"; do
        line="${lines[$i]%$'\r'}"
        if ! [[ "$line" =~ $USES_RE ]]; then
            continue
        fi
        action="${BASH_REMATCH[3]}"
        if [[ "$action" == ./* ]]; then
            continue
        fi
        prefix="${BASH_REMATCH[1]}" ref="${BASH_REMATCH[5]}" comment="${BASH_REMATCH[6]}"
        repo=$(cut -d '/' -f 1,2 <<< "$action")
        E_FILE+=("$file") E_IDX+=("$i") E_ORIG+=("$line") E_PREFIX+=("$prefix") E_ACTION+=("$action")
        E_REPO+=("$repo") E_REF+=("$ref") E_NEW+=("$line") E_STATUS+=("") E_DETAIL+=("")
        E_TAG+=("$(grep -oE "$TAG_IN_COMMENT_RE" <<< "$comment" | head -n 1 || true)")
        if [[ -z "${SEEN_REPO[$repo]:-}" ]]; then
            SEEN_REPO[$repo]=1
            REPOS+=("$repo")
        fi
    done
done
N=${#E_ACTION[@]}

###############################################################################
# Header
###############################################################################
echo -e "${WHITE}Pin GitHub Actions${RESET}: ${#FILES[@]} workflow files, $N uses: lines, ${#REPOS[@]} actions"

if [[ -n "$TOKEN" ]]; then
    api_get "https://api.github.com/rate_limit" "$WORK/rate.json"
    API_CALLS=$((API_CALLS - 1))   # the quota check is free
    if [[ "$HTTP_STATUS" == "200" ]]; then
        read -r remaining limit reset_epoch < <(jq -r '.resources.core | "\(.remaining) \(.limit) \(.reset)"' "$WORK/rate.json")
        resets_at=$(date -d "@$reset_epoch" +%H:%M 2>/dev/null || date -r "$reset_epoch" +%H:%M 2>/dev/null || echo "?")
        colour=""
        if (( remaining < 100 )); then
            colour="$YELLOW"
        fi
        echo -e "${colour}  token    set (API quota $remaining of $limit left, resets $resets_at)${RESET}"
    elif [[ "$HTTP_STATUS" == "401" ]]; then
        API_DOWN=true
        echo -e "${YELLOW}  token    rejected (HTTP 401): check GITHUB_TOKEN; looking up with git instead${RESET}"
    else
        API_DOWN=true
        echo -e "${YELLOW}  token    set, but the GitHub API gave $(format_http_status "$HTTP_STATUS"); looking up with git and the cache${RESET}"
    fi
else
    echo -e "${YELLOW}  token    not set: unauthenticated API, 60 requests an hour${RESET}"
fi

cache_note=""
if [[ "$FORCE_REFRESH" == true ]]; then
    cache_note=", tags bypassed (-f)"
fi
echo "  cache    $CACHE_FILE, $(jq 'length' "$CACHE_WORKING") entries, 24h TTL$cache_note"
if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}  mode     DRY RUN, no workflow file is written${RESET}"
else
    echo "  mode     write"
fi

if (( N == 0 )); then
    echo ""
    echo "  No uses: lines found."
    exit 0
fi

###############################################################################
# List every repo's tags with git, in parallel: one at a time is most of a minute
###############################################################################
git_started=$(date +%s)
for repo in "${REPOS[@]}"; do
    fetch_remote_tags "$repo" &
done
wait
reachable=0
for repo in "${REPOS[@]}"; do
    if remote_ok "$repo"; then
        reachable=$((reachable + 1))
        vlog "git ls-remote $repo -> $(wc -l < "$(tags_file "$repo")" | tr -d ' ') tags"
    else
        vlog "git ls-remote $repo -> failed"
    fi
done
colour=""
if (( reachable < ${#REPOS[@]} )); then
    colour="$YELLOW"
fi
echo -e "${colour}  git      tags listed for $reachable of ${#REPOS[@]} actions in $(( $(date +%s) - git_started ))s${RESET}"
echo ""

###############################################################################
# Resolve each action and decide what its lines become
###############################################################################
declare -A COUNTS=([FIXED]=0 [UPDATED]=0 [PINNED]=0 [ok]=0 [SKIPPED]=0 [UNRESOLVED]=0)

for repo in "${REPOS[@]}"; do
    resolve_latest_tag "$repo"
    R_SHA="" R_SHA_SRC="" R_SHA_FAIL=""
    if [[ -n "$R_TAG" ]]; then
        resolve_commit_sha "$repo" "$R_TAG"
    fi

    # Lines of this action that share a status and detail print once, as "owner/repo xN".
    group_key=() group_count=() group_first=()
    for ((k = 0; k < N; k++)); do
        if [[ "${E_REPO[$k]}" != "$repo" ]]; then
            continue
        fi
        ref="${E_REF[$k]}" etag="${E_TAG[$k]}"
        if [[ -z "$R_TAG" ]]; then
            st="UNRESOLVED" det="$R_FAIL; line left as it is"
        elif [[ -n "$etag" ]] && is_older "$R_TAG" "$etag"; then
            st="SKIPPED" det="newest tag $R_TAG is older than pinned $etag"
        elif [[ -z "$R_SHA" ]]; then
            st="UNRESOLVED" det="no SHA for $R_TAG: $R_SHA_FAIL; line left as it is"
        else
            E_NEW[k]="${E_PREFIX[$k]}${E_ACTION[$k]}@${R_SHA} # ${R_TAG}"
            if [[ "${E_NEW[$k]}" == "${E_ORIG[$k]}" ]]; then
                st="ok" det="tag $R_SRC, sha $R_SHA_SRC"
            elif ! [[ "$ref" =~ $SHA_RE ]]; then
                st="PINNED" det="@$ref -> $(short "$R_SHA")"
            elif [[ "$ref" == "$R_SHA" ]]; then
                st="UPDATED" det="comment only, now # $R_TAG"
            elif [[ -n "$etag" && "${etag#v}" == "${R_TAG#v}" ]]; then
                st="FIXED" det="$(short "$ref") -> $(short "$R_SHA") (old SHA: $(tag_for_commit "$repo" "$ref"))"
            else
                st="UPDATED" det="${etag:-untagged} -> $R_TAG, $(short "$ref") -> $(short "$R_SHA")"
            fi
        fi
        E_STATUS[k]="$st" E_DETAIL[k]="$det"
        COUNTS[$st]=$(( ${COUNTS[$st]} + 1 ))

        gi=-1
        for ((g = 0; g < ${#group_key[@]}; g++)); do
            if [[ "${group_key[$g]}" == "$st|$det" ]]; then
                gi=$g
                break
            fi
        done
        if (( gi < 0 )); then
            group_key+=("$st|$det") group_count+=(0) group_first+=("$k")
            gi=$(( ${#group_key[@]} - 1 ))
        fi
        group_count[gi]=$(( group_count[gi] + 1 ))
    done

    for ((g = 0; g < ${#group_key[@]}; g++)); do
        k=${group_first[$g]}
        st="${E_STATUS[$k]}"
        name="$repo"
        if (( group_count[g] > 1 )); then
            name="$repo x${group_count[$g]}"
        fi
        case "$st" in
            SKIPPED|UNRESOLVED) shown="${E_TAG[$k]}" colour="$YELLOW" ;;
            ok) shown="$R_TAG" colour="" ;;
            *) shown="$R_TAG" colour="$GREEN" ;;
        esac
        printf "  %-36s %-9s %s%-10s%s %s\n" "$name" "$shown" "$colour" "$st" "$RESET" "${E_DETAIL[$k]}"
    done
done
echo ""

###############################################################################
# Write the workflow files and the cache
###############################################################################
WRITTEN=()
for file in "${FILES[@]}"; do
    changed=0
    for ((k = 0; k < N; k++)); do
        if [[ "${E_FILE[$k]}" == "$file" && "${E_NEW[$k]}" != "${E_ORIG[$k]}" ]]; then
            changed=$((changed + 1))
        fi
    done
    if (( changed == 0 )); then
        continue
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Keep each line's own ending (CRLF or LF) and whether the file ends in a newline.
        mapfile -t lines < "$file"
        for ((k = 0; k < N; k++)); do
            if [[ "${E_FILE[$k]}" == "$file" ]]; then
                idx=${E_IDX[$k]}
                cr=""
                if [[ "${lines[$idx]}" == *$'\r' ]]; then
                    cr=$'\r'
                fi
                lines[idx]="${E_NEW[$k]}$cr"
            fi
        done
        final_newline=true
        if [[ -n "$(tail -c 1 "$file")" ]]; then
            final_newline=false
        fi
        last=$(( ${#lines[@]} - 1 ))
        {
            for ((j = 0; j <= last; j++)); do
                if (( j < last )) || [[ "$final_newline" == true ]]; then
                    printf '%s\n' "${lines[$j]}"
                else
                    printf '%s' "${lines[$j]}"
                fi
            done
        } > "$WORK/write.tmp"
        cat "$WORK/write.tmp" > "$file"
    fi

    plural="s"
    if (( changed == 1 )); then
        plural=""
    fi
    WRITTEN+=("$(basename "$file") ($changed line$plural)")
done

written_list=""
if (( ${#WRITTEN[@]} > 0 )); then
    printf -v written_list '%s, ' "${WRITTEN[@]}"
    written_list="${written_list%, }"
fi
if [[ -z "$written_list" ]]; then
    echo "  written  nothing, every line is already current"
elif [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}  written  nothing (DRY RUN); would write $written_list${RESET}"
else
    echo -e "${GREEN}  written  $written_list${RESET}"
fi

cp "$CACHE_WORKING" "$CACHE_FILE"
vlog "cache saved to $CACHE_FILE, $(jq 'length' "$CACHE_FILE") entries"

###############################################################################
# Check every pin against its tag with git, independently of the API and the cache
###############################################################################
VERIFIED=0 UNVERIFIED=0
MISMATCHES=() UNPINNED=() UNREACHED=()
declare -A SEEN_UNREACHED=()

for ((k = 0; k < N; k++)); do
    if ! [[ "${E_NEW[$k]}" =~ $USES_RE ]]; then
        continue
    fi
    ref="${BASH_REMATCH[5]}" comment="${BASH_REMATCH[6]}"
    tag=$(grep -oE "$TAG_IN_COMMENT_RE" <<< "$comment" | head -n 1 || true)
    action="${E_ACTION[$k]}" repo="${E_REPO[$k]}"
    if ! [[ "$ref" =~ $SHA_RE ]]; then
        UNPINNED+=("$action@$ref is not pinned to a SHA")
        continue
    fi
    if [[ -z "$tag" ]]; then
        UNPINNED+=("$action has no tag in its comment to check against")
        continue
    fi
    if ! remote_ok "$repo"; then
        UNVERIFIED=$((UNVERIFIED + 1))
        if [[ -z "${SEEN_UNREACHED[$repo]:-}" ]]; then
            SEEN_UNREACHED[$repo]=1
            UNREACHED+=("$repo")
        fi
        continue
    fi
    name=$(remote_find_tag "$repo" "$tag")
    if [[ -z "$name" ]]; then
        MISMATCHES+=("$action # $tag: no such tag")
        continue
    fi
    tag_sha=$(remote_sha "$repo" "$name")
    if [[ "$tag_sha" != "$ref" ]]; then
        MISMATCHES+=("$action # $tag: pinned $(short "$ref") is $(tag_for_commit "$repo" "$ref"), the tag is $(short "$tag_sha")")
    else
        VERIFIED=$((VERIFIED + 1))
    fi
done

checked_what="git ls-remote"
if [[ "$DRY_RUN" == true ]]; then
    checked_what="as they would be written"
fi
if (( ${#MISMATCHES[@]} > 0 )); then
    echo -e "${RED}  verify   FAILED: ${#MISMATCHES[@]} of $N pins do not match their tag ($checked_what)${RESET}"
    for m in "${MISMATCHES[@]}"; do
        echo -e "${RED}             $m${RESET}"
    done
elif (( VERIFIED > 0 || UNVERIFIED == 0 )); then
    colour=""
    if (( VERIFIED == N )); then
        colour="$GREEN"
    fi
    echo -e "${colour}  verify   $VERIFIED of $N pins match their tag ($checked_what)${RESET}"
fi
if (( UNVERIFIED > 0 )); then
    printf -v unreached_list '%s, ' "${UNREACHED[@]}"
    echo -e "${YELLOW}  verify   $UNVERIFIED of $N pins not checked, git could not reach GitHub for: ${unreached_list%, }${RESET}"
fi
for u in ${UNPINNED[@]+"${UNPINNED[@]}"}; do
    echo -e "${YELLOW}  verify   $u${RESET}"
done

###############################################################################
# Summary
###############################################################################
summary=""
for st in FIXED UPDATED PINNED ok SKIPPED UNRESOLVED; do
    summary+="${COUNTS[$st]} $st, "
done
result_colour="$GREEN"
if (( ${#MISMATCHES[@]} > 0 )); then
    result_colour="$RED"
elif (( COUNTS[SKIPPED] + COUNTS[UNRESOLVED] + UNVERIFIED > 0 )); then
    result_colour="$YELLOW"
fi
echo -e "${result_colour}  result   ${summary%, }; $API_CALLS API calls; $(( $(date +%s) - STARTED ))s${RESET}"

if (( ${#MISMATCHES[@]} > 0 )); then
    exit 1
fi
exit 0
