#!/bin/bash
set -euo pipefail

#######################################
# DEFAULTS
#######################################
DRY_RUN=false
METHOD="clear"
DISK=""
GPG_USER=""
REMOTE_HOST=""
REMOTE_USER="root"
REMOTE_DIR="/tmp"

#######################################
# EXIT CODES
#######################################
# 0 = success
# 1 = usage / input error
# 2 = dependency error
# 3 = erase failure
# 4 = validation failure
# 5 = transfer failure

#######################################
# ROOT CHECK
#######################################
[[ $EUID -eq 0 ]] || { echo "Must be run as root"; exit 1; }

#######################################
# DEPENDENCIES
#######################################
REQ=(lsblk smartctl gpg scp shred dd od awk grep date)
for c in "${REQ[@]}"; do
    command -v "$c" >/dev/null || { echo "Missing dependency: $c"; exit 2; }
done

#######################################
# ARGUMENT PARSING
#######################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk) DISK="$2"; shift 2 ;;
        --method) METHOD="$2"; shift 2 ;;
        --gpg) GPG_USER="$2"; shift 2 ;;
        --remote) REMOTE_HOST="$2"; shift 2 ;;
        --ssh-user) REMOTE_USER="$2"; shift 2 ;;
        --remote-dir) REMOTE_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--disk /dev/sdX] [--method clear|purge] [--dry-run]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

#######################################
# DISK VALIDATION
#######################################
[[ -b "$DISK" ]] || { echo "Invalid block device"; exit 1; }

#######################################
# CONFIRMATION
#######################################
if ! $DRY_RUN; then
    echo "!!! WARNING !!!"
    echo "You are about to ERASE: $DISK using NIST method: $METHOD"
    read -rp "Type ERASE to continue: " CONFIRM
    [[ "$CONFIRM" == "ERASE" ]] || exit 1
fi

#######################################
# REPORT FILES
#######################################
TS=$(date +%Y%m%d_%H%M%S)
REPORT_TXT="audit_${TS}.txt"
REPORT_JSON="audit_${TS}.json"

#######################################
# METADATA
#######################################
SERIAL=$(lsblk -dno SERIAL "$DISK")
MODEL=$(lsblk -dno MODEL "$DISK")
TYPE=$(lsblk -dno TRAN "$DISK")

#######################################
# ERASE
#######################################
ERASE_RESULT="SKIPPED"

if $DRY_RUN; then
    ERASE_RESULT="DRY_RUN"
else
    if [[ "$METHOD" == "purge" && "$DISK" == *nvme* ]]; then
        if nvme format "$DISK" --ses=2 --force &>/dev/null; then
            ERASE_RESULT="NVME_PURGE"
        else
            echo "NVMe purge failed"
            exit 3
        fi
    else
        if shred -n 1 -z "$DISK" &>/dev/null; then
            ERASE_RESULT="OVERWRITE_CLEAR"
        else
            echo "Overwrite failed"
            exit 3
        fi
    fi
fi

#######################################
# VALIDATION
#######################################
if ! $DRY_RUN; then
    if dd if="$DISK" bs=1M count=5 2>/dev/null \
        | od -A n -X | grep -vq "0000000"; then
        VALIDATION="PASS"
    else
        VALIDATION="FAIL"
        exit 4
    fi
else
    VALIDATION="SKIPPED"
fi

#######################################
# REPORTS
#######################################
cat > "$REPORT_TXT" <<EOF
NIST 800-88 Disk Erasure Report
------------------------------
Date: $(date)
Disk: $DISK
Serial: $SERIAL
Model: $MODEL
Method: $METHOD
Erase Result: $ERASE_RESULT
Validation: $VALIDATION
Dry Run: $DRY_RUN
EOF

cat > "$REPORT_JSON" <<EOF
{
  "timestamp": "$(date -Is)",
  "disk": "$DISK",
  "serial": "$SERIAL",
  "model": "$MODEL",
  "method": "$METHOD",
  "erase_result": "$ERASE_RESULT",
  "validation": "$VALIDATION",
  "dry_run": $DRY_RUN
}
EOF

#######################################
# SIGN & SEND
#######################################
if [[ -n "$GPG_USER" ]]; then
    gpg --batch --yes --clear-sign --local-user "$GPG_USER" "$REPORT_JSON"
    REPORT_SEND="${REPORT_JSON}.asc"
else
    REPORT_SEND="$REPORT_JSON"
fi

if [[ -n "$REMOTE_HOST" ]]; then
    scp -o BatchMode=yes -o ConnectTimeout=10 \
        "$REPORT_SEND" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR" || exit 5
fi

echo "ERASE COMPLETE — STATUS: $VALIDATION"
