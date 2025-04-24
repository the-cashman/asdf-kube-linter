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

list_github_tags() {
  git ls-remote --tags --refs "$GH_REPO" |
    grep -o 'refs/tags/.*' | cut -d/ -f3- |
    sed 's/^v//'
}

list_all_versions() {
  list_github_tags
}

download_release() {
  local version="$1"
  local filename="$2"

  local uname_s uname_m os arch_suffix url url_with_v url_without_v
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"

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
  esac

  # For Windows, use .exe extension
  if [[ "$os" == "windows" ]]; then
    if [[ -n "$arch_suffix" ]]; then
      os="${TOOL_NAME}${arch_suffix}.exe"
    else
      os="${TOOL_NAME}.exe"
    fi
  else
    os="${os}${arch_suffix}"
  fi

  # Try both URL formats (with and without 'v' prefix)
  url_with_v="$GH_REPO/releases/download/v${version}/kube-linter-${os}.tar.gz"
  url_without_v="$GH_REPO/releases/download/${version}/kube-linter-${os}.tar.gz"

  echo "* Downloading $TOOL_NAME release $version for ${os}..."

  # First try with 'v' prefix
  if curl -f -I "${curl_opts[@]}" "$url_with_v" &> /dev/null; then
    url="$url_with_v"
  else
    # If that fails, try without 'v' prefix
    url="$url_without_v"
  fi

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

    echo "$TOOL_NAME $version installation was successful!"
  ) || (
    rm -rf "$install_path"
    fail "An error ocurred while installing $TOOL_NAME $version."
  )
}
