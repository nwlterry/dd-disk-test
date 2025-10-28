#!/bin/bash

# =============================================
# Disk Read/Write Speed Test using dd (SAFE & FIXED)
# - No 61GB temp files!
# - Real-time progress
# - Accurate block count
# - Timeout protection
# - Optional fast mode (cached)
# Author: Assistant
# Requires: bash, dd, sync, timeout (coreutils)
# =============================================

set -euo pipefail

# === CONFIGURATION ===
TEST_FILE="dd_speed_test.tmp"
TEST_SIZE="1G"        # Default: 1GB (safe)
BLOCK_SIZE="1M"       # 1MB blocks
TARGET_DIR=""
TIMEOUT=120           # Max 120s per test (0 = no timeout)
USE_DSYNC=true        # true = accurate (slow), false = fast (cached)

# === COLORS ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
  $0 -s 2G -b 4M -t 300 /home/user/storage
  $0 -s 1G -f /tmp   # Fast test using RAM cache

EOF
    exit 1
}

# === PARSE ARGS ===
while getopts "s:b:t:fh" opt; do
    case $opt in
        s) TEST_SIZE="${OPTARG^^}" ;;  # Uppercase
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
# Extract number and unit
SIZE_NUM=$(echo "$TEST_SIZE" | grep -oE '[0-9]+')
SIZE_UNIT=$(echo "$TEST_SIZE" | grep -oE '[KMG]$' || echo "M")

case "$SIZE_UNIT" in
    K) TOTAL_BYTES=$((SIZE_NUM * 1024)) ;;
    M) TOTAL_BYTES=$((SIZE_NUM * 1024 * 1024)) ;;
    G) TOTAL_BYTES=$((SIZE_NUM * 1024 * 1024 * 1024)) ;;
    *) echo -e "${RED}Invalid size unit: use K, M, or G${NC}"; exit 1 ;;
esac

BS_NUM=$(echo "$BLOCK_SIZE" | grep -oE '[0-9]+')
BS_UNIT=$(echo "$BLOCK_SIZE" | grep -oE '[KMG]$' || echo "M")

case "$BS_UNIT" in
    K) BLOCK_BYTES=$((BS_NUM * 1024)) ;;
    M) BLOCK_BYTES=$((BS_NUM * 1024 * 1024)) ;;
    G) BLOCK_BYTES=$((BS_NUM * 1024 * 1024 * 1024)) ;;
    *) echo -e "${RED}Invalid block size unit${NC}"; exit 1 ;;
esac

COUNT=$((TOTAL_BYTES / BLOCK_BYTES))
if [ $COUNT -eq 0 ]; then
    echo -e "${RED}Error: Test size too small for block size.${NC}"
    exit 1
fi

# === CHECK FREE SPACE (with 50% buffer) ===
FREE_KB=$(df "$TARGET_DIR" --output=avail | tail -1)
FREE_BYTES=$((FREE_KB * 1024))
REQUIRED_BYTES=$((TOTAL_BYTES + (TOTAL_BYTES / 2)))  # 50% buffer

if [ "$FREE_BYTES" -lt "$REQUIRED_BYTES" ]; then
    echo -e "${RED}Not enough space!${NC}"
    echo "   Need: ~$((REQUIRED_BYTES / 1024 / 1024)) MB"
    echo "   Free: $((FREE_BYTES / 1024 / 1024)) MB"
    exit 1
fi

# === DISPLAY INFO ===
echo -e "${YELLOW}=== DISK SPEED TEST (SAFE) ===${NC}"
echo -e "Target Dir : ${BLUE}$TARGET_DIR${NC}"
echo -e "Test Size  : ${BLUE}$TEST_SIZE${NC} ($((TOTAL_BYTES / 1024 / 1024)) MB)"
echo -e "Block Size : ${BLUE}$BLOCK_SIZE${NC}"
echo -e "Blocks     : ${BLUE}$COUNT${NC}"
echo -e "Mode       : ${BLUE}$( [ "$USE_DSYNC" = true ] && echo "Accurate (dsync)" || echo "Fast (cached)" )${NC}"
echo -e "Timeout    : ${BLUE}${TIMEOUT}s${NC}"
echo

# === WRITE TEST ===
echo -e "${GREEN}Testing WRITE speed...${NC}"
sync

DD_WRITE="dd if=/dev/zero of=\"$TEST_FILE_PATH\" bs=$BLOCK_SIZE count=$COUNT status=progress"
[ "$USE_DSYNC" = true ] && DD_WRITE="$DD_WRITE oflag=dsync"

if [ "$TIMEOUT" -gt 0 ]; then
    WRITE_OUT=$(timeout "$TIMEOUT" bash -c "$DD_WRITE" 2>&1 || echo "WRITE TIMEOUT")
else
    WRITE_OUT=$($DD_WRITE 2>&1)
fi

WRITE_SPEED=$(echo "$WRITE_OUT" | tail -1 | grep -oE '[0-9.]+ [KMGT]B/s' | head -1 || echo "N/A")

if echo "$WRITE_OUT" | grep -q "records out"; then
    echo -e "${GREEN}Write: $WRITE_SPEED${NC}"
else
    echo -e "${RED}Write failed: $WRITE_OUT${NC}"
    rm -f "$TEST_FILE_PATH"
    exit 1
fi
echo

# === READ TEST ===
echo -e "${GREEN}Testing READ speed...${NC}"
sync

DD_READ="dd if=\"$TEST_FILE_PATH\" of=/dev/null bs=$BLOCK_SIZE status=progress"
[ "$USE_DSYNC" = true ] && DD_READ="$DD_READ iflag=dsync"

if [ "$TIMEOUT" -gt 0 ]; then
    READ_OUT=$(timeout "$TIMEOUT" bash -c "$DD_READ" 2>&1 || echo "READ TIMEOUT")
else
    READ_OUT=$($DD_READ 2>&1)
fi

READ_SPEED=$(echo "$READ_OUT" | tail -1 | grep -oE '[0-9.]+ [KMGT]B/s' | head -1 || echo "N/A")

if echo "$READ_OUT" | grep -q "records out"; then
    echo -e "${GREEN}Read: $READ_SPEED${NC}"
else
    echo -e "${RED}Read failed: $READ_OUT${NC}"
fi
echo

# === CLEANUP ===
echo -e "${YELLOW}Cleaning up...${NC}"
rm -f "$TEST_FILE_PATH"
sync

# === FINAL SUMMARY ===
echo -e "${YELLOW}=== RESULTS ===${NC}"
echo -e "Write Speed : ${GREEN}$WRITE_SPEED${NC}"
echo -e "Read Speed  : ${GREEN}$READ_SPEED${NC}"
echo -e "${BLUE}Test completed safely. Temp file deleted.${NC}"
