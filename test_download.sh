#!/usr/bin/env bash

set -euo pipefail

# Source the utils.bash file
source "./lib/utils.bash"

# Set up logging
log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*"
}

error() {
  log "ERROR: $*" >&2
}

# Detect system architecture
detect_arch() {
  local uname_s uname_m os arch_suffix
  uname_s="$(uname -s)"
  uname_m="$(uname -m)"

  # Determine OS
  case "$uname_s" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    MINGW* | MSYS* | CYGWIN*) os="windows" ;;
    *)
      error "OS not supported: $uname_s"
      return 1
      ;;
  esac

  # Determine architecture suffix
  arch_suffix=""
  case "$uname_m" in
    arm64 | aarch64) arch_suffix="_arm64" ;;
  esac

  echo "${os}${arch_suffix}"
}

# Get current architecture
CURRENT_ARCH=$(detect_arch)
log "Detected architecture: $CURRENT_ARCH"

# Handle cleanup on exit
cleanup() {
  if [[ -d "${temp_dir:-}" ]]; then
    log "Cleaning up temporary directory: $temp_dir"
    rm -rf "$temp_dir"
  fi
}

trap cleanup EXIT

# Create a temporary directory for testing
temp_dir=$(mktemp -d)
log "Created temporary directory: $temp_dir"

# Function to test a specific version
test_version() {
  local version=$1
  local arch=${2:-$CURRENT_ARCH}
  local release_file="$temp_dir/kube-linter-$version.tar.gz"

  log "Testing download of version: $version for architecture: $arch"

  # Download the release
  if ! download_release "$version" "$release_file" 2> /tmp/download_error; then
    error "Failed to download version $version for architecture $arch"
    cat /tmp/download_error >&2
    return 1
  fi

  # Check if the download was successful
  if [[ -f "$release_file" ]]; then
    log "Download successful: $release_file"
    ls -la "$release_file"

    # Create a temporary directory for extraction
    local extract_dir="$temp_dir/extract-$version"
    mkdir -p "$extract_dir"

    # Verify the archive is valid and extract it
    if tar -xzf "$release_file" -C "$extract_dir"; then
      log "Archive extraction successful for version $version"

      # Check if the binary exists
      if [[ -f "$extract_dir/kube-linter" ]]; then
        log "Binary verification successful for version $version"

        # For non-Windows platforms, check if the binary is executable
        if [[ "$arch" != windows* ]]; then
          if [[ -x "$extract_dir/kube-linter" ]]; then
            log "Binary is executable for version $version"
          else
            error "Binary is not executable for version $version"
            return 1
          fi
        fi

        # Optional: Run the binary with --version to verify it works
        # This is commented out because it might not work in all CI environments
        # if "$extract_dir/kube-linter" --version &>/dev/null; then
        #   log "Binary execution successful for version $version"
        # else
        #   error "Binary execution failed for version $version"
        #   return 1
        # fi

        # Clean up extraction directory
        rm -rf "$extract_dir"
        return 0
      else
        error "Binary not found in archive for version $version"
        return 1
      fi
    else
      error "Downloaded archive is corrupted for version $version"
      return 1
    fi
  else
    error "Download failed for version $version (file not found)"
    return 1
  fi
}

# Function to print usage
usage() {
  echo "Usage: $0 [options] [version1 version2 ...]"
  echo ""
  echo "Options:"
  echo "  --arch ARCH     Test specific architecture (darwin, darwin_arm64, linux, linux_arm64, windows)"
  echo "  --all-archs     Test all supported architectures"
  echo "  --help          Show this help message"
  echo ""
  echo "If no versions are provided, tests will run on versions 0.7.2 and 0.2.0"
  echo "If no architecture is specified, tests will run on the current architecture"
}

# Parse command line arguments
test_archs=()
test_versions=()
test_all_archs=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      test_archs+=("$2")
      shift 2
      ;;
    --all-archs)
      test_all_archs=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    -*)
      error "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      test_versions+=("$1")
      shift
      ;;
  esac
done

# If no versions specified, use defaults
if [[ ${#test_versions[@]} -eq 0 ]]; then
  test_versions=("0.7.2" "0.2.0")
fi

# If no architectures specified and not testing all, use current
if [[ ${#test_archs[@]} -eq 0 && "$test_all_archs" == "false" ]]; then
  test_archs=("$CURRENT_ARCH")
fi

# If testing all architectures, define the list
if [[ "$test_all_archs" == "true" ]]; then
  test_archs=("darwin" "darwin_arm64" "linux" "linux_arm64" "windows")
fi

# Run the tests
failed=0
for arch in "${test_archs[@]}"; do
  for version in "${test_versions[@]}"; do
    log "=== Testing version $version on architecture $arch ==="
    if [[ "$arch" == "$CURRENT_ARCH" ]]; then
      # For current architecture, we can do a full test
      if ! test_version "$version" "$arch"; then
        failed=1
      fi
    else
      # For other architectures, we need to override the OS/arch detection
      # This is a simulated test that verifies URL construction but doesn't verify binary execution
      log "Simulating test for non-native architecture: $arch"

      # Override the OS and architecture for the download_release function
      # This is a bit hacky but allows us to test URL construction for different architectures
      original_uname_s=$(uname -s)
      original_uname_m=$(uname -m)

      # Override uname functions temporarily
      function uname() {
        case "$1" in
          -s)
            case "$arch" in
              darwin*) echo "Darwin" ;;
              linux*) echo "Linux" ;;
              windows*) echo "MINGW64_NT-10.0" ;;
            esac
            ;;
          -m)
            case "$arch" in
              *_arm64) echo "arm64" ;;
              *) echo "x86_64" ;;
            esac
            ;;
          *)
            command uname "$@"
            ;;
        esac
      }

      # Run the test with the overridden uname
      if ! test_version "$version" "$arch"; then
        failed=1
      fi

      # Restore original uname behavior
      unset -f uname
    fi
  done
done

if [[ $failed -eq 1 ]]; then
  error "One or more tests failed"
  exit 1
else
  log "All tests completed successfully"
fi
