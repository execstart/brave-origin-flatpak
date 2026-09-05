#!/usr/bin/env sh
set -eu

MANIFEST_FILE="io.github.execstart.BraveOrigin.yaml"
METADATA_FILE="io.github.execstart.BraveOrigin.metainfo.xml"
REPO_URL="https://github.com/brave/brave-browser/releases/download"

if [ -f "fetch.config.yml" ]; then
    ALLOW_PRERELEASE=$(grep 'allow-prerelease:' fetch.config.yml | head -1 | awk '{print $2}')
else
    ALLOW_PRERELEASE="false"
fi

if [ "$ALLOW_PRERELEASE" = "true" ]; then
    FILTER="true"
else
    FILTER=".name | contains(\"Release\")"
fi

printf "   Fetching releases from GitHub...\n"
# RELEASES_JSON=$(curl -s https://api.github.com/repos/brave/brave-browser/releases |
#     jq -c "[.[] | select(.tag_name != null and ($FILTER))] | sort_by(.created_at) | last")
LATEST_VERSION=$(curl -s https://api.github.com/repos/brave/brave-browser/releases/latest | jq .tag_name | tr -d '"' | sed 's/^v//')
# IS_PRERELEASE=$(printf "%s" "$RELEASES_JSON" | jq -r '.prerelease')

if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
    printf "   Error: Failed to fetch valid version tag from GitHub.\n"
    exit 1
fi

# Extract version from current brave-origin URL
CURRENT_VERSION=$(awk -F 'v' '{print$3}' version.txt)
CURRENT_DATE=$(date '+%Y-%m-%d')

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    printf "   Manifest is already up to date (%s).\n" "$CURRENT_VERSION"
    # We exit successfully; the workflow will see no git diff and stop.
    exit 0
fi

# Verify download URLs and download binaries to compute SHA256 before modifying any files
printf "   Downloading binaries to compute SHA256...\n"

DL_X86="$REPO_URL/v$LATEST_VERSION/brave-origin-$LATEST_VERSION-linux-amd64.zip"
TMP_X86=$(mktemp)
if ! curl --fail -L -s -o "$TMP_X86" "$DL_X86"; then
    printf "   Error: Download URL for x86_64 does not exist: %s\n   Skipping update.\n" "$DL_X86"
    rm -f "$TMP_X86"
    exit 0
fi

DL_ARM="$REPO_URL/v$LATEST_VERSION/brave-origin-$LATEST_VERSION-linux-arm64.zip"
TMP_ARM=$(mktemp)
if ! curl --fail -L -s -o "$TMP_ARM" "$DL_ARM"; then
    printf "   Error: Download URL for arm64 does not exist: %s\n   Skipping update.\n" "$DL_ARM"
    rm -f "$TMP_X86" "$TMP_ARM"
    exit 0
fi

NEW_SHA256_X86=$(sha256sum "$TMP_X86" | awk '{print $1}')
NEW_SHA256_ARM=$(sha256sum "$TMP_ARM" | awk '{print $1}')
rm -f "$TMP_X86" "$TMP_ARM"

if [ -z "$NEW_SHA256_X86" ] || [ -z "$NEW_SHA256_ARM" ]; then
    printf "   Failed to compute SHA256 checksums.\n"
    exit 1
fi

printf "   Updating manifest from %s -> %s\n" "$CURRENT_VERSION" "$LATEST_VERSION"

# Update Manifest Files
sed -i "s,${CURRENT_VERSION},${LATEST_VERSION}," "$MANIFEST_FILE" "$METADATA_FILE"
sed -i "/linux-amd64\.zip/{n;s/sha256: [a-f0-9]*/sha256: $NEW_SHA256_X86/;}" "$MANIFEST_FILE"
sed -i "/linux-arm64\.zip/{n;s/sha256: [a-f0-9]*/sha256: $NEW_SHA256_ARM/;}" "$MANIFEST_FILE"

# Update Metadata Files
sed -i  "/${CURRENT_VERSION}/i\    <release version=\"${LATEST_VERSION}\" date=\"${CURRENT_DATE}\"/>" $METADATA_FILE

# Update the version tracker
printf "version: %s\n" "$LATEST_VERSION" > version.txt

printf "   Manifest updated successfully.\n"

printf "   Done.\n"

