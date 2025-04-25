#!/usr/bin/env bash

set -euo pipefail

GH_REPO="https://github.com/stackrox/kube-linter"
TOOL_NAME="kube-linter"
TOOL_TEST="kube-linter --help"

fail() {
  echo -e "asdf-$TOOL_NAME: $*"
  exit 1
}

curl_opts=(-fsSL)

if [ -n "${GITHUB_API_TOKEN:-}" ]; then
  curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

sort_versions() {
  sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
    LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

# Fetches all tags from the GitHub repository
list_github_tags() {
  git ls-remote --tags --refs "$GH_REPO" |
    grep -o 'refs/tags/.*' | cut -d/ -f3- || fail "Could not list tags from $GH_REPO"
}

# Lists all versions, stripping the 'v' prefix for consistency
list_all_versions() {
  list_github_tags | sed 's/^v//'
}

# Given a normalized version (e.g., 0.6.1), find the actual tag used in GH (e.g., v0.6.1)
find_actual_github_tag() {
  local normalized_version="$1"
  local actual_tag
  actual_tag=$(list_github_tags | grep -E "^v?${normalized_version}$" | head -n 1)

  if [ -z "$actual_tag" ]; then
    fail "Failed to find actual GitHub tag for version ${normalized_version}"
  fi
  echo "$actual_tag"
}

# Check if a version is supported for a specific architecture
is_version_supported_for_arch() {
  local version="$1"     # Actual tag (e.g., v0.6.8)
  local os="$2"          # darwin or linux
  local arch_suffix="$3" # _arm64 or empty

  # Always supported if arch_suffix is empty (amd64)
  if [[ -z "$arch_suffix" ]]; then
    return 0
  fi

  # Remove 'v' prefix if present for comparison
  local ver_num="${version#v}"

  IFS='.' read -r major minor patch <<<"$ver_num"
  patch="${patch:-0}" # Default to 0 if patch is not specified

  # Convert to a single number for comparison (major*10000 + minor*100 + patch)
  local ver_val=$((major * 10000 + minor * 100 + patch))

  # ARM64 architectures were added in v0.6.8
  if [[ "$arch_suffix" == "_arm64" && "$ver_val" -lt 608 ]]; then
    return 1 # Not supported
  fi

  return 0 # Supported
}

# Determine OS, architecture, and construct the download URL
get_download_url() {
  local normalized_version="$1"
  local actual_tag
  local uname_s uname_m os arch_suffix url

  echo "DEBUG: Finding actual tag for normalized version: $normalized_version" >&2
  actual_tag=$(find_actual_github_tag "$normalized_version")
  echo "DEBUG: Found actual tag: $actual_tag" >&2

  uname_s="${ASDF_TEST_UNAME_S:-$(uname -s)}"
  uname_m="${ASDF_TEST_UNAME_M:-$(uname -m)}"

  case "$uname_s" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *) fail "OS not supported: $uname_s. Only Linux and Darwin are supported." ;;
  esac

  arch_suffix=""
  case "$uname_m" in
  arm64 | aarch64) arch_suffix="_arm64" ;;
  x86_64 | amd64) arch_suffix="" ;;
  *) echo "Warning: Unknown architecture $uname_m, assuming amd64." >&2 ;;
  esac

  # Check architecture support using the actual tag
  if ! is_version_supported_for_arch "$actual_tag" "$os" "$arch_suffix"; then
    fail "Architecture ${os}${arch_suffix} is not supported in version $normalized_version (tag: $actual_tag). ARM64 support was added in v0.6.8 and later."
  fi

  # Asset name part for Linux/Darwin
  local asset_os_arch="${os}${arch_suffix}"

  echo "DEBUG: Using actual tag for URL: $actual_tag" >&2
  echo "DEBUG: Determined asset OS/Arch string: ${asset_os_arch}" >&2

  # Try .tar.gz URL first
  local tar_url="$GH_REPO/releases/download/${actual_tag}/kube-linter-${asset_os_arch}.tar.gz"
  echo "DEBUG: Checking URL (tar.gz): $tar_url" >&2
  # Perform HEAD request *without* auth token to check existence
  http_code=$(curl -I -L -o /dev/null -s -w "%{http_code}" "$tar_url")
  echo "DEBUG: HTTP status (tar.gz): $http_code" >&2

  if [ "$http_code" -eq 200 ]; then
    echo "DEBUG: Using .tar.gz URL: $tar_url" >&2
    echo "$tar_url"
    return 0
  fi

  # If .tar.gz not found, try raw binary URL
  local raw_binary_name="kube-linter-${asset_os_arch}"
  local raw_url="$GH_REPO/releases/download/${actual_tag}/${raw_binary_name}"

  echo "DEBUG: Checking URL (raw): $raw_url" >&2
  # Perform HEAD request *without* auth token to check existence
  http_code=$(curl -I -L -o /dev/null -s -w "%{http_code}" "$raw_url")
  echo "DEBUG: HTTP status (raw): $http_code" >&2

  if [ "$http_code" -eq 200 ]; then
    echo "DEBUG: Using raw binary URL: $raw_url" >&2
    echo "$raw_url"
    return 0
  fi

  fail "Could not find a downloadable asset (.tar.gz or raw binary) for version $normalized_version ($actual_tag) for ${asset_os_arch} at either $tar_url or $raw_url"
}

download_release() {
  local version="$1"
  local filename="$2"
  local url

  url=$(get_download_url "$version")

  # Extract asset name part for user message
  local asset_name_part="${url##*/}"
  asset_name_part="${asset_name_part#kube-linter-}"
  asset_name_part="${asset_name_part%.tar.gz}" # Remove .tar.gz if present

  echo "* Downloading $TOOL_NAME release $version for ${asset_name_part}..."

  curl "${curl_opts[@]}" -o "$filename" -C - "$url" || fail "Could not download $url"
}

install_version() {
  local install_type="$1"
  local version="$2" # Normalized version
  local install_path="${3%/bin}/bin"

  if [ "$install_type" != "version" ]; then
    fail "asdf-$TOOL_NAME supports release installs only"
  fi

  local downloaded_file
  downloaded_file=$(find "$ASDF_DOWNLOAD_PATH" -maxdepth 1 -type f -print -quit)

  if [ -z "$downloaded_file" ]; then
    fail "No downloaded file found in $ASDF_DOWNLOAD_PATH"
  fi

  echo "DEBUG: Found downloaded file: $downloaded_file" >&2
  local filename
  filename=$(basename "$downloaded_file")
  echo "DEBUG: Basename of downloaded file: $filename" >&2

  (
    mkdir -p "$install_path"

    # Final binary name is always TOOL_NAME for Linux/Mac
    local final_binary_name="$TOOL_NAME"
    local final_binary_path="$install_path/$final_binary_name"
    echo "DEBUG: Final binary path will be: $final_binary_path" >&2

    # Check if downloaded file is a tar.gz archive
    if [[ "$filename" == *.tar.gz ]]; then
      echo "* Extracting $filename..."
      # Extract directly into the final install path
      tar -xzf "$downloaded_file" -C "$install_path" || fail "Failed to extract $downloaded_file"
      # Assume extracted binary is named TOOL_NAME
      echo "DEBUG: Assuming extraction placed $final_binary_name in $install_path" >&2
    else
      echo "* Copying binary $filename..."
      # Copy the raw binary to the install path with the correct final name
      cp "$downloaded_file" "$final_binary_path" || fail "Failed to copy $downloaded_file to $final_binary_path"
    fi

    # Make the final binary executable
    chmod +x "$final_binary_path" || fail "Failed to chmod +x $final_binary_path"

    # Test the installed tool
    test -f "$final_binary_path" || fail "Expected $final_binary_path to exist."
    test -x "$final_binary_path" || fail "Expected $final_binary_path to be executable."

    echo "$TOOL_NAME $version installation was successful!"
  ) || (
    rm -rf "$install_path"
    fail "An error occurred while installing $TOOL_NAME $version."
  )
}
