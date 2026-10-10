# Simple Antivirus Daemon

A lightweight, automated Antivirus Daemon, Quarantine Review Tool, and Cron Monitor implemented in Bash and managed via GNU Make.

This project implements **Lab 2: Writing a Shell Script for a Simple Antivirus Daemon** (Dr. Samia Hafez).

---

## Table of Contents

- [Overview](#overview)
- [Folder Structure](#folder-structure)
- [Prerequisites & Ubuntu Installation](#prerequisites--ubuntu-installation)
- [Malicious File Classification Rules](#malicious-file-classification-rules)
  - [Location in Source Code](#location-in-source-code)
- [Part 1: Antivirus Daemon (`antivirusd.sh`)](#part-1-antivirus-daemon-antivirusdsh)
- [Part 2: Restore Tool (`restore.sh`)](#part-2-restore-tool-restoresh)
- [Part 3: Makefile Automation](#part-3-makefile-automation)
- [Bonus 1: Cron Job Scheduling](#bonus-1-cron-job-scheduling)
  - [Step-by-Step Cron Configuration](#step-by-step-cron-configuration)
  - [Prerequisites for Cron](#prerequisites-for-cron)
  - [Running Every 3rd Friday of the Month at 12:31 AM](#running-every-3rd-friday-of-the-month-at-1231-am)
- [Bonus 2: Whitelist (False Positive Persistence)](#bonus-2-whitelist-false-positive-persistence)
  - [How Files Are Added](#how-files-are-added)
  - [How the Daemon Checks the Whitelist](#how-the-daemon-checks-the-whitelist)
  - [Persistence Across Runs](#persistence-across-runs)
- [Automated Testing](#automated-testing)

---

## Overview

The antivirus system is divided into complementary components:

1. **`antivirusd.sh` (Daemon)**: A background monitoring process that detects directory changes over time using directory snapshots (`directory-info.last` vs. `directory-info.new`). When changes occur, it scans files against malicious rules, prints `<file> is malicious and it is DELETED`, copies the file to the quarantine directory, and removes it from the monitored folder.
2. **`restore.sh` (Restore Tool)**: An interactive command-line utility for reviewing quarantined files. Users can inspect quarantined files one by one and choose to restore false positives, permanently delete malicious files, or leave them as-is.
3. **`Makefile`**: Automates pre-build directory creation, daemon execution, and restore tool launching with customizable arguments.
4. **`antivirus-cron.sh` (Bonus 1)**: A cron-friendly worker that executes single-pass polling and quarantine on a scheduled basis without a persistent `sleep` loop.
5. **Whitelist System (Bonus 2)**: Persists restored false positives in `.whitelist` across daemon restarts so they are not flagged again.

---

## Folder Structure

```text
Antivirus-Daemon/
├── antivirusd.sh       # Main antivirus monitoring daemon (Part 1, Bonus 2)
├── restore.sh          # Interactive quarantine restore & whitelist tool (Part 2, Bonus 2)
├── antivirus-cron.sh   # Cron-compatible single-pass monitor worker (Bonus 1, Bonus 2)
├── Makefile            # Build & execution automation with pre-build target (Part 3)
├── test_antivirus.sh   # Comprehensive automated test suite (20 automated assertions)
├── README.md           # Documentation & step-by-step manual (Part 4)
├── monitored_dir/      # Target directory monitored by the daemon (files only)
├── malicious_dir/      # Destination directory where quarantined files are moved
└── .whitelist          # (Generated on restore) Stores whitelisted false-positive files
```

---

## Prerequisites & Ubuntu Installation

The scripts are written in standard POSIX/Bash and utilize core Unix utilities (`diffutils`, `grep`, `coreutils`, `cron`, and `make`).

### Installation on Ubuntu / Debian

Open a terminal and run:

```bash
# 1. Update package lists
sudo apt update

# 2. Install Make, Cron, and essential build utilities
sudo apt install -y build-essential make cron diffutils grep coreutils

# 3. Ensure the cron service is active and enabled
sudo systemctl enable cron
sudo systemctl start cron

# 4. Clone or navigate to the repository directory
cd /path/to/Antivirus-Daemon

# 5. Grant executable permissions to all shell scripts
chmod +x antivirusd.sh restore.sh antivirus-cron.sh test_antivirus.sh
```

---

## Malicious File Classification Rules

A file is considered malicious if it matches **either** of the following rules:

1. **Flagged Extension**: The file extension matches one of the following hardcoded extensions:
   - `.exe`
   - `.bat`
   - `.vbs`
   - `.scr`
   - `.ps1`

2. **Flagged Content**: The file's contents contain at least one of the following keywords (case-insensitive):
   - `virus`
   - `trojan`
   - `malware`
   - `worm`
   - `ransomware`

*(A file is exempt if it has previously been restored and added to the whitelist; see Bonus 2).*

### Location in Source Code

The required lists are defined in the source code as hardcoded arrays:

- **In `antivirusd.sh`**:
  - **Lines 18–19**:
    ```bash
    FLAGGED_EXTENSIONS=(".exe" ".bat" ".vbs" ".scr" ".ps1")
    FLAGGED_KEYWORDS=("virus" "trojan" "malware" "worm" "ransomware")
    ```
- **In `antivirus-cron.sh`**:
  - **Lines 19–20**:
    ```bash
    FLAGGED_EXTENSIONS=(".exe" ".bat" ".vbs" ".scr" ".ps1")
    FLAGGED_KEYWORDS=("virus" "trojan" "malware" "worm" "ransomware")
    ```

---

## Part 1: Antivirus Daemon (`antivirusd.sh`)

### Syntax

```bash
./antivirusd.sh <dir> <malicious_dir> <interval-secs>
```

- `dir`: The monitored directory containing files directly inside it (no subdirectories).
- `malicious_dir`: Destination directory where quarantined files are stored.
- `interval-secs`: Number of seconds between checks.

### Example

```bash
./antivirusd.sh ./monitored_dir ./malicious_dir 5
```

### How Change Detection Works

1. **First Execution**: If `directory-info.last` does not exist, the daemon performs an immediate scan of `dir`, and saves the directory snapshot:
   ```bash
   ls -l dir > directory-info.last
   ```
2. **Periodic Polling**: Every `interval-secs`, the daemon captures the current directory state:
   ```bash
   ls -l dir > directory-info.new
   ```
3. **Comparison**: The daemon compares the two snapshot files using `cmp -s directory-info.last directory-info.new`:
   - **No Change (Identical)**: The daemon simply sleeps for another `interval-secs`. No scan is performed.
   - **Change Detected (Differ)**: The daemon scans `dir`, checks files against malicious extension and keyword rules, and updates `directory-info.last` (`cp directory-info.new directory-info.last`) so future comparisons are against the current state.
4. **Action on Detection**: For every file identified as malicious:
   - Prints: `<file> is malicious and it is DELETED`
   - Copies `<file>` into `malicious_dir`, preserving its original filename
   - Deletes the original file from `dir`

---

## Part 2: Restore Tool (`restore.sh`)

The restore tool is an interactive review console designed to handle false positives and permanently remove confirmed threats.

> **Note**: As specified, `antivirusd.sh` and `restore.sh` should not be executed concurrently.

### Syntax

```bash
./restore.sh <dir> <malicious_dir>
```

### Example

```bash
./restore.sh ./monitored_dir ./malicious_dir
```

### Interactive Workflow

1. If `malicious_dir` is empty or contains no files when started, the script outputs:
   ```text
   No malicious files to review.
   ```
   and terminates immediately.
2. Otherwise, the script displays a numbered list of all files in quarantine:
   ```text
   Quarantined files in malicious_dir:
   1) document.bat
   2) report.ps1
   0) Exit
   Select a file by number (1-2, or 0 to exit): 1
   ```
3. Upon selecting a file, the user is presented with three options:
   ```text
   Selected file: document.bat
   1) Restore this file back into ./monitored_dir (it was a false positive)
   2) Permanently delete this file from ./malicious_dir (it was genuinely malicious)
   3) Leave this file as-is and go back to the list
   Enter option [1-3]:
   ```
4. **Terminal Logging**:
   - **Option 1**: Moves the file back into `<dir>`, registers the filename into `.whitelist`, and prints:
     ```text
     Restored document.bat to ./monitored_dir.
     ```
   - **Option 2**: Permanently deletes the file from `<malicious_dir>` and prints:
     ```text
     document.bat permanently deleted.
     ```
   - **Option 3**: Leaves the file in quarantine and returns to the file selection menu.

---

## Part 3: Makefile Automation

A `Makefile` is provided to streamline directory preparation, daemon execution, and restore operations with standard commands.

### Supported Targets

| Target | Description |
|---|---|
| `make` / `make daemon` | Executes pre-build directory creation, then launches `antivirusd.sh` |
| `make restore` | Executes pre-build directory creation, then launches `restore.sh` |
| `make pre-build` | Creates `malicious_dir` (and `DIR`) if it does not already exist |
| `make clean` | Removes temporary snapshot files (`directory-info.last`, `directory-info.new`) |
| `make clean-all` | Removes snapshot files and the `.whitelist` file |
| `make help` | Displays available targets and configuration variables |

### Configuration Variables

You can override default parameters when invoking `make`:

```bash
# Run the daemon with custom paths and a 10-second interval
make daemon DIR=/path/to/monitored MALICIOUS_DIR=/path/to/quarantine INTERVAL=10

# Run the restore tool on custom paths
make restore DIR=/path/to/monitored MALICIOUS_DIR=/path/to/quarantine
```

---

## Bonus 1: Cron Job Scheduling

Instead of running a daemon that sleeps in an infinite loop, monitoring can be scheduled using the Linux `cron` service via `antivirus-cron.sh`.

### `antivirus-cron.sh` Overview

`antivirus-cron.sh` performs a single change-detection evaluation on invocation:
- Compares `directory-info.last` with `directory-info.new`.
- If changes are detected, it scans the directory, quarantines any malicious files (respecting `.whitelist`), and updates `directory-info.last`.
- Exits cleanly immediately after the check.

### Step-by-Step Cron Configuration

#### Step 1: Verify the Cron Service
Ensure the cron service is active on Ubuntu:
```bash
sudo systemctl status cron
```
If not active, start and enable it:
```bash
sudo systemctl enable --now cron
```

#### Step 2: Ensure Executable Permissions
```bash
chmod +x /absolute/path/to/Antivirus-Daemon/antivirus-cron.sh
```

#### Step 3: Open the User Crontab
```bash
crontab -e
```
*(If prompted to select an editor, choose `nano` by pressing `1`).*

#### Step 4: Add the Entry for "Every 1 Minute at Second 23"
Standard Linux cron checks jobs once per minute at second `00`. To execute a job **every 1 minute at second 23**, use `sleep 23` before running the worker:

```crontab
* * * * * sleep 23 && /absolute/path/to/Antivirus-Daemon/antivirus-cron.sh /absolute/path/to/monitored_dir /absolute/path/to/malicious_dir >> /absolute/path/to/Antivirus-Daemon/cron-antivirus.log 2>&1
```

Save and exit (`Ctrl+O`, `Enter`, `Ctrl+X` in nano).

#### Step 5: Verify the Installed Crontab
```bash
crontab -l
```

### Prerequisites for Cron

1. **Absolute Paths**: Cron executes commands in the user's home directory with a minimal environment (`PATH=/usr/bin:/bin`). Always specify absolute paths for both the script and target directories.
2. **Cron Daemon Running**: The `cron` system daemon must be running (`systemctl is-active cron` should return `active`).
3. **Execution Permissions**: `antivirus-cron.sh` must have `+x` permissions for the user owning the crontab.
4. **Log Redirection**: Redirect stdout and stderr (`>> ... 2>&1`) to capture detection output and inspect daemon activity.

---

### Running Every 3rd Friday of the Month at 12:31 AM

#### Question
> *What should the cron expression be to run this scan every 3rd Friday of the month at 12:31 am?*

#### Solution & Technical Explanation

In standard POSIX / Vixie cron:
- **12:31 AM**: Minute `31`, Hour `0` (midnight hour `00:31`).
- **3rd Friday of the Month**: In any calendar month:
  - 1st Friday falls between days 1 and 7.
  - 2nd Friday falls between days 8 and 14.
  - **3rd Friday always falls between day 15 and day 21.**

**Important Cron Nuance**: In standard Linux cron, when **both** the Day-of-Month (DOM) and Day-of-Week (DOW) fields are specified (i.e. neither is `*`), cron executes if **either** condition matches (logical OR, not AND). Therefore, writing `31 0 15-21 * 5` would mistakenly execute on every day between the 15th and 21st, *plus* on every Friday of the entire month!

To guarantee that the job runs **strictly on the 3rd Friday of the month**, the standard POSIX cron solution uses a weekday check guard (`[ "$(date +\%u)" -eq 5 ]`):

```crontab
31 0 15-21 * * [ "$(date +\%u)" -eq 5 ] && /absolute/path/to/Antivirus-Daemon/antivirus-cron.sh /absolute/path/to/monitored_dir /absolute/path/to/malicious_dir >> /absolute/path/to/Antivirus-Daemon/cron-antivirus.log 2>&1
```

#### Field Breakdown

| Field | Value | Meaning |
|---|---|---|
| **Minute** | `31` | At minute 31 |
| **Hour** | `0` | At 00:00 (12:00 AM midnight) |
| **Day of Month** | `15-21` | Only between the 15th and 21st day of the month |
| **Month** | `*` | Every month |
| **Day of Week** | `*` | Every day in the range, guarded by `[ $(date +\%u) -eq 5 ]` (Friday) |

*(Note: In crontab syntax, the `%` symbol is a newline character and must be escaped with a backslash as `\%`).*

---

## Bonus 2: Whitelist (False Positive Persistence)

When a file is falsely flagged, restoring it without tracking would cause the daemon to flag and delete it again during the very next scan cycle. The whitelist system resolves this.

### How Files Are Added to the Whitelist

When a user runs `restore.sh` and selects **Option 1**:
1. `restore.sh` moves the file from `malicious_dir` back to `dir`.
2. It appends the exact filename to the persistent `.whitelist` file:
   ```bash
   if ! grep -Fxq "$selected_file" "$WHITELIST_FILE"; then
       echo "$selected_file" >> "$WHITELIST_FILE"
   fi
   ```
3. Logs confirmation: `Restored <file> to <dir>.`

### How the Daemon Checks the Whitelist

During every scan pass in both `antivirusd.sh` and `antivirus-cron.sh`, the scanner evaluates each file:

```bash
is_whitelisted() {
    local fname="$1"
    if [ -f "$WHITELIST_FILE" ]; then
        if grep -Fxq "$fname" "$WHITELIST_FILE" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}
```

- `-F`: Evaluates the filename as fixed string (prevents regex interpretation).
- `-x`: Matches the whole line exactly (prevents substring false matches).
- If `is_whitelisted "$filename"` returns true (`0`), the daemon **skips** the file completely, leaving it untouched in `dir`.

### Persistence Across Runs

- The whitelist is stored on disk in `.whitelist` in the project directory.
- Because it is a permanent file on the filesystem, whitelisted entries persist across:
  - Stopping and restarting `antivirusd.sh`
  - Reboots of the system
  - Switching between `antivirusd.sh` and `antivirus-cron.sh`
- If a file is permanently deleted through `restore.sh` (Option 2), its entry is automatically purged from `.whitelist`.

---

## Automated Testing

A full automated test suite `test_antivirus.sh` is provided to validate all requirements, edge cases, and bonuses.

### Running the Tests

```bash
./test_antivirus.sh
```

### What Is Tested

- **Test 1**: CLI parameter and argument validation.
- **Test 2**: First-run behavior and detection across all 5 flagged extensions (`.exe`, `.bat`, `.vbs`, `.scr`, `.ps1`).
- **Test 3**: Content keyword scanning across case variations (`VIRUS`, `Trojan`, etc.) and real-time polling change detection.
- **Test 4**: `restore.sh` empty quarantine handling and interactive menus.
- **Test 5**: Whitelist persistence across daemon restarts (verifying restored false positives remain untouched).
- **Test 6**: `antivirus-cron.sh` single-pass detection, quarantine, and change tracking.
