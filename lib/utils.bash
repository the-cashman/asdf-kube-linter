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

# NOTE: You might want to remove this if <YOUR TOOL> is not hosted on GitHub releases.
if [ -n "${GITHUB_API_TOKEN:-}" ]; then
  curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

# Helper function to compare versions (handles semantic versioning)
# Usage: check_version_constraint "1.10.1" ">=" "1.9.0"
# Returns 0 (true) if constraint is met, 1 (false) otherwise
check_version_constraint() {
  local version1 operator version2
  version1="$1"
  operator="$2"
  version2="$3"

  # Pad versions with zeros for consistent comparison
  local v1_padded v2_padded
  v1_padded=$(printf "%-10s" "$version1" | sed 's/ /0/g')
  v2_padded=$(printf "%-10s" "$version2" | sed 's/ /0/g')

  # Use [[ ]] for more robust string comparison operators
  if [[ "$operator" == "==" ]]; then
    [[ "$v1_padded" == "$v2_padded" ]]
  elif [[ "$operator" == "!=" ]]; then
    [[ "$v1_padded" != "$v2_padded" ]]
  elif [[ "$operator" == ">" ]]; then
    [[ "$v1_padded" > "$v2_padded" ]]
  elif [[ "$operator" == ">=" ]]; then
    [[ "$v1_padded" > "$v2_padded" || "$v1_padded" == "$v2_padded" ]]
  elif [[ "$operator" == "<" ]]; then
    [[ "$v1_padded" < "$v2_padded" ]]
  elif [[ "$operator" == "<=" ]]; then
    [[ "$v1_padded" < "$v2_padded" || "$v1_padded" == "$v2_padded" ]]
  else
    fail "Invalid operator '$operator' in check_version_constraint"
    return 1 # Explicitly return non-zero on failure
  fi
  # The return status of the last [[ ]] command is used implicitly
}

# Helper function to determine the OS identifier used in asset names
get_os() {
  local os
  os="$(uname -s)"
  case "$os" in
  Linux) echo "linux" ;;
  Darwin) echo "darwin" ;;
  *) fail "Unsupported operating system: $os" ;;
  esac
}

# Helper function to determine the architecture identifier used in asset names
get_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
  x86_64 | amd64) echo "amd64" ;;
  arm64 | aarch64) echo "arm64" ;;
  *) fail "Unsupported architecture: $arch" ;;
  esac
}

sort_versions() {
  sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
    LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

# Fetches tags from the upstream kube-linter repo and filters for valid versions.
# Outputs versions *without* the 'v' prefix for asdf compatibility.
list_github_tags() {
  git ls-remote --tags --refs "$GH_REPO" |
    grep -o 'refs/tags/.*' | cut -d/ -f3- |
    # Filter potentially invalid tags (like signatures or non-version tags)
    grep -E '^(v)?[0-9]+\.[0-9]+\.[0-9]+$' |
    # Remove the 'v' prefix for sorting and asdf compatibility
    sed 's/^v//'
}

list_all_versions() {
  # List tags from the correct repository
  list_github_tags
}

# Determines the correct download URL, asset filename, and file extension
# based on version, OS, and architecture.
# Outputs: DOWNLOAD_URL ASSET_FILENAME EXTENSION
get_download_info() {
  local version os arch tag version_no_v asset_os asset_arch_suffix asset_ext filename url
  version="$1"
  os=$(get_os)
  arch=$(get_arch)

  # Strip 'v' prefix if present for version comparisons
  version_no_v="${version#v}"

  # 1. Determine TAG prefix
  if check_version_constraint "$version_no_v" ">=" "0.6.1"; then
    tag="v${version_no_v}"
  else
    tag="${version_no_v}"
  fi

  # 2. Determine Architecture Suffix
  asset_arch_suffix=""
  if [ "$arch" = "arm64" ]; then
    if check_version_constraint "$version_no_v" ">=" "0.6.8"; then
      asset_arch_suffix="_arm64"
    else
      fail "Error: arm64 builds are only available for kube-linter version 0.6.8 and later. Requested: $version"
    fi
  fi
  # Note: amd64 never has a suffix

  # 3. Determine OS identifier and Asset Extension based on OS and Version
  asset_os="$os"      # Default to 'linux' or 'darwin'
  asset_ext=".tar.gz" # Default extension

  if [ "$os" = "darwin" ]; then
    if check_version_constraint "$version_no_v" "<" "0.5.0"; then
      asset_ext=".tar.gz"
    elif check_version_constraint "$version_no_v" ">=" "0.5.0" && check_version_constraint "$version_no_v" "<" "0.6.8"; then
      # Between 0.5.0 and 0.6.7 (inclusive), Darwin uses a raw binary
      asset_ext=""
    else # >= 0.6.8
      asset_ext=".tar.gz"
    fi
  elif [ "$os" = "linux" ]; then
    # Linux always uses .tar.gz
    asset_ext=".tar.gz"
  # else # Windows - assuming .tar.gz based on previous discussion
  #   asset_os="windows"
  #   asset_ext=".tar.gz"
  fi

  # 4. Construct Filename and URL
  filename="${TOOL_NAME}-${asset_os}${asset_arch_suffix}${asset_ext}"
  url="${GH_REPO}/releases/download/${tag}/${filename}"

  # Output space-separated values for easy parsing in the calling script
  echo "$url $filename ${asset_ext}"
}

install_version() {
  local install_type="$1"
  local version="$2"
  local install_path="$3" # The full install path provided by asdf
  local bin_path="$install_path/bin"

  if [ "$install_type" != "version" ]; then
    fail "asdf-$TOOL_NAME supports release installs only"
  fi

  # Create the final bin directory
  mkdir -p "$bin_path" || fail "Could not create bin directory $bin_path"

  # Determine the expected source executable location in the download path
  local download_info source_executable download_filename download_ext
  # Call get_download_info again to determine if it was a raw binary or extracted archive
  download_info=$(get_download_info "$version")
  # shellcheck disable=SC2162 # We intentionally read into dummy vars
  read -r _ download_filename download_ext <<< "$download_info"

  if [ "$download_ext" = "" ]; then
    # Raw binary was downloaded, use its full name
    source_executable="$ASDF_DOWNLOAD_PATH/$download_filename"
  else
    # Archive was extracted, the binary should just be TOOL_NAME
    source_executable="$ASDF_DOWNLOAD_PATH/$TOOL_NAME"
  fi

  # Check if the determined source executable actually exists
  if [ ! -f "$source_executable" ]; then
    fail "Could not find executable '$source_executable' in download path '$ASDF_DOWNLOAD_PATH'."
  fi

  # Define the final destination path
  local final_executable="$bin_path/$TOOL_NAME"

  echo "* Moving $source_executable to $final_executable..."
  mv "$source_executable" "$final_executable" || fail "Could not move executable to $final_executable"

  echo "* Making $final_executable executable..."
  chmod +x "$final_executable" || fail "Could not make executable $final_executable"

  # Final verification
  local tool_cmd
  tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)" # Get base command name
  if [ ! -x "$bin_path/$tool_cmd" ]; then
     fail "Expected $bin_path/$tool_cmd to be executable after installation."
  fi

  echo "$TOOL_NAME $version installation successful!"
  # Cleanup of ASDF_DOWNLOAD_PATH is implicitly handled by asdf itself or bin/download removing the archive.
}
