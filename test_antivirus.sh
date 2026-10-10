#!/usr/bin/env bash
# ==============================================================================
# Automated Test Suite for Antivirus Daemon Lab
# ==============================================================================

set -e

PASSED=0
FAILED=0

assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $msg"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $msg (Expected: '$expected', Actual: '$actual')"
        FAILED=$((FAILED + 1))
    fi
}

assert_file_exists() {
    local file="$1"
    local msg="$2"
    if [ -f "$file" ]; then
        echo "  [PASS] $msg"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $msg (File '$file' does not exist)"
        FAILED=$((FAILED + 1))
    fi
}

assert_file_not_exists() {
    local file="$1"
    local msg="$2"
    if [ ! -f "$file" ]; then
        echo "  [PASS] $msg"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $msg (File '$file' should not exist)"
        FAILED=$((FAILED + 1))
    fi
}

# Setup test workspace
TEST_DIR="test_monitored"
TEST_QUARANTINE="test_quarantine"
rm -rf "$TEST_DIR" "$TEST_QUARANTINE" directory-info.last directory-info.new .whitelist
mkdir -p "$TEST_DIR" "$TEST_QUARANTINE"

echo "=== TEST 1: Parameter Validation ==="
set +e
output=$(bash ./antivirusd.sh 2>&1)
exit_code=$?
set -e
assert_equals 1 "$exit_code" "antivirusd.sh fails without arguments"

echo "=== TEST 2: Initial Run & Extension Detection ==="
# Create clean file and flagged extension files
echo "Clean document" > "$TEST_DIR/doc.txt"
echo "Binary executable" > "$TEST_DIR/payload.exe"
echo "Batch script" > "$TEST_DIR/script.bat"
echo "VBS script" > "$TEST_DIR/macro.vbs"
echo "Screen saver" > "$TEST_DIR/screensaver.scr"
echo "Powershell" > "$TEST_DIR/task.ps1"

# Run daemon in background for 3 seconds with 1 second interval
bash ./antivirusd.sh "$TEST_DIR" "$TEST_QUARANTINE" 1 &
DAEMON_PID=$!
sleep 2.5
kill $DAEMON_PID 2>/dev/null || true
wait $DAEMON_PID 2>/dev/null || true

assert_file_exists "$TEST_DIR/doc.txt" "Clean file remains in monitored dir"
assert_file_not_exists "$TEST_DIR/payload.exe" "payload.exe deleted from monitored dir"
assert_file_exists "$TEST_QUARANTINE/payload.exe" "payload.exe quarantined"
assert_file_exists "$TEST_QUARANTINE/script.bat" "script.bat quarantined"
assert_file_exists "$TEST_QUARANTINE/macro.vbs" "macro.vbs quarantined"
assert_file_exists "$TEST_QUARANTINE/screensaver.scr" "screensaver.scr quarantined"
assert_file_exists "$TEST_QUARANTINE/task.ps1" "task.ps1 quarantined"
assert_file_exists "directory-info.last" "directory-info.last created"

echo "=== TEST 3: Keyword Content Detection & Live Polling ==="
# Restart daemon with 1s interval
bash ./antivirusd.sh "$TEST_DIR" "$TEST_QUARANTINE" 1 &
DAEMON_PID=$!
sleep 1.5

# Drop a file with malicious keyword
echo "This file contains a secret VIRUS inside" > "$TEST_DIR/notes.txt"
echo "This file contains a Trojan horse" > "$TEST_DIR/readme.md"
echo "Clean file here" > "$TEST_DIR/safe.txt"

# Wait for daemon poll
sleep 2.5
kill $DAEMON_PID 2>/dev/null || true
wait $DAEMON_PID 2>/dev/null || true

assert_file_not_exists "$TEST_DIR/notes.txt" "notes.txt with 'VIRUS' deleted from monitored dir"
assert_file_exists "$TEST_QUARANTINE/notes.txt" "notes.txt quarantined"
assert_file_not_exists "$TEST_DIR/readme.md" "readme.md with 'Trojan' deleted from monitored dir"
assert_file_exists "$TEST_QUARANTINE/readme.md" "readme.md quarantined"
assert_file_exists "$TEST_DIR/safe.txt" "safe.txt remains in monitored dir"

echo "=== TEST 4: Restore Tool (restore.sh) ==="
# Test empty quarantine message
EMPTY_QUARANTINE="test_empty_q"
mkdir -p "$EMPTY_QUARANTINE"
output=$(bash ./restore.sh "$TEST_DIR" "$EMPTY_QUARANTINE")
assert_equals "No malicious files to review." "$output" "restore.sh handles empty quarantine"
rm -rf "$EMPTY_QUARANTINE"

# Test Option 1: Restore false positive (e.g. notes.txt)
# Feed selection '1' for file selection and choice '1' (restore), then '0' to exit
printf "1\n1\n0\n" | bash ./restore.sh "$TEST_DIR" "$TEST_QUARANTINE" > /dev/null 2>&1 || true

# Test Option 2: Permanently delete genuinely malicious file
printf "1\n2\n0\n" | bash ./restore.sh "$TEST_DIR" "$TEST_QUARANTINE" > /dev/null 2>&1 || true

echo "=== TEST 5: Whitelist Persistence Across Runs (Bonus 2) ==="
# Check whitelist exists and contains the restored file
assert_file_exists ".whitelist" "Whitelist file exists"

# Start daemon again. The restored file is in $TEST_DIR and matches a flagged extension/keyword.
# It should NOT be quarantined because it was whitelisted!
bash ./antivirusd.sh "$TEST_DIR" "$TEST_QUARANTINE" 1 &
DAEMON_PID=$!
sleep 2.5

# Drop a new genuinely malicious file to trigger change detection
echo "Another worm active" > "$TEST_DIR/worm_attack.txt"
sleep 3.5
kill $DAEMON_PID 2>/dev/null || true
wait $DAEMON_PID 2>/dev/null || true

# Worm should be quarantined
assert_file_exists "$TEST_QUARANTINE/worm_attack.txt" "worm_attack.txt was quarantined"
assert_file_not_exists "$TEST_DIR/worm_attack.txt" "worm_attack.txt was deleted"

echo "=== TEST 6: Cron Worker (antivirus-cron.sh) ==="
echo "ransomware payload" > "$TEST_DIR/bad_data.txt"
bash ./antivirus-cron.sh "$TEST_DIR" "$TEST_QUARANTINE"
assert_file_not_exists "$TEST_DIR/bad_data.txt" "antivirus-cron.sh detected and quarantined ransomware"
assert_file_exists "$TEST_QUARANTINE/bad_data.txt" "bad_data.txt in quarantine"

# Cleanup test directories
rm -rf "$TEST_DIR" "$TEST_QUARANTINE" directory-info.last directory-info.new .whitelist

echo "=========================================="
echo "TEST RESULTS: Passed: $PASSED, Failed: $FAILED"
echo "=========================================="

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
