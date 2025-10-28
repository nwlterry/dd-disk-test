#!/bin/bash

# =============================================
# Disk Read/Write Speed Test using dd (SAFE & READABLE)
# - No huge files
# - Real-time progress
# - Accurate block count
# - Timeout protection
# - Bright cyan for info (replaces hard-to-see blue)
# Author: Assistant
# Requires: bash, dd, sync, timeout
# =============================================

set -euo pipefail

# === CONFIGURATION ===
TEST_FILE="dd_speed_test.tmp"
TEST_SIZE="1G"        # Default: 1GB
BLOCK_SIZE="1M"
TARGET_DIR=""
TIMEOUT=120
USE_DSYNC=true

# === COLORS (Improved readability) ===
RED='\033[0;31m'           # Error
GREEN='\033[0;32m'         # Success / Speed
YELLOW='\033[1;33m'        # Headers / Warnings
CYAN='\033[0;96m'          # Info (BRIGHT, replaces blue)
NC='\033[0m'               # Reset

# === HELP ===
usage() {
    cat << EOF
Usage: $0 [OPTIONS] /path/to/test/directory

Test disk read/write speed safely using dd.

Options:
  -s SIZE    Test size: 512M, 1G, 2G, 4G, etc. [default: 1G]
  -b BS      Block size: 1M, 4M, 128K, etc. [default: 1M]
  -t SEC     Timeout per test in seconds (0 = no limit) [default: 120]
  -f         Fast mode: Skip dsync (cached, faster, less accurate)
  -h         Show this help

Examples:
  $0 /mnt/ssd
  $0 -s 2G -t 300 /home/user/storage
  $0 -s 1G -f /tmp   # Fast test using RAM

EOF
    exit 1
}

# === PARSE ARGS ===
while getopts "s:b:t:fh" opt; do
    case $opt in
        s) TEST_SIZE="${OPTARG^^}" ;;
        b) BLOCK_SIZE="${OPTARG^^}" ;;
        t) TIMEOUT="$OPTARG" ;;
        f) USE_DSYNC=false ;;
        h) usage ;;
        *) usage ;;
    esac
done
shift $((OPTIND-1))

if [ $# -ne 1 ]; then
    echo -e "${RED}Error: Please provide a target directory.${NC}"
    usage
fi

TARGET_DIR="$(realpath "$1")"
TEST_FILE_PATH="$TARGET_DIR/$TEST_FILE"

# === VALIDATE DIRECTORY ===
if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}Error: Directory does not exist: $TARGET_DIR${NC}"
    exit 1
fi

# === CALCULATE SIZE & COUNT ===
SIZE_NUM=$(echo "$TEST_SIZE" | grep -oE '[0-9]+')
SIZE_UNIT=$(echo "$TEST_SIZE" | grep -oE '[KMG]$' || echo "M")

case "$SIZE_UNIT" in
    K) TOTAL_BYTES=$((SIZE_NUM * 1024)) ;;
    M) TOTAL_BYTES=$((SIZE_NUM * 1024 * 1024)) ;;
    G) TOTAL_BYTES=$((SIZE_NUM * 1024 * 1024 * 1024)) ;;
    *) echo -e "${RED}Invalid size unit: use K, M, or G${NC}"; exit 1 ;;
esac

BS_NUM=$(echo
