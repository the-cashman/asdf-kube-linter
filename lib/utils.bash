#!/usr/bin/env bash

set -euo pipefail

# GitHub repository for kube-linter releases
GH_REPO="https://github.com/stackrox/kube-linter"
TOOL_NAME="kube-linter"
# Command to test the installed tool
TOOL_TEST="kube-linter --help"

fail() {
  echo -e "asdf-$TOOL_NAME: $*"
  exit 1
}

curl_opts=(-fsSL)

# Add GitHub token to curl options if available
if [ -n "${GITHUB_API_TOKEN:-}" ]; then
  curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

# Standard version sorting function
sort_versions() {
  sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
    LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

# Fetches all tags from the GitHub repository
list_github_tags() {
  git ls-remote --tags --refs "$GH_REPO" |
    grep -o 'refs/tags/.*' | cut -d/ -f3- || fail "Could not list tags from $GH_REPO"
}

# Lists all versions, stripping the 'v' prefix for consistency.
list_all_versions() {
  list_github_tags | sed 's/^v//'
}

# Given a normalized version (e.g., 0.6.1), find the actual tag used in GH (e.g., v0.6.1)
find_actual_github_tag() {
  local normalized_version="$1"
  local actual_tag
  # Search for tags that match the normalized version, optionally prefixed with 'v'
  actual_tag=$(list_github_tags | grep -E "^v?${normalized_version}$" | head -n 1)

  if [ -z "$actual_tag" ]; then
    fail "Failed to find actual GitHub tag for version ${normalized_version}"
  fi
  echo "$actual_tag"
}

# Check if a version is supported for a specific architecture
# Kube-linter added ARM64 support in v0.6.8
is_version_supported_for_arch() {
  local version="$1"     # Actual tag (e.g., v0.6.8)
  local arch_suffix="$2" # _arm64 or empty (for amd64)

  # AMD64 is always supported (empty suffix)
  if [[ -z "$arch_suffix" ]]; then
    return 0
  fi

  # Only need to check ARM64 constraint
  if [[ "$arch_suffix" == "_arm64" ]]; then
    # Remove 'v' prefix if present for version comparison
    local ver_num="${version#v}"
    # Parse major.minor.patch
    IFS='.' read -r major minor patch <<<"$ver_num"
    major="${major:-0}"
    minor="${minor:-0}"
    patch="${patch:-0}" # Default to 0 if patch is not specified
    # Convert to a single number for comparison (major*10000 + minor*100 + patch)
    local ver_val=$((major * 10000 + minor * 100 + patch))
    # ARM64 architectures were added in v0.6.8 (608)
    if [[ "$ver_val" -lt 608 ]]; then
      # echo "DEBUG: Version $version ($ver_val) is less than 0.6.8 (608), ARM64 not supported." >&2
      return 1 # Not supported
    fi
  fi

  # echo "DEBUG: Version $version supports arch suffix '$arch_suffix'." >&2
  return 0 # Supported
}

# Download the release tar.gz asset
download_release() {
  local version="$1"  # Normalized version
  local filename="$2" # Path to save the download (provided by bin/download)
  local actual_tag os arch_suffix asset_os_arch asset_filename url

  # Determine OS and Arch
  local uname_s="${ASDF_TEST_UNAME_S:-$(uname -s)}"
  local uname_m="${ASDF_TEST_UNAME_M:-$(uname -m)}"

  case "$uname_s" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *) fail "OS not supported: $uname_s. Only Linux and Darwin are supported." ;;
  esac

  arch_suffix=""
  case "$uname_m" in
  arm64 | aarch64) arch_suffix="_arm64" ;;
  x86_64 | amd64) arch_suffix="" ;; # amd64 uses no suffix in asset name
  *) echo "Warning: Unknown architecture $uname_m, assuming amd64." >&2 ;;
  esac

  # Find the actual git tag corresponding to the normalized version
  actual_tag=$(find_actual_github_tag "$version")
  # echo "DEBUG: Found actual tag: $actual_tag" >&2

  # Check architecture support using the actual tag
  if ! is_version_supported_for_arch "$actual_tag" "$arch_suffix"; then
    fail "Architecture ${os}${arch_suffix} is not supported in version $version (tag: $actual_tag). ARM64 support was added in v0.6.8 and later."
  fi

  # Construct asset filename part (e.g., "linux", "darwin_arm64")
  asset_os_arch="${os}${arch_suffix}"
  asset_filename="${TOOL_NAME}-${asset_os_arch}.tar.gz"
  # echo "DEBUG: Determined asset filename: ${asset_filename}" >&2

  # Construct the download URL
  url="$GH_REPO/releases/download/${actual_tag}/${asset_filename}"
  # echo "DEBUG: Constructed download URL: $url" >&2

  echo "* Downloading $TOOL_NAME release $version (${asset_os_arch})..."
  curl "${curl_opts[@]}" -o "$filename" -C - "$url" || fail "Could not download $url"

  # Note: Extraction is handled by bin/download script after this function returns
}

# Install the downloaded and extracted version
install_version() {
  local install_type="$1"
  local version="$2"                 # Normalized version
  local install_path="${3%/bin}/bin" # Target bin directory

  if [ "$install_type" != "version" ]; then
    fail "asdf-$TOOL_NAME supports release installs only"
  fi

  (
    mkdir -p "$install_path"
    # echo "DEBUG: Copying files from $ASDF_DOWNLOAD_PATH to $install_path" >&2

    # Expect bin/download to have extracted the contents into ASDF_DOWNLOAD_PATH
    # We need to copy everything from the download path to the install path
    # Use dotglob to copy hidden files too, if any (like .DS_Store, though unlikely needed)
    shopt -s dotglob
    cp -r "$ASDF_DOWNLOAD_PATH"/* "$install_path/" || fail "Failed to copy files from $ASDF_DOWNLOAD_PATH to $install_path"
    shopt -u dotglob

    # Assert the main tool executable exists.
    local tool_cmd_path="$install_path/$TOOL_NAME"
    # echo "DEBUG: Checking for executable at $tool_cmd_path" >&2
    if [ ! -f "$tool_cmd_path" ]; then
      # If not found directly, maybe it's in a subdirectory (less likely with --strip-components=1 in bin/download)
      local potential_executable
      potential_executable=$(find "$install_path" -maxdepth 2 -type f -name "$TOOL_NAME" | head -n 1)
      if [ -n "$potential_executable" ] && [ -f "$potential_executable" ]; then
        echo "Warning: Found executable in subdirectory: $potential_executable" >&2
        tool_cmd_path="$potential_executable"
        # If it was in a subdir, we might need to move it up or adjust path, but cp -r * should handle it?
      else
        fail "Executable '$TOOL_NAME' not found in install path '$install_path' after copying."
      fi
    fi

    # Ensure the main binary is executable
    # echo "DEBUG: Making $tool_cmd_path executable..." >&2
    chmod +x "$tool_cmd_path" || fail "Failed to make $tool_cmd_path executable."

    # Test the executable
    # echo "DEBUG: Verifying installation with '$TOOL_TEST'..." >&2
    "$tool_cmd_path" --help >/dev/null 2>&1 || fail "Execution check failed for $tool_cmd_path --help"
    # Alternative using TOOL_TEST variable:
    # (
    #   export PATH="$install_path:$PATH"
    #   $TOOL_TEST > /dev/null 2>&1 || fail "Tool test command '$TOOL_TEST' failed."
    # )

    echo "$TOOL_NAME $version installation was successful!"
  ) || (
    rm -rf "$install_path"
    fail "An error occurred while installing $TOOL_NAME $version."
  )
}
