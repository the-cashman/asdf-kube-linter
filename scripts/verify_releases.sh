#!/usr/bin/env bash

# Script to fetch all release tags and their assets from the stackrox/kube-linter repo
# Requires jq: https://stedolan.github.io/jq/

set -euo pipefail

GH_REPO_OWNER="stackrox"
GH_REPO_NAME="kube-linter"
API_URL="https://api.github.com/repos/${GH_REPO_OWNER}/${GH_REPO_NAME}/releases"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq." >&2
    echo "See: https://stedolan.github.io/jq/download/" >&2
    exit 1
fi

echo "Fetching release data from ${API_URL}..." >&2

# Fetch all releases using pagination (GitHub API might limit results per page)
all_releases_json="[]"
page=1
while true; do
    echo "Fetching page ${page}..." >&2
    # Add GITHUB_API_TOKEN if available for higher rate limits
    if [ -n "${GITHUB_API_TOKEN:-}" ]; then
        releases_json=$(curl -fsSL -H "Authorization: token $GITHUB_API_TOKEN" "${API_URL}?page=${page}&per_page=100")
    else
        releases_json=$(curl -fsSL "${API_URL}?page=${page}&per_page=100")
    fi

    # Check if the page returned any releases
    if [ "$(echo "$releases_json" | jq 'length')" -eq 0 ]; then
        break # No more releases found
    fi

    # Append the current page's releases to the total list
    all_releases_json=$(echo "$all_releases_json $releases_json" | jq -s 'add')
    page=$((page + 1))
done

echo "Processing release data..." >&2

# Process the JSON data and print tag and asset names
echo "$all_releases_json" | jq -c '.[] | {tag: .tag_name, assets: [.assets[].name]}' | while IFS= read -r line; do
    tag=$(echo "$line" | jq -r '.tag')
    assets=$(echo "$line" | jq -r '.assets | join(", ")')
    echo "Tag: ${tag}"
    echo "  Assets: ${assets:-No assets found}"
    echo "" # Add a blank line for readability
done

echo "Finished fetching release data." >&2