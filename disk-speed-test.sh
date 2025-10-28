#!/bin/bash

# =============================================
# Disk Read/Write Speed Test using dd
# Author: Assistant
# Requires: bash, dd, sync, bc (optional for pretty output)
# =============================================

set -euo pipefail

# Default settings
TEST_FILE="dd_speed_test.tmp"
TEST_SIZE="4G"        # Total test size (4GB recommended)
BLOCK_SIZE="1M"       # Block size for dd
TARGET_DIR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Help function
usage() {
    cat << EOF
Usage: $0 [OPTIONS] /path/to/test/directory

Test disk read/write speed using dd.

Options:
  -s SIZE    Test file size (e.g., 1G, 4G, 1024M) [default: 4G]
  -b BS      Block size for dd (e.g., 1M, 4M, 128K) [default: 1M]
  -h         Show this help

Example:
  $0 /mnt/mydisk
  $0 -s 2G -b 4M /home/user/storage

Warning: Directory must have enough free space!
EOF
    exit 1
}

# Parse arguments
while getopts "s:b:h" opt; do
    case $opt in
        s) TEST_SIZE="$OPTARG" ;;
        b) BLOCK_SIZE="$OPTARG" ;;
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

# Check free space
FREE_SPACE_KB=$(df "$TARGET_DIR" --output=avail | tail -1)
FREE_SPACE_MB=$((FREE_SPACE_KB / 1024))
REQUIRED_MB=$(( $(echo "$TEST_SIZE" | sed 's/G//i') * 1024 + 100 ))

if [ "$FREE_SPACE_MB" -lt "$REQUIRED_MB" ]; then
    echo -e "${RED}Error: Not enough space in '$TARGET_DIR'${NC}"
    echo "   Need ~${REQUIRED_MB} MB, have ${FREE_SPACE_MB} MB"
    exit 1
fi

echo -e "${YELLOW}=== Disk Speed Test (dd) ===${NC}"
echo "Target Directory : $TARGET_DIR"
echo "Test File Size   : $TEST_SIZE"
echo "Block Size       : $BLOCK_SIZE"
echo "Test File        : $TEST_FILE_PATH"
echo

# === WRITE TEST ===
echo -e "${GREEN}Testing WRITE speed...${NC}"
sync
WRITE_OUTPUT=$(dd if=/dev/zero of="$TEST_FILE_PATH" bs="$BLOCK_SIZE" count=$(echo "$TEST_SIZE" | sed 's/G//i')000 oflag=dsync 2>&1)
WRITE_BYTES=$(echo "$WRITE_OUTPUT" | grep -o '[0-9]\+ bytes')
WRITE_TIME=$(echo "$WRITE_OUTPUT" | grep -o '[0-9.]\+ sec')
WRITE_SPEED=$(echo "$WRITE_OUTPUT" | grep -o '[0-9.]\+ [KMGT]B/s')

echo "$WRITE_OUTPUT"
echo

# === READ TEST ===
echo -e "${GREEN}Testing READ speed...${NC}"
sync
READ_OUTPUT=$(dd if="$TEST_FILE_PATH" of=/dev/null bs="$BLOCK_SIZE" iflag=dsync 2>&1)
READ_SPEED=$(echo "$READ_OUTPUT" | grep -o '[0-9.]\+ [KMGT]B/s')

echo "$READ_OUTPUT"
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
