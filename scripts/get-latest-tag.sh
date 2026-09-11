#!/bin/bash
#
# get-latest-tag.sh
#   For a list of GitHub repos, fetch the latest semver‑style tag
#   and the commit SHA it points at.
#
# Usage:
#   bash get-latest-tag.sh
#
# -------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status.
set -e

# repos to check for latest tag
repos=(
  "https://github.com/actions/checkout.git"
  "https://github.com/actions/setup-java.git"
  "https://github.com/subosito/flutter-action.git"
  "https://github.com/SonarSource/sonarqube-scan-action.git"
  "https://github.com/actions/upload-artifact.git"
  "https://github.com/google/osv-scanner-action.git"
  "https://github.com/actions/download-artifact.git"
  "https://github.com/MobSF/mobsfscan.git"
  "https://github.com/github/codeql-action.git"
  "https://github.com/actions/attest-build-provenance.git"
  "https://github.com/r0adkll/upload-google-play.git"
  "https://github.com/anchore/sbom-action.git"
  "https://github.com/softprops/action-gh-release.git"
  "https://github.com/kevin-david/promote-play-release.git"
)

# Loop through each repo and fetch the latest tag and its commit SHA
for url in "${repos[@]}"; do
  echo "  $url"

  # Pull all tags, keep only 'refs/tags/[v]MAJOR.MINOR.PATCH'
  #      The awk line:
  #        - fields are tab‑separated (sha \t ref)
  #        - $2 must match "refs/tags/v" followed by three numeric groups OR just "refs/tags/" followed by three numeric groups
  #        - we strip the leading 'refs/tags/v' or 'refs/tags/' from the tag name and output "sha\ttag"
  latest=$(git ls-remote --tags "$url" \
    | awk -F'\t' \
        '$2 ~ /^refs\/tags\/v?[0-9]+\.[0-9]+\.[0-9]+$/ {
          sha = $1
          tag = $2
          sub(/^refs\/tags\/v/, "", tag)
          sub(/^refs\/tags\//, "", tag)
          print sha "\t" tag
        }' \
    | sort -t$'\t' -k2 -V \
    | tail -n1)

  # If no tags were found, print a message and skip to the next repo
  if [[ -z "$latest" ]]; then
    echo "   No ‘X.Y.Z’ or ‘vX.Y.Z’ tags found – skipping."
  else
  # If a tag was found, split the output into SHA and tag, and print them
    sha=$(echo "$latest" | cut -f1)
    tag=$(echo "$latest" | cut -f2)
    echo "   Latest tag : $tag"
    echo "   Commit SHA : $sha"
  fi

  echo "   ---"
done
