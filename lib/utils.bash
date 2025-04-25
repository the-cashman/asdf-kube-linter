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

# Returns 0 if v1 >= v2, 1 otherwise
check_min_version() {
  local v1=$1 v2=$2
  # Add trailing .0 if version is only X.Y
  [[ "$v1" =~ ^[0-9]+\.[0-9]+$ ]] && v1="${v1}.0"
  [[ "$v2" =~ ^[0-9]+\.[0-9]+$ ]] && v2="${v2}.0"

  # Check if versions are in X.Y.Z format
  if ! [[ "$v1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || ! [[ "$v2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Warning: Invalid version format for comparison: $v1, $v2" >&2
    # Default to assuming v1 is sufficient if format is invalid
    return 0
  fi

  local i v1_parts v2_parts
  # Use read -ra for robust splitting based on IFS
  IFS=. read -ra v1_parts <<< "$v1"
  IFS=. read -ra v2_parts <<< "$v2"

  # Fill empty fields in v1_parts with 0
  for ((i = ${#v1_parts[@]}; i < 3; i++)); do
    v1_parts[i]=0
  done
  # Fill empty fields in v2_parts with 0
  for ((i = ${#v2_parts[@]}; i < 3; i++)); do
    v2_parts[i]=0
  done

  for ((i = 0; i < 3; i++)); do
    # SC2004: $/${} is unnecessary on arithmetic variables.
    if ((v1_parts[i] < v2_parts[i])); then
      return 1
    fi
    if ((v1_parts[i] > v2_parts[i])); then
      return 0
    fi
  done
  return 0
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

# Determines the OS/Arch string used in kube-linter release assets
get_release_asset_os_arch() {
  local os arch arch_suffix
  os=$(get_os)
  arch=$(get_arch)

  # Default amd64 has no suffix in filename pre-arm64 support, but does after? Checking v0.7.2 assets...
  # v0.7.2 assets: kube-linter-darwin, kube-linter-darwin_arm64, kube-linter-linux, kube-linter-linux_arm64
  # It seems amd64 has *no* suffix, and arm64 uses _arm64. Let's assume this pattern.
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

# Downloads the correct release asset using fallbacks, printing the asset filename on success.
download_release() {
  local requested_version="$1"
  local download_dir="$2"
  local os arch os_arch version_tag_v version_tag_no_v
  local asset_tarball asset_raw output_path_tarball output_path_raw
  local url_v_tar url_no_v_tar url_v_raw url_no_v_raw
  local downloaded_asset_filename is_tarball download_url

  os=$(get_os) || exit 1
  arch=$(get_arch) || exit 1
  os_arch=$(get_release_asset_os_arch) || exit 1 # e.g., linux_arm64 or darwin

  # Check minimum version for arm64 support *before* attempting download
  if [ "$arch" == "arm64" ]; then
    if ! check_min_version "$requested_version" "0.6.8"; then
      fail "$TOOL_NAME version $requested_version does not support arm64 architecture. Minimum required is 0.6.8."
    fi
  fi

  asset_tarball="${TOOL_NAME}-${os_arch}.tar.gz"
  asset_raw="${TOOL_NAME}-${os_arch}"
  output_path_tarball="${download_dir}/${asset_tarball}"
  output_path_raw="${download_dir}/${asset_raw}"

  version_tag_v="v${requested_version}"
  version_tag_no_v="${requested_version}"

  url_v_tar="$GH_REPO/releases/download/${version_tag_v}/${asset_tarball}"
  url_no_v_tar="$GH_REPO/releases/download/${version_tag_no_v}/${asset_tarball}"
  url_v_raw="$GH_REPO/releases/download/${version_tag_v}/${asset_raw}"
  url_no_v_raw="$GH_REPO/releases/download/${version_tag_no_v}/${asset_raw}"

  echo "* Downloading $TOOL_NAME release $requested_version (${os_arch})..." >&2

  if curl --fail "${curl_opts[@]}" -o "$output_path_tarball" -C - "$url_v_tar"; then
    downloaded_asset_filename="$asset_tarball"
    is_tarball=true
    download_url="$url_v_tar"
  else
    if curl --fail "${curl_opts[@]}" -o "$output_path_tarball" -C - "$url_no_v_tar"; then
      downloaded_asset_filename="$asset_tarball"
      is_tarball=true
      download_url="$url_no_v_tar"
    else
      if curl --fail "${curl_opts[@]}" -o "$output_path_raw" -C - "$url_v_raw"; then
        downloaded_asset_filename="$asset_raw"
        is_tarball=false
        download_url="$url_v_raw"
      else
        if curl --fail "${curl_opts[@]}" -o "$output_path_raw" -C - "$url_no_v_raw"; then
          downloaded_asset_filename="$asset_raw"
          is_tarball=false
          download_url="$url_no_v_raw"
        else
          fail "Could not download $TOOL_NAME $requested_version. All attempts failed. Tried:\n  - $url_v_tar\n  - $url_no_v_tar\n  - $url_v_raw\n  - $url_no_v_raw"
        fi
      fi
    fi
  fi

  local output_path="${download_dir}/${downloaded_asset_filename}"

  if [ "$is_tarball" = true ]; then
    if ! file "$output_path" | grep -q 'gzip compressed data'; then
      rm -f "$output_path"
      fail "Download verification failed: File is not a gzip archive. URL: $download_url"
    fi
  else
    if ! file "$output_path" | grep -q 'executable' && [ ! -s "$output_path" ]; then
      rm -f "$output_path"
      fail "Download verification failed: File is empty or not recognized as executable. URL: $download_url"
    fi
  fi

  echo "$downloaded_asset_filename"
}

install_version() {
  local install_type="$1"
  local version="$2"
  local install_path="$3"
  local bin_path="${install_path}/bin"
  local found_executable target_executable_path

  if [ "$install_type" != "version" ]; then
    fail "asdf-$TOOL_NAME supports release installs only"
  fi

  (
    echo "* Installing $TOOL_NAME $version..." >&2

    mkdir -p "$install_path"
    cp -a "$ASDF_DOWNLOAD_PATH"/.[!.]* "$ASDF_DOWNLOAD_PATH"/* "$install_path/" 2> /dev/null || cp -a "$ASDF_DOWNLOAD_PATH"/* "$install_path/" || fail "Failed to copy files to install path."

    mkdir -p "$bin_path"

    # Find the main executable within the install path
    # Look for files named TOOL_NAME or TOOL_NAME-* that are executable files
    found_executable=$(find "$install_path" -maxdepth 2 -type f \( -name "$TOOL_NAME" -o -name "${TOOL_NAME}-*" \) -executable -print -quit)

    if [ -z "$found_executable" ]; then
      # If not found by executable flag (might not be set yet), try finding by name only
      found_executable=$(find "$install_path" -maxdepth 2 -type f \( -name "$TOOL_NAME" -o -name "${TOOL_NAME}-*" \) -print -quit)
      if [ -z "$found_executable" ]; then
        fail "Could not find '$TOOL_NAME' executable binary in '$install_path' after copying."
      fi
    fi

    target_executable_path="${bin_path}/${TOOL_NAME}"

    if [ "$found_executable" != "$target_executable_path" ]; then
      # Ensure parent dir exists just in case find went into a subdir like 'bin'
      mkdir -p "$(dirname "$target_executable_path")"
      mv "$found_executable" "$target_executable_path" || fail "Failed to move executable to bin directory."
    fi

    chmod +x "$target_executable_path" || fail "Could not set executable permission."

    # Verify installation using the test command defined in TOOL_TEST
    local args
    args=$(echo "$TOOL_TEST" | cut -d' ' -f2-) # Extract arguments, if any

    test -x "$target_executable_path" || fail "Expected $target_executable_path to be executable."

    # SC2086: Double quote args to prevent globbing and word splitting.
    "$target_executable_path" "$args" || fail "'${TOOL_TEST}' command failed."

    echo "$TOOL_NAME $version installation was successful!" >&2
  ) || (
    rm -rf "$install_path" # Clean up failed install
    fail "An error occurred while installing $TOOL_NAME $version."
  )
}
