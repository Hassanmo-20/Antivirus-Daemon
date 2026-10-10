#!/usr/bin/env bash
# ==============================================================================
# Restore Tool (restore.sh)
#
# Lab 2: Writing a Shell Script for a Simple Antivirus Daemon
# Author: Dr. Samia Hafez Lab Implementation
#
# Allows users to review quarantined files, restore false positives,
# or permanently delete genuine malicious files.
# ==============================================================================

set -u

# Argument validation
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <dir> <malicious_dir>" >&2
    exit 1
fi

DIR="$1"
MALICIOUS_DIR="$2"

# Whitelist file location (Bonus 2)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHITELIST_FILE="${WHITELIST_FILE:-$SCRIPT_DIR/.whitelist}"

# If malicious_dir does not exist or has no files at start
if [ ! -d "$MALICIOUS_DIR" ]; then
    echo "No malicious files to review."
    exit 0
fi

# Ensure target restoration directory exists
if [ ! -d "$DIR" ]; then
    mkdir -p "$DIR"
fi

# Function to add file to persistent whitelist
whitelist_file() {
    local fname="$1"
    mkdir -p "$(dirname "$WHITELIST_FILE")"
    if [ ! -f "$WHITELIST_FILE" ] || ! grep -Fxq "$fname" "$WHITELIST_FILE" 2>/dev/null; then
        echo "$fname" >> "$WHITELIST_FILE"
    fi
}

# Function to remove file from persistent whitelist
unwhitelist_file() {
    local fname="$1"
    if [ -f "$WHITELIST_FILE" ]; then
        # Escape special characters for regex deletion
        local escaped
        escaped=$(printf '%s\n' "$fname" | sed 's/[[\.*^$/]/\\&/g')
        sed -i "/^$escaped$/d" "$WHITELIST_FILE" 2>/dev/null || true
    fi
}

# Interactive review loop
while true; do
    # Collect files currently in quarantine
    files=()
    for f in "$MALICIOUS_DIR"/*; do
        [ -e "$f" ] || continue
        [ -f "$f" ] || continue
        files+=("$(basename "$f")")
    done

    # If no files remain
    if [ "${#files[@]}" -eq 0 ]; then
        echo "No malicious files to review."
        exit 0
    fi

    # Display list of quarantined files
    echo ""
    echo "Quarantined files in $MALICIOUS_DIR:"
    for i in "${!files[@]}"; do
        echo "$((i + 1))) ${files[i]}"
    done
    echo "0) Exit"

    # Prompt user to select a file
    echo -n "Select a file by number (1-${#files[@]}, or 0 to exit): "
    if ! read -r selection; then
        echo ""
        echo "Exiting restore tool."
        exit 0
    fi

    # Check for exit command
    if [[ "$selection" == "0" || "$selection" == "q" || "$selection" == "exit" ]]; then
        echo "Exiting restore tool."
        exit 0
    fi

    # Validate numeric choice
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#files[@]}" ]; then
        echo "Invalid selection. Please choose a number between 1 and ${#files[@]}."
        continue
    fi

    selected_file="${files[$((selection - 1))]}"

    # Action prompt for selected file
    echo ""
    echo "Selected file: $selected_file"
    echo "1) Restore this file back into $DIR (it was a false positive)"
    echo "2) Permanently delete this file from $MALICIOUS_DIR (it was genuinely malicious)"
    echo "3) Leave this file as-is and go back to the list"
    echo -n "Enter option [1-3]: "
    if ! read -r action; then
        echo ""
        echo "Exiting restore tool."
        exit 0
    fi

    case "$action" in
        1)
            # Restore file back into dir
            mv "$MALICIOUS_DIR/$selected_file" "$DIR/$selected_file"
            
            # Bonus 2: Whitelist file so subsequent scans do not flag it again
            whitelist_file "$selected_file"

            # Required terminal log format: "Restored <file> to <dir>."
            echo "Restored $selected_file to $DIR."
            ;;
        2)
            # Permanently delete file from malicious_dir
            rm -f "$MALICIOUS_DIR/$selected_file"

            # Remove from whitelist if previously tracked
            unwhitelist_file "$selected_file"

            # Required terminal log format: "<file> permanently deleted."
            echo "$selected_file permanently deleted."
            ;;
        3)
            # Leave file as-is and return to list
            echo "Left $selected_file as-is."
            ;;
        *)
            echo "Invalid option. Returning to list."
            ;;
    esac
done
