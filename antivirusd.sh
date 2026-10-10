#!/usr/bin/env bash
# ==============================================================================
# Antivirus Daemon (antivirusd.sh)
#
# Lab 2: Writing a Shell Script for a Simple Antivirus Daemon
# Author: Dr. Samia Hafez Lab Implementation
#
# Monitors a directory for changes and quarantines malicious files.
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

# Argument validation
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <dir> <malicious_dir> <interval-secs>" >&2
    exit 1
fi

DIR="$1"
MALICIOUS_DIR="$2"
INTERVAL="$3"

# Validate monitored directory
if [ ! -d "$DIR" ]; then
    echo "Error: Directory '$DIR' does not exist." >&2
    exit 1
fi

# Validate interval
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -le 0 ]; then
    echo "Error: interval-secs must be a positive integer." >&2
    exit 1
fi

# Ensure malicious_dir exists
mkdir -p "$MALICIOUS_DIR"

# Snapshot filenames
INFO_LAST="directory-info.last"
INFO_NEW="directory-info.new"

# Whitelist file location (persisted in script directory or current directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHITELIST_FILE="${WHITELIST_FILE:-$SCRIPT_DIR/.whitelist}"

# Clean up temporary snapshot file on exit/interrupt
cleanup() {
    rm -f "$INFO_NEW"
    exit 0
}
trap cleanup SIGINT SIGTERM

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
        # If directory is empty, glob expands to literal "$DIR/*"
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
# Initial check: On the very first run, if directory-info.last does not exist,
# scan immediately and create directory-info.last from current state.
# ------------------------------------------------------------------------------
if [ ! -f "$INFO_LAST" ]; then
    scan_directory
    ls -l "$DIR" > "$INFO_LAST"
fi

# ------------------------------------------------------------------------------
# Monitoring loop: Poll every interval-secs
# ------------------------------------------------------------------------------
while true; do
    sleep "$INTERVAL"
    ls -l "$DIR" > "$INFO_NEW"

    # Compare snapshots using cmp
    if ! cmp -s "$INFO_LAST" "$INFO_NEW"; then
        scan_directory
        # Copy directory-info.new into directory-info.last as specified in lab overview
        cp "$INFO_NEW" "$INFO_LAST"
    fi
done
