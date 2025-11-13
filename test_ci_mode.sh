#!/bin/bash

# Test CI/CD Mode Script
# This script simulates CI/CD environment by setting RP_LAUNCH_UUID
# and running tests with parallel execution enabled.

set -e  # Exit on error

echo "=========================================="
echo "Testing CI/CD Mode for ReportPortal Agent"
echo "=========================================="
echo ""

# Generate a unique UUID for this test run (simulates CI/CD pipeline)
export RP_LAUNCH_UUID=$(uuidgen)
echo "🚀 Launch UUID (shared across all workers): $RP_LAUNCH_UUID"
echo "📋 This UUID will be used by ALL parallel test workers"
echo ""

# Check if ReportPortal credentials are configured
echo "🔍 Checking ReportPortal configuration in ExampleUITests/Info.plist..."
RP_URL=$(defaults read "$(pwd)/ExampleUITests/Info.plist" ReportPortalURL 2>/dev/null || echo "NOT_SET")
RP_PROJECT=$(defaults read "$(pwd)/ExampleUITests/Info.plist" ReportPortalProjectName 2>/dev/null || echo "NOT_SET")
RP_TOKEN=$(defaults read "$(pwd)/ExampleUITests/Info.plist" ReportPortalToken 2>/dev/null || echo "NOT_SET")

if [[ "$RP_URL" == *"localhost"* ]] || [[ "$RP_PROJECT" == *"project name"* ]] || [[ "$RP_TOKEN" == *"token"* ]]; then
    echo "⚠️  WARNING: ReportPortal credentials appear to be placeholders!"
    echo "   URL: $RP_URL"
    echo "   Project: $RP_PROJECT"
    echo "   Token: ${RP_TOKEN:0:20}..."
    echo ""
    echo "   The agent will run but data won't reach ReportPortal."
    echo "   Update ExampleUITests/Info.plist with real credentials to test fully."
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "✅ Running UI tests with 2 parallel workers..."
echo ""

# CRITICAL: xcodebuild doesn't automatically pass all environment variables to test processes
# We need to ensure RP_LAUNCH_UUID is available to the test runner
# Option 1: Use env command to explicitly set it
# Option 2: Add to test plan (requires editing Example.xctestplan)
# Using env command here for CI/CD compatibility

# Run tests with parallel execution
# The output is saved to a log file for analysis
env RP_LAUNCH_UUID="$RP_LAUNCH_UUID" xcodebuild test \
  -scheme Example \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -parallel-testing-enabled YES \
  -maximum-parallel-testing-workers 2 \
  -only-testing:ExampleUITests \
  2>&1 | tee /tmp/rp_ci_test.log

echo ""
echo "=========================================="
echo "Test Execution Complete - Analyzing Logs"
echo "=========================================="
echo ""

# Analyze the logs
echo "=== 1. CI/CD Mode Detection ===" echo ""
if grep -q "CI Mode" /tmp/rp_ci_test.log; then
    echo "✅ CI/CD Mode detected!"
    grep "CI Mode" /tmp/rp_ci_test.log | head -3
else
    echo "❌ CI/CD Mode NOT detected (should see '[CI Mode]' in logs)"
    echo "Checking for Local Mode instead..."
    grep "Local Mode" /tmp/rp_ci_test.log | head -3 || echo "No mode logs found"
fi

echo ""
echo "=== 2. Parallel Worker Detection ==="
echo ""
CLONE_COUNT=$(grep -c "Clone [0-9]" /tmp/rp_ci_test.log || echo "0")
if [[ $CLONE_COUNT -gt 1 ]]; then
    echo "✅ Multiple workers detected ($CLONE_COUNT worker instances)"
    grep "Clone [0-9]" /tmp/rp_ci_test.log | head -10
else
    echo "⚠️  Only 1 worker detected (expected 2 with -maximum-parallel-testing-workers 2)"
    grep "Clone [0-9]" /tmp/rp_ci_test.log | head -5 || echo "No Clone logs found"
fi

echo ""
echo "=== 3. Launch Coordination (409 Conflict) ==="
echo ""
if grep -q "409" /tmp/rp_ci_test.log; then
    echo "✅ 409 Conflict detected (expected when worker 2 joins worker 1's launch)"
    grep "409" /tmp/rp_ci_test.log | head -5
else
    echo "ℹ️  No 409 Conflict found (may indicate only 1 worker created the launch)"
fi

echo ""
echo "=== 4. Test Suites Executed ==="
echo ""
grep "Test suite.*started" /tmp/rp_ci_test.log | head -10 || echo "No test suites found in logs"

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Launch UUID used: $RP_LAUNCH_UUID"
echo "Full log saved to: /tmp/rp_ci_test.log"
echo ""
echo "Next steps:"
echo "1. Check your ReportPortal instance for a launch with UUID: $RP_LAUNCH_UUID"
echo "2. Verify all test results from both workers appear in ONE launch"
echo "3. Review /tmp/rp_ci_test.log for detailed execution logs"
echo ""
