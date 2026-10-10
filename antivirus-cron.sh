#!/usr/bin/env bash
# ==============================================================================
# Antivirus Cron Worker (antivirus-cron.sh)
#
# Lab 2: Writing a Shell Script for a Simple Antivirus Daemon (Bonus 1)
# Author: Dr. Samia Hafez Lab Implementation
#
# Designed to be executed periodically by the cron daemon.
# Performs change detection, directory scanning, and quarantine of malicious files.
# ==============================================================================

set -u

# ==============================================================================
# MALICIOUS DETECTION CONFIGURATION
# Defined here as required by the specification. Documented in README.md.
# These lists are hardcoded exactly as required by the lab specification.
# ==============================================================================
FLAGGED_EXTENSIONS=(".exe" ".bat" ".vbs" ".scr" ".ps1")
FLAGGED_KEYWORDS=("virus" "trojan" "malware" "worm" "ransomware")
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Arguments or default paths
DIR="${1:-$SCRIPT_DIR/monitored_dir}"
MALICIOUS_DIR="${2:-$SCRIPT_DIR/malicious_dir}"

# Ensure directories exist
if [ ! -d "$DIR" ]; then
    mkdir -p "$DIR"
fi
mkdir -p "$MALICIOUS_DIR"

# Snapshot filenames
INFO_LAST="$SCRIPT_DIR/directory-info.last"
INFO_NEW="$SCRIPT_DIR/directory-info.new"

# Whitelist file location (Bonus 2)
WHITELIST_FILE="${WHITELIST_FILE:-$SCRIPT_DIR/.whitelist}"

# Clean up temporary snapshot file on exit/interrupt
cleanup() {
    rm -f "$INFO_NEW"
}
trap cleanup EXIT SIGINT SIGTERM

# Check if a filename is in the persistent whitelist (Bonus 2)
is_whitelisted() {
    local fname="$1"
    if [ -f "$WHITELIST_FILE" ]; then
        if grep -Fxq "$fname" "$WHITELIST_FILE" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Check if file has a flagged extension (case-insensitive)
is_flagged_extension() {
    local fname="$1"
    local lower_name
    lower_name=$(echo "$fname" | tr '[:upper:]' '[:lower:]')
    for ext in "${FLAGGED_EXTENSIONS[@]}"; do
        local lower_ext
        lower_ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_name" == *"$lower_ext" ]]; then
            return 0
        fi
    done
    return 1
}

# Check if file content contains any flagged keywords (case-insensitive)
is_flagged_content() {
    local fpath="$1"
    if [ ! -s "$fpath" ] || [ ! -r "$fpath" ]; then
        return 1
    fi
    for kw in "${FLAGGED_KEYWORDS[@]}"; do
        if grep -i -q "$kw" "$fpath" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# Scan dir and quarantine any malicious files
scan_directory() {
    local file_path
    local filename

    for file_path in "$DIR"/*; do
        [ -e "$file_path" ] || continue
        [ -f "$file_path" ] || continue

        filename=$(basename "$file_path")

        # Skip whitelisted files (Bonus 2)
        if is_whitelisted "$filename"; then
            continue
        fi

        local is_malicious=false

        if is_flagged_extension "$filename"; then
            is_malicious=true
        elif is_flagged_content "$file_path"; then
            is_malicious=true
        fi

        if [ "$is_malicious" = true ]; then
            # Action on Detection:
            # 1. Print: "<file> is malicious and it is DELETED"
            # 2. Copy the file into malicious_dir, keeping its original filename
            # 3. Delete the original file from dir
            echo "$filename is malicious and it is DELETED"
            cp "$file_path" "$MALICIOUS_DIR/$filename"
            rm -f "$file_path"
        fi
    done
}

# ------------------------------------------------------------------------------
# Single-Pass Change Detection (Invoked by cron on schedule)
# ------------------------------------------------------------------------------
if [ ! -f "$INFO_LAST" ]; then
    # First execution: scan immediately and record baseline snapshot
    scan_directory
    ls -l "$DIR" > "$INFO_LAST"
else
    # Subsequent executions: take new snapshot and compare against last
    ls -l "$DIR" > "$INFO_NEW"
    if ! cmp -s "$INFO_LAST" "$INFO_NEW"; then
        scan_directory
        cp "$INFO_NEW" "$INFO_LAST"
    fi
fi
