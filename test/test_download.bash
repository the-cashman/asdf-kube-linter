#!/usr/bin/env bash

set -euo pipefail # Re-enable exit on error, unset var; pipefail
set -x            # Enable command tracing

# --- Configuration ---
# Get the directory of the currently executing script
current_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Navigate up one level to the project root
project_root=$(cd "$current_script_dir/.." && pwd)
# Source the utils script relative to the project root
echo "DEBUG [test_download]: Sourcing ${project_root}/lib/utils.bash..." >&2
# shellcheck source=../lib/utils.bash
source "${project_root}/lib/utils.bash" || { echo "ERROR [test_download]: Failed to source lib/utils.bash"; exit 1; }
echo "DEBUG [test_download]: Sourcing complete." >&2

# Versions to test
OLD_VERSION="0.6.7" # Pre-ARM64 support
NEW_VERSION="0.7.0" # Post-ARM64 support

# Temporary directory for downloads
TEST_DOWNLOAD_DIR="${project_root}/test/tmp_download"

# Counter for test results
tests_run=0
tests_passed=0
tests_failed=0

# --- Helper Functions ---

# Function to run a single test case
# Arguments: $1: Expected outcome (0 for success, 1 for failure)
#            $2: Version to test (e.g., 0.6.7)
#            $3: OS (uname -s: Linux or Darwin)
#            $4: Arch (uname -m: x86_64 or arm64)
#            $5: Test description
run_test() {
    echo "DEBUG [run_test]: Entering function..." >&2
    local expected_outcome="$1"
    echo "DEBUG [run_test]: Assigned expected_outcome=$expected_outcome" >&2
    local version="$2"
    echo "DEBUG [run_test]: Assigned version=$version" >&2
    local os="$3"
    echo "DEBUG [run_test]: Assigned os=$os" >&2
    local arch="$4"
    echo "DEBUG [run_test]: Assigned arch=$arch" >&2
    local description="$5"
    echo "DEBUG [run_test]: Assigned description=$description" >&2
    local test_result="FAIL"
    local exit_code=0

    echo "DEBUG [run_test]: Incrementing tests_run (current value: $tests_run)" >&2
    # ((tests_run++)) # Original increment
    tests_run=$((tests_run + 1)) # Alternative increment
    echo "DEBUG [run_test]: Incremented tests_run (new value: $tests_run)" >&2

    echo "--------------------------------------------------"
    echo "Running test: $description"
    echo "Version: $version, OS: $os, Arch: $arch, Expected: $( [ "$expected_outcome" -eq 0 ] && echo "Success" || echo "Failure" )"

    # Set environment variables for the download function
    export ASDF_TEST_UNAME_S="$os"
    export ASDF_TEST_UNAME_M="$arch"
    export ASDF_DOWNLOAD_PATH="$TEST_DOWNLOAD_DIR"

    # Create a unique filename for this test's download attempt
    local download_filename="${TEST_DOWNLOAD_DIR}/${TOOL_NAME}-${version}-${os}-${arch}.tar.gz"
    mkdir -p "$TEST_DOWNLOAD_DIR" # Ensure download dir exists

    # Execute the download function, capturing output and exit code
    # Use a subshell to isolate environment variables if needed, though export works globally here.
    set +e # Temporarily disable exit on error to capture the exit code
    download_release "$version" "$download_filename" > /dev/null 2>&1
    exit_code=$?
    set -e # Re-enable exit on error

    # Check the result
    if [[ "$exit_code" -eq "$expected_outcome" ]]; then
        test_result="PASS"
        ((tests_passed++))
        # If success was expected, check if the file was actually created (basic check)
        if [[ "$expected_outcome" -eq 0 ]] && [[ ! -f "$download_filename" ]]; then
             echo "  WARN: Expected success, but download file '$download_filename' not found."
             # Optionally mark as fail? For now, just warn.
        fi
    else
        ((tests_failed++))
        echo "  ERROR: Test failed. Expected exit code $expected_outcome, but got $exit_code."
    fi

    echo "Result: $test_result"

    # Clean up the specific download file and potentially the dir if empty
    rm -f "$download_filename"
    # Optional: rmdir "$TEST_DOWNLOAD_DIR" 2>/dev/null # Remove dir if empty

    # Unset env vars for safety, although next test will overwrite
    unset ASDF_TEST_UNAME_S
    unset ASDF_TEST_UNAME_M
    unset ASDF_DOWNLOAD_PATH
}

# --- Test Execution ---

echo "Starting download_release tests..."
# Clean up any previous test runs
echo "DEBUG [test_download]: Cleaning up previous test directory: $TEST_DOWNLOAD_DIR" >&2
rm -rf "$TEST_DOWNLOAD_DIR"
mkdir -p "$TEST_DOWNLOAD_DIR"
echo "DEBUG [test_download]: Starting test loop..." >&2

# --- Old Version Tests (v0.6.7) ---
run_test 0 "$OLD_VERSION" "Linux"  "x86_64" "Old version ($OLD_VERSION), Linux, amd64 (Expect Success)"
run_test 1 "$OLD_VERSION" "Linux"  "arm64"  "Old version ($OLD_VERSION), Linux, arm64 (Expect Failure - Unsupported Arch)"
run_test 0 "$OLD_VERSION" "Darwin" "x86_64" "Old version ($OLD_VERSION), Darwin, amd64 (Expect Success)"
run_test 1 "$OLD_VERSION" "Darwin" "arm64"  "Old version ($OLD_VERSION), Darwin, arm64 (Expect Failure - Unsupported Arch)"

# --- Older Version Tests (0.5.0 - No 'v' tag) ---
OLDER_VERSION="0.5.0"
run_test 0 "$OLDER_VERSION" "Linux"  "x86_64" "Older version ($OLDER_VERSION), Linux, amd64 (Expect Success)"
run_test 1 "$OLDER_VERSION" "Linux"  "arm64"  "Older version ($OLDER_VERSION), Linux, arm64 (Expect Failure - Unsupported Arch)"
run_test 0 "$OLDER_VERSION" "Darwin" "x86_64" "Older version ($OLDER_VERSION), Darwin, amd64 (Expect Success)"
run_test 1 "$OLDER_VERSION" "Darwin" "arm64"  "Older version ($OLDER_VERSION), Darwin, arm64 (Expect Failure - Unsupported Arch)"

# --- New Version Tests (v0.7.0) ---
run_test 0 "$NEW_VERSION" "Linux"  "x86_64" "New version ($NEW_VERSION), Linux, amd64 (Expect Success)"
run_test 0 "$NEW_VERSION" "Linux"  "arm64"  "New version ($NEW_VERSION), Linux, arm64 (Expect Success)"
run_test 0 "$NEW_VERSION" "Darwin" "x86_64" "New version, Darwin, amd64 (Expect Success)"
run_test 0 "$NEW_VERSION" "Darwin" "arm64"  "New version, Darwin, arm64 (Expect Success)"

# --- Test Summary ---
echo "--------------------------------------------------"
echo "Test Summary:"
echo "Total tests run: $tests_run"
echo "Passed: $tests_passed"
echo "Failed: $tests_failed"
echo "--------------------------------------------------"

# Clean up the main test download directory
rm -rf "$TEST_DOWNLOAD_DIR"

# Exit with appropriate code
if [[ "$tests_failed" -gt 0 ]]; then
    echo "Some tests failed!"
    exit 1
else
    echo "All tests passed!"
    exit 0
fi