#!/bin/bash

# =============================================
# Disk Speed Test Script
# - Path argument support
# - Log file: disk-speed-test-<hostname>.log
# - New: Mode selection (dsync or direct)
# =============================================

set -euo pipefail

# === LOG FILE SETUP ===
HOSTNAME=$(hostname -s)
LOGFILE="disk-speed-test-${HOSTNAME}.log"

log() {
    echo -e "$1" | tee -a "$LOGFILE"
}

# Header
log "================================================================="
log "Disk Speed Test Started at: $(date)"
log "Hostname: $(hostname)"
log "Log file: $LOGFILE"
log "================================================================="

# === CONFIGURATION ===
TEST_FILE="dd_speed_test.tmp"
TEST_SIZE="1G"        # Default: 1GB
BLOCK_SIZE="1M"
TARGET_DIR=""
TIMEOUT=120
OFLAG_MODE="dsync"    # New: default is dsync

# === COLORS ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;96m'
NC='\033[0m'

# === HELP ===
usage() {
    cat << EOF
Usage: $0 [OPTIONS] /path/to/test/directory

Options:
  -s SIZE     Test size (512M, 1G, 2G, ...) [default: 1G]
  -b BS       Block size (1M, 4M, 128K, ...) [default: 1M]
  -t SEC      Timeout per test (0 = unlimited) [default: 120]
  -m MODE     oflag mode: dsync or direct [default: dsync]
  -f          Fast mode (no oflag - uses cache, less accurate)
  -h          Show this help

Examples:
  $0 /mnt/ssd
  $0 -s 2G -m direct /mnt/nvme
  $0 -m dsync -b 4M /tmp
EOF
    exit 1
}

# === PARSE ARGUMENTS ===
while getopts "s:b:t:m:fh" opt; do
    case $opt in
        s) TEST_SIZE="${OPTARG^^}" ;;
        b) BLOCK_SIZE="${OPTARG^^}" ;;
        t) TIMEOUT="$OPTARG" ;;
        m) OFLAG_MODE="${OPTARG,,}" ;;   # convert to lowercase
        f) OFLAG_MODE="none" ;;
        h) usage ;;
        *) usage ;;
    esac
done
shift $((OPTIND-1))

if [ $# -ne 1 ]; then
    log "${RED}Error: Please provide a target directory.${NC}"
    usage
fi

TARGET_DIR="$(realpath "$1")"
TEST_FILE_PATH="$TARGET_DIR/$TEST_FILE"

log "Target directory: $TARGET_DIR"

# === VALIDATE DIRECTORY ===
if [ ! -d "$TARGET_DIR" ]; then
    log "${RED}Error: Directory does not exist: $TARGET_DIR${NC}"
    exit 1
fi

# Validate mode
if [[ "$OFLAG_MODE" != "dsync" && "$OFLAG_MODE" != "direct" && "$OFLAG_MODE" != "none" ]]; then
    log "${RED}Error: Invalid mode. Use 'dsync', 'direct', or -f for none.${NC}"
    exit 1
fi

# === CALCULATE SIZE & COUNT (same as before) ===
SIZE_NUM=$(echo "$TEST_SIZE" | grep -oE '[0-9]+')
SIZE_UNIT=$(echo "$TEST_SIZE" | grep -oE '[KMG]$' || echo "M")

case "$SIZE_UNIT" in
    K) TOTAL_BYTES=$((SIZE_NUM * 1024)) ;;
    M) TOTAL_BYTES=$((SIZE_NUM * 1024 * 1024)) ;;
    G) TOTAL_BYTES=$((SIZE_NUM * 1024 * 1024 * 1024)) ;;
    *) log "${RED}Invalid size unit.${NC}"; exit 1 ;;
esac

BS_NUM=$(echo "$BLOCK_SIZE" | grep -oE '[0-9]+')
BS_UNIT=$(echo "$BLOCK_SIZE" | grep -oE '[KMG]$' || echo "M")

case "$BS_UNIT" in
    K) BLOCK_BYTES=$((BS_NUM * 1024)) ;;
    M) BLOCK_BYTES=$((BS_NUM * 1024 * 1024)) ;;
    G) BLOCK_BYTES=$((BS_NUM * 1024 * 1024 * 1024)) ;;
    *) log "${RED}Invalid block size unit${NC}"; exit 1 ;;
esac

COUNT=$((TOTAL_BYTES / BLOCK_BYTES))
[ "$COUNT" -eq 0 ] && { log "${RED}Test size too small.${NC}"; exit 1; }

# === FREE SPACE CHECK ===
FREE_KB=$(df "$TARGET_DIR" --output=avail | tail -1)
FREE_BYTES=$((FREE_KB * 1024))
if [ "$FREE_BYTES" -lt $((TOTAL_BYTES * 2)) ]; then
    log "${RED}Not enough free space!${NC}"
    exit 1
fi

# === DISPLAY INFO ===
log "${YELLOW}=== DISK SPEED TEST STARTED ===${NC}"
log "Target Dir : ${CYAN}$TARGET_DIR${NC}"
log "Test Size  : ${CYAN}$TEST_SIZE${NC}"
log "Block Size : ${CYAN}$BLOCK_SIZE${NC}"
log "Mode       : ${CYAN}${OFLAG_MODE^^}${NC}"
log ""

# === WRITE TEST ===
log "${GREEN}Testing WRITE speed...${NC}"
sync

DD_WRITE="dd if=/dev/zero of=\"$TEST_FILE_PATH\" bs=$BLOCK_SIZE count=$COUNT status=progress"

if [ "$OFLAG_MODE" = "dsync" ]; then
    DD_WRITE="$DD_WRITE oflag=dsync"
elif [ "$OFLAG_MODE" = "direct" ]; then
    DD_WRITE="$DD_WRITE oflag=direct"
fi

if [ "$TIMEOUT" -gt 0 ]; then
    WRITE_OUT=$(timeout "$TIMEOUT" bash -c "$DD_WRITE" 2>&1 || echo "TIMEOUT")
else
    WRITE_OUT=$($DD_WRITE 2>&1)
fi

WRITE_SPEED=$(echo "$WRITE_OUT" | tail -n 1 | grep -oE '[0-9.]+ [KMGT]B/s' | head -n 1 || echo "N/A")

log "${GREEN}Write: $WRITE_SPEED${NC}"
log ""

# === READ TEST (always with iflag=direct when possible) ===
log "${GREEN}Testing READ speed...${NC}"
sync

DD_READ="dd if=\"$TEST_FILE_PATH\" of=/dev/null bs=$BLOCK_SIZE status=progress"
[ "$OFLAG_MODE" = "direct" ] && DD_READ="$DD_READ iflag=direct"

if [ "$TIMEOUT" -gt 0 ]; then
    READ_OUT=$(timeout "$TIMEOUT" bash -c "$DD_READ" 2>&1 || echo "TIMEOUT")
else
    READ_OUT=$($DD_READ 2>&1)
fi

READ_SPEED=$(echo "$READ_OUT" | tail -n 1 | grep -oE '[0-9.]+ [KMGT]B/s' | head -n 1 || echo "N/A")

log "${GREEN}Read: $READ_SPEED${NC}"
log ""

# === CLEANUP ===
log "${YELLOW}Cleaning up...${NC}"
rm -f "$TEST_FILE_PATH" 2>/dev/null || true
sync

# === SUMMARY ===
log "================================================================="
log "${YELLOW}=== TEST RESULTS ===${NC}"
log "Write Speed : ${GREEN}$WRITE_SPEED${NC}"
log "Read Speed  : ${GREEN}$READ_SPEED${NC}"
log "Mode used   : ${CYAN}${OFLAG_MODE^^}${NC}"
log "Log saved to: $LOGFILE"
log "Completed at: $(date)"
log "================================================================="

echo -e "${GREEN}Test finished! Log: $LOGFILE${NC}"
