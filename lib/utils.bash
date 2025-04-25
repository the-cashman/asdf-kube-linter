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
# Returns the actual tag name or exits if not found
find_actual_github_tag() {
  local normalized_version="$1"
  local actual_tag
  # Check for tag with 'v' prefix first, then without
  actual_tag=$(list_github_tags | grep -E "^v?${normalized_version}$" | head -n 1)

  if [ -z "$actual_tag" ]; then
    fail "Failed to find actual GitHub tag for version ${normalized_version}"
  fi
  echo "$actual_tag"
}


# Check if a version is supported for a specific architecture
is_version_supported_for_arch() {
  local version="$1"
  local os="$2"
  local arch_suffix="$3"

  # Skip check for standard architectures (always supported)
  if [[ -z "$arch_suffix" ]]; then
    return 0
  fi

  # Convert version string to a comparable number
  # Remove 'v' prefix if present
  local ver_num="${version#v}"

  # Split version into components
  IFS='.' read -r major minor patch <<<"$ver_num"
  patch="${patch:-0}" # Default to 0 if patch is not specified

  # Convert to a single number for comparison (major*10000 + minor*100 + patch)
  local ver_val=$((major * 10000 + minor * 100 + patch))

  # ARM64 architectures were added in v0.6.8
  if [[ "$arch_suffix" == "_arm64" && "$ver_val" -lt 608 ]]; then
    return 1
  fi

  return 0
}

# Determine OS, architecture, and construct the download URL
# Determine OS, architecture, and construct the download URL
# Accepts the *normalized* version (e.g., 0.6.1)
get_download_url() {
  local normalized_version="$1"
  local actual_tag # The actual tag on GitHub (e.g., v0.6.1)
  local uname_s uname_m os arch_suffix url

  # Find the actual tag on GitHub corresponding to the normalized version
  echo "DEBUG: Finding actual tag for normalized version: $normalized_version" >&2
  actual_tag=$(find_actual_github_tag "$normalized_version")
  echo "DEBUG: Found actual tag: $actual_tag" >&2

  # Allow overriding uname for testing purposes
  uname_s="${ASDF_TEST_UNAME_S:-$(uname -s)}"
  uname_m="${ASDF_TEST_UNAME_M:-$(uname -m)}"

  # Determine OS
  case "$uname_s" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  MINGW* | MSYS* | CYGWIN*) os="windows" ;;
  *) fail "OS not supported: $uname_s" ;;
  esac

  # Determine architecture suffix
  arch_suffix=""
  case "$uname_m" in
  arm64 | aarch64) arch_suffix="_arm64" ;;
  x86_64 | amd64) arch_suffix="" ;; # Explicitly handle common 64-bit arch
  *) echo "Warning: Unknown architecture $uname_m, assuming default." >&2 ;;
  esac

  # Check if this version supports the detected architecture
  # Note: is_version_supported_for_arch uses the original os name (linux/darwin), not the final asset name part
  local check_os="$os"
  # Use the *actual_tag* for checks and URL construction, but the *normalized_version* for user messages/failures
  if ! is_version_supported_for_arch "$actual_tag" "$check_os" "$arch_suffix"; then
    fail "Architecture ${check_os}${arch_suffix} is not supported in version $normalized_version. ARM64 support was added in v0.6.8 and later."
  fi

  # Determine the asset name part based on OS and arch
  local asset_os_arch
  if [[ "$os" == "windows" ]]; then
    if [[ -n "$arch_suffix" ]]; then
      asset_os_arch="${TOOL_NAME}${arch_suffix}.exe"
    else
      asset_os_arch="${TOOL_NAME}.exe"
    fi
  else
    asset_os_arch="${os}${arch_suffix}"
  fi

  echo "DEBUG: Received normalized version for URL construction: $normalized_version" >&2
  echo "DEBUG: Using actual tag for URL: $actual_tag" >&2
  echo "DEBUG: Determined asset OS/Arch string: ${asset_os_arch}" >&2
  # Construct the download URL using the *actual* GitHub tag
  url="$GH_REPO/releases/download/${actual_tag}/kube-linter-${asset_os_arch}.tar.gz"
  echo "DEBUG: Constructed download URL: $url" >&2
  echo "$url"
}

download_release() {
  local version="$1"
  local filename="$2"
  local url

  # Pass the normalized version to get_download_url
  url=$(get_download_url "$version")

  # Extract asset name part for user message (handle potential .exe)
  local asset_name_part="${url##*/}"
  asset_name_part="${asset_name_part#kube-linter-}"
  asset_name_part="${asset_name_part%.tar.gz}"

  # Use normalized version in user message
  echo "* Downloading $TOOL_NAME release $version for ${asset_name_part}..."

  curl "${curl_opts[@]}" -o "$filename" -C - "$url" || fail "Could not download $url"
}

install_version() {
  local install_type="$1"
  local version="$2"
  local install_path="${3%/bin}/bin"

  if [ "$install_type" != "version" ]; then
    fail "asdf-$TOOL_NAME supports release installs only"
  fi

  (
    mkdir -p "$install_path"
    cp -r "$ASDF_DOWNLOAD_PATH/"* "$install_path"
    chmod +x "$install_path/$TOOL_NAME"

    local tool_cmd
    tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)"
    test -x "$install_path/$tool_cmd" || fail "Expected $install_path/$tool_cmd to be executable."

    # Use normalized version in user message
    echo "$TOOL_NAME $version installation was successful!"
  ) || (
    rm -rf "$install_path"
    # Use normalized version in user message
    fail "An error ocurred while installing $TOOL_NAME $version."
  )
}
