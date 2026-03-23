#!/bin/bash

# =============================================
# Disk Speed Test Script (with logging)
# Log file now includes hostname: disk-speed-test-<hostname>.log
# =============================================

# Get hostname and create log filename
HOSTNAME=$(hostname -s)                    # Use short hostname (without domain)
LOGFILE="disk-speed-test-${HOSTNAME}.log"

# Create or append to the log file with header
echo "=================================================================" | tee -a "$LOGFILE"
echo "Disk Speed Test Started at: $(date)" | tee -a "$LOGFILE"
echo "Hostname: $(hostname)" | tee -a "$LOGFILE"
echo "Log file: $LOGFILE" | tee -a "$LOGFILE"
echo "=================================================================" | tee -a "$LOGFILE"

echo "Testing write speed (1GB file)..." | tee -a "$LOGFILE"
dd if=/dev/zero of=tempfile bs=1M count=1024 conv=fdatasync status=progress 2>&1 | tee -a "$LOGFILE"

echo "" | tee -a "$LOGFILE"
echo "Testing read speed..." | tee -a "$LOGFILE"
dd if=tempfile of=/dev/null bs=1M count=1024 status=progress 2>&1 | tee -a "$LOGFILE"

echo "" | tee -a "$LOGFILE"
echo "Cleaning up..." | tee -a "$LOGFILE"
rm -f tempfile

echo "" | tee -a "$LOGFILE"
echo "=================================================================" | tee -a "$LOGFILE"
echo "Disk Speed Test Completed at: $(date)" | tee -a "$LOGFILE"
echo "Log saved to: $LOGFILE" | tee -a "$LOGFILE"
echo "=================================================================" | tee -a "$LOGFILE"
