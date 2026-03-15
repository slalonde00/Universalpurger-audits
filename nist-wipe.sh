#!/bin/bash
set -euo pipefail

# Vérification ROOT
[[ $EUID -ne 0 ]] && echo -e "\e[31mErreur: Exécutez en ROOT.\e[0m" && exit 1

# --- CONFIGURATION INTERACTIVE ---
echo -e "\e[36m=== CONFIGURATION DE L'AUDIT ===\e[0m"
read -p "Email pour identification (pour logs locaux) : " GPG_USER

# --- DISK DETECTION ---
echo -e "\n\e[33m[DISQUES DISPONIBLES]\e[0m"
mapfile -t DISK_LIST < <(lsblk -dno NAME,SIZE,ROTA,TYPE,MODEL | grep -v "loop")

# Build menu
echo "0) TOUS LES DISQUES (sauf OS)"
for i in "${!DISK_LIST[@]}"; do
    echo "$((i+1))) ${DISK_LIST[$i]}"
done

# --- SELECTION INTERACTIVE ---
read -p "Sélectionnez le numéro du disque à effacer : " DISK_CHOICE

# Determine selected disks
if [[ "$DISK_CHOICE" -eq 0 ]]; then
    ROOT_DISK=$(findmnt -no SOURCE / | sed 's/[0-9]*$//')
    SELECTED_DISKS=""
    for DISK in $(lsblk -dno NAME | grep -v "loop"); do
        [[ "/dev/$DISK" == "$ROOT_DISK" ]] && continue
        SELECTED_DISKS+="/dev/$DISK "
    done
else
    INDEX=$((DISK_CHOICE-1))
    DISK_NAME=$(echo "${DISK_LIST[$INDEX]}" | awk '{print $1}')
    SELECTED_DISKS="/dev/$DISK_NAME"
fi

[[ -z "$SELECTED_DISKS" ]] && echo "Aucun disque sélectionné." && exit 1

echo -e "\nLes disques sélectionnés seront effacés : $SELECTED_DISKS"

# --- CONFIRMATION ---
read -p "Tapez ERASE en majuscules pour confirmer : " CONFIRM
if [[ "$CONFIRM" != "ERASE" ]]; then
    echo -e "\e[33mAnnulé. Le script ne fera rien.\e[0m"
    exit 0
fi

# --- DEPENDENCIES ---
for cmd in pv sha256sum; do
    if ! command -v $cmd &>/dev/null; then
        echo "$cmd n'est pas installé. Installation..."
        apt update && apt install -y $cmd
    fi
done

# --- FUNCTION: Wipe HDD/USB/eMMC ---
wipe_hdd() {
    local DISK="$1"
    local DISK_BYTES=$(blockdev --getsize64 "$DISK")
    local abort_flag=0

    for PASS in {1..3}; do
        echo -e "\n-- Passe $PASS: $( [[ $PASS -eq 3 ]] && echo "zéros" || echo "données aléatoires" ) --"
        INPUT=/dev/urandom
        [[ $PASS -eq 3 ]] && INPUT=/dev/zero

        dd if="$INPUT" bs=1M status=none | pv -s $DISK_BYTES -pterb | dd of="$DISK" bs=1M conv=notrunc status=none &
        DD_PID=$!

        echo -e "\nAppuyez sur 'q' puis Enter pour annuler le wipe..."
        while kill -0 $DD_PID 2>/dev/null; do
            read -t 1 -n 1 key || true
            if [[ "$key" == "q" ]]; then
                kill -9 $DD_PID
                echo "Effacement annulé par l'utilisateur !"
                abort_flag=1
                break
            fi
        done
        wait $DD_PID 2>/dev/null
        [[ $abort_flag -eq 1 ]] && break
    done

    if [[ $abort_flag -eq 0 ]]; then
        echo -e "\nVérification complète du disque avec SHA-256..."
        HASH=$(dd if="$DISK" bs=1M status=none | sha256sum | awk '{print $1}')
        if [[ "$HASH" =~ ^[0]+$ ]]; then
            echo "Résultat : CONFORME (tout le disque est à zéro)"
        else
            echo "Résultat : ÉCHEC (des données résiduelles détectées)"
        fi
    else
        echo "Effacement interrompu, vérification ignorée."
    fi
}

# --- FUNCTION: Wipe NVMe/SSD ---
wipe_nvme() {
    local DISK="$1"
    echo "Action : Effacement NVMe/SSD en cours..."
    if command -v nvme &>/dev/null; then
        nvme format "$DISK" --ses=2 --force &>/dev/null || nvme format "$DISK" --ses=1 --force &>/dev/null
        echo "Effacement NVMe terminé"
    else
        echo "nvme CLI non disponible, utilisation de blkdiscard si possible..."
        blkdiscard "$DISK" &>/dev/null && echo "Effacement blkdiscard terminé" || echo "Impossible d'effacer le disque via nvme/blkdiscard"
    fi
}

# --- WIPE LOOP ---
for DISK in $SELECTED_DISKS; do
    SERIAL=$(lsblk -dno SERIAL "$DISK" || echo "INCONNU")
    ROTA=$(lsblk -dno ROTA "$DISK")
    echo -e "\n\e[34mTraitement de $DISK (S/N: $SERIAL)\e[0m"

    # Audit SMART
    if command -v smartctl &>/dev/null; then
        HEALTH=$(smartctl -H "$DISK" 2>/dev/null | grep -i "result" | awk -F: '{print $2}' | xargs)
        echo "Santé SMART : ${HEALTH:-INCONNU}"
    else
        echo "smartctl non disponible, audit SMART ignoré."
    fi

    # Detect type
    if [[ "$DISK" == *nvme* ]] || [[ "$ROTA" -eq 0 ]]; then
        wipe_nvme "$DISK"
    else
        wipe_hdd "$DISK"
    fi
done

echo -e "\n--- OPÉRATION TERMINÉE ---"
