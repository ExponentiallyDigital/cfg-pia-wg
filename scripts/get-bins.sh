#!/bin/sh
# Installs latest jq and mailsend-go to /jffs/cfg-pia-wg

set -e

ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

mkdir -p /jffs/cfg-pia-wg

# Function to fetch the latest download URL from GitHub API
get_latest_url() {
    repo="$1"
    pattern="$2"
    curl -s "https://api.github.com/repos/$repo/releases/latest" | \
        grep "browser_download_url.*$pattern" | \
        head -1 | \
        cut -d '"' -f 4
}

case "$ARCH" in
    aarch64)
        MAILSEND_GO_URL=$(get_latest_url "muquit/mailsend-go" "linux-arm64")
        JQ_URL=$(get_latest_url "jqlang/jq" "linux-arm64")
        ;;
    armv7l)
        MAILSEND_GO_URL=$(get_latest_url "muquit/mailsend-go" "linux-arm")
        JQ_URL=$(get_latest_url "jqlang/jq" "linux-armhf")
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# --- Install mailsend-go ---
echo "Downloading mailsend-go from: $MAILSEND_GO_URL"
wget -O /tmp/mailsend-go.tar.gz "$MAILSEND_GO_URL"

# Create a clean extraction directory (avoid using mktemp)
EXTRACT_DIR="/tmp/mailsend-extract"
rm -rf "$EXTRACT_DIR"          # remove any leftover from previous runs
mkdir -p "$EXTRACT_DIR"

tar -xzf /tmp/mailsend-go.tar.gz -C "$EXTRACT_DIR"

# Find the binary (exclude .txt and .md files)
BINARY=$(find "$EXTRACT_DIR" -name "mailsend-go*" | grep -v '\.txt$' | grep -v '\.md$' | head -1)

if [ -z "$BINARY" ]; then
    echo "ERROR: Could not find mailsend-go binary in the tarball"
    exit 1
fi

# Move and rename to 'mailsend-go'
mv "$BINARY" /jffs/cfg-pia-wg/mailsend-go
chmod 755 /jffs/cfg-pia-wg/mailsend-go
chown 0:0 /jffs/cfg-pia-wg/mailsend-go

# Clean up temporary files
rm -f /tmp/mailsend-go.tar.gz
rm -rf "$EXTRACT_DIR"

# --- Install jq (raw binary, no archive) ---
echo "Downloading jq from: $JQ_URL"
wget -O /jffs/cfg-pia-wg/jq "$JQ_URL"
chmod 755 /jffs/cfg-pia-wg/jq

echo "Installation complete."
echo "Binaries installed to /jffs/cfg-pia-wg/"
echo "  - /jffs/cfg-pia-wg/mailsend-go"
echo "  - /jffs/cfg-pia-wg/jq"