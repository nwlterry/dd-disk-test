#!/bin/bash

# =============================================
# Disk Read/Write Speed Test using dd (Fixed Version)
# Fixes: Progress bar, timeout, better parsing
# Author: Assistant
# Requires: bash, dd, sync, timeout (from coreutils)
# =============================================

set -euo pipefail

# Default settings
TEST_FILE="dd_speed_test.tmp"
TEST_SIZE="4G"        # Total test size (4GB recommended)
BLOCK_SIZE="1M"       # Block size for dd
TARGET_DIR=""
TIMEOUT=300           # Timeout for dd in seconds (0 = no timeout)
USE_DSYNC=true        # Use dsync for accuracy (set false for faster/cached test)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Help function
usage() {
    cat << EOF
Usage: $0 [OPTIONS] /path/to/test/directory

Options:
  -s SIZE    Test file size (e.g., 1G, 4G, 1024M) [default: 4G]
  -b BS      Block size for dd (e.g., 1M, 4M, 128K) [default: 1M]
  -t SEC     Timeout for each dd command (0=disable) [default: 300]
  -f         Fast mode: Skip dsync (uses cache, faster but less accurate)
  -h         Show this help

Example:
  $0 /mnt/mydisk
  $0 -s 1G -f /home/user/storage  # Fast 1GB test
EOF
    exit 1
}

# Parse arguments
while getopts "s:b:t:f h" opt; do
    case $opt in
        s) TEST_SIZE="$OPTARG" ;;
        b) BLOCK_SIZE="$OPTARG" ;;
        t) TIMEOUT="$OPTARG" ;;
        f) USE_DSYNC=false ;;
        h) usage ;;
        *) usage ;;
    esac
done

shift $((OPTIND-1))

# Get target directory
if [ $# -ne 1 ]; then
    echo -e "${RED}Error: Please provide a target directory.${NC}"
    usage
fi

TARGET_DIR="$(realpath "$1")"
TEST_FILE_PATH="$TARGET_DIR/$TEST_FILE"

if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}Error: Directory '$TARGET_DIR' does not exist.${NC}"
    exit 1
fi

# Check free space (add 20% buffer)
FREE_SPACE_KB=$(df "$TARGET_DIR" --output=avail | tail -1)
FREE_SPACE_MB=$((FREE_SPACE_KB / 1024))
case $(echo "$TEST_SIZE" | tr '[:upper:]' '[:lower:]') in
    *g) REQUIRED_MB=$(( $(echo "$TEST_SIZE" | sed 's/G//i') * 1024 )) ;;
    *m) REQUIRED_MB=$(echo "$TEST_SIZE" | sed 's/M//i') ;;
    *) echo -e "${RED}Error: Invalid size format (use 1G, 4G, 1024M).${NC}"; exit 1 ;;
esac
REQUIRED_MB=$((REQUIRED_MB * 120 / 100))  # 20% buffer

if [ "$FREE_SPACE_MB" -lt "$REQUIRED_MB" ]; then
    echo -e "${RED}Error: Not enough space in '$TARGET_DIR'${NC}"
    echo "   Need ~${REQUIRED_MB} MB, have ${FREE_SPACE_MB} MB"
    exit 1
fi

# Calculate count for dd (e.g., 4G with 1M bs = 4096)
COUNT=$(( $(echo "$TEST_SIZE" | sed 's/G//i') * 1024 * 1024 / $(echo "$BLOCK_SIZE" | sed 's/M//i') * 1024 / 1024 ))

echo -e "${YELLOW}=== Disk Speed Test (dd) - Fixed ===${NC}"
echo "Target Directory : $TARGET_DIR"
echo "Test File Size   : $TEST_SIZE (count=$COUNT blocks)"
echo "Block Size       : $BLOCK_SIZE"
echo "Use dsync        : $USE_DSYNC (set -f for fast/cached)"
echo "Timeout          : ${TIMEOUT}s"
echo "Monitor with: sudo iotop -o"
echo

# === WRITE TEST ===
echo -e "${GREEN}Testing WRITE speed... (Progress shown live)${NC}"
sync

# Build dd command
DD_CMD="dd if=/dev/zero of=\"$TEST_FILE_PATH\" bs=\"$BLOCK_SIZE\" count=$COUNT"
if [ "$USE_DSYNC" = true ]; then
    DD_CMD="$DD_CMD oflag=dsync"
fi
DD_CMD="$DD_CMD status=progress 2>&1"

# Run with timeout if >0
if [ "$TIMEOUT" -gt 0 ]; then
    WRITE_OUTPUT=$(timeout "$TIMEOUT" bash -c "$DD_CMD" || echo "TIMEOUT: dd killed after ${TIMEOUT}s - disk too slow?")
else
    WRITE_OUTPUT=$($DD_CMD)
fi

# Parse output (look for final speed line)
if echo "$WRITE_OUTPUT" | grep -q "copied"; then
    WRITE_SPEED=$(echo "$WRITE_OUTPUT" | grep -o '[0-9.]\+ [KMGT]B/s' | tail -1)
    echo -e "\n${GREEN}Write completed: $WRITE_SPEED${NC}"
else
    echo -e "${RED}Write failed or timed out: $WRITE_OUTPUT${NC}"
    exit 1
fi
echo

# === READ TEST ===
echo -e "${GREEN}Testing READ speed... (Progress shown live)${NC}"
sync

# Build dd command
DD_CMD="dd if=\"$TEST_FILE_PATH\" of=/dev/null bs=\"$BLOCK_SIZE\""
if [ "$USE_DSYNC" = true ]; then
    DD_CMD="$DD_CMD iflag=dsync"
fi
DD_CMD="$DD_CMD status=progress 2>&1"

if [ "$TIMEOUT" -gt 0 ]; then
    READ_OUTPUT=$(timeout "$TIMEOUT" bash -c "$DD_CMD" || echo "TIMEOUT: dd killed after ${TIMEOUT}s")
else
    READ_OUTPUT=$($DD_CMD)
fi

if echo "$READ_OUTPUT" | grep -q "copied"; then
    READ_SPEED=$(echo "$READ_OUTPUT" | grep -o '[0-9.]\+ [KMGT]B/s' | tail -1)
    echo -e "\n${GREEN}Read completed: $READ_SPEED${NC}"
else
    echo -e "${RED}Read failed or timed out: $READ_OUTPUT${NC}"
fi
echo

# === CLEANUP ===
echo -e "${YELLOW}Cleaning up...${NC}"
rm -f "$TEST_FILE_PATH"
sync

# === SUMMARY ===
echo -e "${YELLOW}=== SUMMARY ===${NC}"
echo "Write Speed : $WRITE_SPEED"
echo "Read Speed  : $READ_SPEED"
echo -e "${GREEN}Test completed successfully.${NC}"
