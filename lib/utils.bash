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
  local os arch os_arch version_tag_v version_tag_no_v
  local asset_tarball asset_raw output_path_tarball output_path_raw
  local url_v_tar url_no_v_tar url_v_raw url_no_v_raw

  os=$(get_os) || exit 1
  arch=$(get_arch) || exit 1
  os_arch=$(get_release_asset_os_arch) || exit 1

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

  if curl --fail "${curl_opts[@]}" -o "$output_path_tarball" -C - "$url_v_tar"; then
    echo "$asset_tarball"
    return
  fi

  if curl --fail "${curl_opts[@]}" -o "$output_path_tarball" -C - "$url_no_v_tar"; then
    echo "$asset_tarball"
    return
  fi

  if curl --fail "${curl_opts[@]}" -o "$output_path_raw" -C - "$url_v_raw"; then
    echo "$asset_raw"
    return
  fi

  if curl --fail "${curl_opts[@]}" -o "$output_path_raw" -C - "$url_no_v_raw"; then
    echo "$asset_raw"
    return
  fi

  fail "Could not download $TOOL_NAME $requested_version. All attempts failed. Tried:\n  - $url_v_tar\n  - $url_no_v_tar\n  - $url_v_raw\n  - $url_no_v_raw"
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
    cp -a "$ASDF_DOWNLOAD_PATH"/.[!.]* "$ASDF_DOWNLOAD_PATH"/* "$install_path/" 2> /dev/null || cp -a "$ASDF_DOWNLOAD_PATH"/* "$install_path/" || fail "Failed to copy files to install path."

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
