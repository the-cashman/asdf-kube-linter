#!/usr/bin/env bash

set -euo pipefail

GH_REPO="https://github.com/stackrox/kube-linter"
TOOL_NAME="kube-linter"
TOOL_TEST="kube-linter version"

fail() {
  echo -e "asdf-$TOOL_NAME: $*"
  exit 1
}

curl_opts=(-fsSL)

if [ -n "${GITHUB_API_TOKEN:-}" ]; then
  curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

# Helper function for version comparison (numeric)
# Returns 0 if v1 == v2, 1 if v1 > v2, 2 if v1 < v2
_version_compare() {
  # Use awk for robust comparison
  awk -v v1="$1" -v v2="$2" 'BEGIN {
    split(v1, a, "."); split(v2, b, ".");
    # Ensure we compare at least 3 parts (major.minor.patch)
    n = length(a) > length(b) ? length(a) : length(b);
    if (n < 3) n = 3;
    for (i=1; i<=n; i++) {
      # Treat empty parts as 0
      if (a[i] == "") a[i] = 0;
      if (b[i] == "") b[i] = 0;
      # Numeric comparison
      if (a[i] + 0 > b[i] + 0) exit 1; # v1 > v2
      if (a[i] + 0 < b[i] + 0) exit 2; # v1 < v2
    }
    exit 0; # v1 == v2
  }'
  return $?
}
get_os() {
  local os
  os=$(uname -s)
  case $os in
  Linux) echo "linux" ;;
  Darwin) echo "darwin" ;;
  *) fail "Unsupported operating system: $os" ;;
  esac
}

get_arch() {
  local arch
  arch=$(uname -m)
  case $arch in
  x86_64 | amd64) echo "amd64" ;;
  arm64 | aarch64) echo "arm64" ;;
  *) fail "Unsupported architecture: $arch" ;;
  esac
}

get_release_asset_os_arch() {
  local os arch arch_suffix
  os=$(get_os)
  arch=$(get_arch)

  if [ "$arch" == "arm64" ]; then
    arch_suffix="_arm64"
  else
    arch_suffix=""
  fi

  echo "${os}${arch_suffix}"
}

sort_versions() {
  sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
    LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

list_github_tags() {
  git ls-remote --tags --refs "$GH_REPO" |
    grep -o 'refs/tags/.*' | cut -d/ -f3- |
    sed 's/^v//'
}

list_all_versions() {
  list_github_tags
}

download_release() {
  local requested_version="$1"
  local download_dir="$2"
  local os arch version_tag asset_name asset_suffix asset_format download_url output_path final_asset_name compare_result arch_suffix

  os=$(get_os) || exit 1
  arch=$(get_arch) || exit 1

  # Determine version tag prefix (v or no v) based on version >= 0.6.1
  _version_compare "$requested_version" "0.6.1"
  compare_result=$?
  if [[ "$compare_result" -eq 0 || "$compare_result" -eq 1 ]]; then # version >= 0.6.1
    version_tag="v${requested_version}"
  else # version < 0.6.1
    version_tag="${requested_version}"
  fi

  # Determine asset format (tar.gz or raw) based on version and OS
  asset_format=""
  asset_suffix=""
  _version_compare "$requested_version" "0.5.0"
  compare_result_050=$?
  _version_compare "$requested_version" "0.6.8"
  compare_result_068=$?

  if [[ "$compare_result_050" -eq 2 ]]; then # version < 0.5.0 (Assume tar.gz for early versions based on 0.0.2+)
    asset_format="tar.gz"
    asset_suffix=".tar.gz"
  elif [[ "$compare_result_068" -eq 2 ]]; then # version >= 0.5.0 AND version < 0.6.8
    if [ "$os" == "linux" ]; then
      asset_format="tar.gz"
      asset_suffix=".tar.gz"
    elif [ "$os" == "darwin" ]; then
      asset_format="raw"
      asset_suffix="" # No extension for raw binary
    else
      # Default or handle other OS if necessary, for now assume tar.gz might exist
      asset_format="tar.gz"
      asset_suffix=".tar.gz"
    fi
  else # version >= 0.6.8
    asset_format="tar.gz"
    asset_suffix=".tar.gz"
  fi

  # Determine architecture suffix and check compatibility (arm64 available >= 0.6.8)
  arch_suffix=""
  if [ "$arch" == "arm64" ]; then
    _version_compare "$requested_version" "0.6.8"
    compare_result=$?
    if [[ "$compare_result" -eq 0 || "$compare_result" -eq 1 ]]; then # version >= 0.6.8
      arch_suffix="_arm64"
    else # version < 0.6.8
      fail "Architecture 'arm64' is not supported for ${TOOL_NAME} version ${requested_version} (requires version >= 0.6.8)."
    fi
  fi

  # Construct final asset name
  asset_name="${TOOL_NAME}-${os}${arch_suffix}"
  final_asset_name="${asset_name}${asset_suffix}"

  # Construct download URL and output path
  download_url="${GH_REPO}/releases/download/${version_tag}/${final_asset_name}"
  output_path="${download_dir}/${final_asset_name}"

  # Log download attempt details to stderr
  echo "Downloading ${TOOL_NAME} ${requested_version} (${final_asset_name}) for ${os}/${arch}..." >&2
  echo "URL: ${download_url}" >&2

  # Attempt download using determined URL
  if curl --fail "${curl_opts[@]}" -o "$output_path" -C - "$download_url"; then
    echo "$final_asset_name" # Output filename to stdout for the calling script (bin/download)
    return 0
  else
    # Clean up potentially partial download file if it exists
    if [ -f "$output_path" ]; then
      rm "$output_path"
    fi
    fail "Download failed for ${TOOL_NAME} ${requested_version} from ${download_url}. Please check the version exists, the URL is correct, and your network connection."
  fi
}

install_version() {
  local install_type="$1"
  local version="$2"
  local install_path="$3"
  local bin_path="${install_path}/bin"
  local source_executable_path target_executable_path potential_raw_name

  if [ "$install_type" != "version" ]; then
    fail "asdf-$TOOL_NAME supports release installs only"
  fi

  (
    mkdir -p "$install_path"
    cp -a "$ASDF_DOWNLOAD_PATH"/.[!.]* "$ASDF_DOWNLOAD_PATH"/* "$install_path/" 2>/dev/null || cp -a "$ASDF_DOWNLOAD_PATH"/* "$install_path/" || fail "Failed to copy files to install path."

    mkdir -p "$bin_path"

    potential_raw_name="${TOOL_NAME}-$(get_release_asset_os_arch)"
    source_executable_path=""

    if [ -f "${install_path}/${potential_raw_name}" ]; then
      source_executable_path="${install_path}/${potential_raw_name}"
    elif [ -f "${install_path}/${TOOL_NAME}" ]; then
      source_executable_path="${install_path}/${TOOL_NAME}"
    else
      fail "Could not find '$TOOL_NAME' or '$potential_raw_name' executable in '$install_path' after copying."
    fi

    target_executable_path="${bin_path}/${TOOL_NAME}"

    if [ "$source_executable_path" != "$target_executable_path" ]; then
      mv "$source_executable_path" "$target_executable_path" || fail "Failed to move executable to bin directory."
    fi

    chmod +x "$target_executable_path" || fail "Could not set executable permission."

    local args
    args=$(echo "$TOOL_TEST" | cut -d' ' -f2-)

    test -x "$target_executable_path" || fail "Expected $target_executable_path to be executable."

    "$target_executable_path" "$args" || fail "'${TOOL_TEST}' command failed."

  ) || (
    rm -rf "$install_path"
    fail "An error occurred while installing $TOOL_NAME $version."
  )
}
