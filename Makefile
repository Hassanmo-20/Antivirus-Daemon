# ==============================================================================
# Makefile for Antivirus Daemon & Tools
#
# Lab 2: Writing a Shell Script for a Simple Antivirus Daemon
# ==============================================================================

# Configurable variables with default arguments
DIR ?= monitored_dir
MALICIOUS_DIR ?= malicious_dir
INTERVAL ?= 5

.PHONY: all pre-build daemon restore clean clean-all help

# Default target: executes the daemon
all: daemon

# Pre-build step: creates the quarantine (and monitored) directory if it does not exist
pre-build:
	@mkdir -p $(MALICIOUS_DIR)
	@mkdir -p $(DIR)

# Target to run the antivirus daemon with required arguments
daemon: pre-build
	bash ./antivirusd.sh $(DIR) $(MALICIOUS_DIR) $(INTERVAL)

# Target to run the restore tool with required arguments
restore: pre-build
	bash ./restore.sh $(DIR) $(MALICIOUS_DIR)

# Clean snapshot tracking files
clean:
	rm -f directory-info.last directory-info.new

# Deep clean including whitelist
clean-all: clean
	rm -f .whitelist

# Help menu
help:
	@echo "Simple Antivirus Daemon - Makefile Targets"
	@echo "------------------------------------------"
	@echo "  make              Run the antivirus daemon (runs pre-build first)"
	@echo "  make daemon       Run the antivirus daemon with arguments"
	@echo "  make restore      Run the quarantine restore tool"
	@echo "  make pre-build    Execute pre-build step to create $(MALICIOUS_DIR)"
	@echo "  make clean        Remove temporary snapshot files"
	@echo "  make clean-all    Remove temporary snapshot files and whitelist"
	@echo ""
	@echo "Variables:"
	@echo "  DIR=$(DIR)"
	@echo "  MALICIOUS_DIR=$(MALICIOUS_DIR)"
	@echo "  INTERVAL=$(INTERVAL)"
