#!/bin/bash
set -euo pipefail

# --- REQUIRE ROOT ---
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31mErreur: Exécutez en ROOT.\e[0m"
    exit 1
fi

# --- DEPENDENCIES ---
REQUIRED_CMDS=(dd sha256sum blkdiscard nvme lsblk findmnt)
MISSING_CMDS=()
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_CMDS+=("$cmd")
    fi
done

if [ ${#MISSING_CMDS[@]} -gt 0 ]; then
    echo -e "\e[33mDépendances manquantes : ${MISSING_CMDS[*]}\e[0m"
    if command -v apt &>/dev/null; then
        echo "Tentative d'installation via apt..."
        apt update
        apt install -y "${MISSING_CMDS[@]}" || echo "Impossible d'installer certaines dépendances, vérifiez manuellement."
    else
        echo "Veuillez installer les dépendances manuellement."
    fi
fi

# --- PARSE ARGUMENTS ---
SELECTED_DISKS=""
MODE="interactive"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk)
            SELECTED_DISKS+="$2 "
            MODE="cli"
            shift
            ;;
        --all)
            MODE="all"
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        *)
            echo "Argument inconnu: $1"
            exit 1
            ;;
    esac
    shift
done

# --- DETECT LIVE USB ROOT ---
ROOT_DISK=$(findmnt -no SOURCE / | sed 's/[0-9]*$//')

# --- INTERACTIVE MODE ---
if [[ "$MODE" == "interactive" ]]; then
    echo -e "\e[36m=== CONFIGURATION DE L'AUDIT ===\e[0m"
    read -p "Email pour identification (logs locaux) : " GPG_USER

    echo -e "\n\e[33m[DISQUES DISPONIBLES]\e[0m"
    mapfile -t DISK_LIST < <(lsblk -dno NAME,SIZE,ROTA,TYPE,MODEL | grep -v "loop" || true)

    echo "0) TOUS LES DISQUES (sauf OS live USB)"
    for i in "${!DISK_LIST[@]}"; do
        echo "$((i+1))) ${DISK_LIST[$i]}"
    done

    read -p "Sélectionnez le numéro du disque à effacer : " DISK_CHOICE

    if [[ "$DISK_CHOICE" -eq 0 ]]; then
        for DISK in $(lsblk -dno NAME | grep -v "loop"); do
            [[ "/dev/$DISK" == "$ROOT_DISK" ]] && continue
            SELECTED_DISKS+="/dev/$DISK "
        done
    else
        INDEX=$((DISK_CHOICE-1))
        DISK_NAME=$(echo "${DISK_LIST[$INDEX]}" | awk '{print $1}')
        SELECTED_DISKS="/dev/$DISK_NAME"
    fi
fi

# --- ALL MODE ---
if [[ "$MODE" == "all" ]]; then
    for DISK in $(lsblk -dno NAME | grep -v "loop"); do
        [[ "/dev/$DISK" == "$ROOT_DISK" ]] && continue
        SELECTED_DISKS+="/dev/$DISK "
    done
fi

# --- VALIDATION ---
if [[ -z "$SELECTED_DISKS" ]]; then
    echo "Aucun disque sélectionné."
    exit 1
fi

echo -e "\nDisques sélectionnés : $SELECTED_DISKS"

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo -e "\nDRY RUN activé — aucune donnée ne sera effacée."
    exit 0
fi

read -p "Tapez ERASE pour confirmer : " CONFIRM
if [[ "$CONFIRM" != "ERASE" ]]; then
    echo "Annulé."
    exit 0
fi

# --- PROGRESS BAR FUNCTION ---
progress_bar() {
    local PROGRESS=$1
    local WIDTH=50
    local FILLED=$((PROGRESS*WIDTH/100))
    local EMPTY=$((WIDTH-FILLED))
    printf "\r["
    for ((i=0;i<FILLED;i++)); do printf "#"; done
    for ((i=0;i<EMPTY;i++)); do printf "-"; done
    printf "] %3d%%" "$PROGRESS"
}

# --- WIPE FUNCTIONS ---
wipe_disk() {
    local DISK="$1"
    local SIZE=$(blockdev --getsize64 "$DISK")
    local BLOCK=4194304  # 4MB

    echo "Effacement du disque $DISK..."

    for PASS in 1 2 3; do
        INPUT="/dev/urandom"
        [[ $PASS -eq 3 ]] && INPUT="/dev/zero"

        echo -e "\nPasse $PASS/3 sur $DISK..."

        # Using dd with pv style progress
        dd if="$INPUT" of="$DISK" bs=$BLOCK conv=notrunc status=progress 2>&1 | \
        while read -r line; do
            if [[ "$line" =~ ([0-9]+) ]]; then
                COUNT=${BASH_REMATCH[1]}
                PERCENT=$((COUNT*100/SIZE))
                ((PERCENT>100)) && PERCENT=100
                progress_bar $PERCENT
            fi
        done

        echo -e "\nPasse $PASS terminée."
    done

    echo "SHA256 vérification..."
    HASH=$(dd if="$DISK" bs=$BLOCK status=none | sha256sum | awk '{print $1}')
    echo "SHA256: $HASH"
}

wipe_nvme_ssd() {
    local DISK="$1"
    echo "Effacement du SSD/NVMe $DISK..."
    if command -v nvme &>/dev/null; then
        echo "Tentative nvme format..."
        nvme format "$DISK" --ses=2 --force || nvme format "$DISK" --ses=1 --force || echo "Échec nvme format, utilisation de dd..."
        wipe_disk "$DISK"  # fallback progress via dd
    else
        echo "blkdiscard..."
        blkdiscard "$DISK" || echo "Échec blkdiscard, utilisation de dd..."
        wipe_disk "$DISK"
    fi
}

# --- MAIN LOOP ---
for DISK in $SELECTED_DISKS; do
    echo -e "\nTraitement de $DISK"

    ROTA=$(lsblk -dno ROTA "$DISK" || echo 1)

    if [[ "$DISK" == *nvme* ]] || [[ "$ROTA" -eq 0 ]]; then
        wipe_nvme_ssd "$DISK"
    else
        wipe_disk "$DISK"
    fi
done

echo -e "\n--- TERMINÉ ---"
read -p "Appuyez sur Entrée pour quitter..."
