#!/usr/bin/env bash

set -euo pipefail

# Ensure asdf is available
if ! command -v asdf &>/dev/null; then
    echo "ERROR: asdf command not found. Please install asdf or source asdf.sh"
    exit 1
fi

# Get the directory of the script itself
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
PLUGIN_DIR=$(dirname "$SCRIPT_DIR") # Assumes test dir is one level down from plugin root
PLUGIN_NAME="kube-linter"
TEST_COMMAND="kube-linter version" # Basic command to check if the tool runs

echo "--- Starting asdf-kube-linter version tests ---"
echo "Plugin directory: $PLUGIN_DIR"
echo "Plugin name: $PLUGIN_NAME"

# --- Test Function ---
run_test() {
    local version_to_test="$1"
    echo ""
    echo "--- Testing version: $version_to_test ---"
    if asdf plugin test "$PLUGIN_NAME" "$PLUGIN_DIR" --asdf-tool-version "$version_to_test" "$TEST_COMMAND"; then
        echo "✅ SUCCESS: Test passed for version $version_to_test"
        # Clean up installed version to avoid conflicts if needed (optional)
        # asdf uninstall $PLUGIN_NAME $version_to_test
        return 0
    else
        echo "❌ FAILED: Test failed for version $version_to_test"
        return 1
    fi
}

# --- Run Tests ---
# Test a version that originally had a 'v' prefix (e.g., v0.6.1)
run_test "0.6.1"
test1_status=$?

# Test a version that originally did NOT have a 'v' prefix (e.g., 0.1.0)
run_test "0.1.0"
test2_status=$?

# --- Summary ---
echo ""
echo "--- Test Summary ---"
if [ $test1_status -eq 0 ] && [ $test2_status -eq 0 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed."
    exit 1
fi
