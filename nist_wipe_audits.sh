#!/bin/bash
# Vérification ROOT
[[ $EUID -ne 0 ]] && echo -e "\e[31mErreur: Exécutez en ROOT.\e[0m" && exit 1

# --- CONFIGURATION INTERACTIVE ---
echo -e "\e[36m=== CONFIGURATION DE L'AUDIT ===\e[0m"
read -p "Email pour signature GPG : " GPG_USER
read -p "IP Serveur : " REMOTE_HOST
read -p "User SSH [root] : " REMOTE_USER; REMOTE_USER=${REMOTE_USER:-root}
read -p "Dossier distant [/tmp] : " REMOTE_DIR; REMOTE_DIR=${REMOTE_DIR:-/tmp}

# --- SÉLECTION DU DISQUE ---
echo -e "\n\e[33m[CHOIX DU DISQUE]\e[0m"
mapfile -t DISK_LIST < <(lsblk -dno NAME,SIZE,MODEL | grep -v "loop")

echo "0) TOUS LES DISQUES"
for i in "${!DISK_LIST[@]}"; do
    echo "$((i+1))) ${DISK_LIST[$i]}"
done

read -p "Sélectionnez le numéro du disque à traiter : " DISK_CHOICE

if [[ "$DISK_CHOICE" -eq 0 ]]; then
    SELECTED_DISKS=$(lsblk -dno NAME | grep -v "loop" | awk '{print "/dev/"$1}')
else
    INDEX=$((DISK_CHOICE-1))
    DISK_NAME=$(echo "${DISK_LIST[$INDEX]}" | awk '{print $1}')
    SELECTED_DISKS="/dev/$DISK_NAME"
fi

[[ -z "$SELECTED_DISKS" ]] && echo "Choix invalide." && exit 1

# --- CONFIRMATION FINALE ---
echo -e "\n\e[31m⚠️  ATTENTION : Cette opération EFFACERA le(s) disque(s) sélectionné(s) !\e[0m"
read -p "Tapez ERASE en majuscules pour continuer : " CONFIRM
if [[ "$CONFIRM" != "ERASE" ]]; then
    echo -e "\e[33mAnnulé. Le script ne fera rien.\e[0m"
    exit 0
fi

REPORT_FILE="audit_$(date +%Y%m%d_%H%M%S).txt"

# --- FONCTIONS ---
log_info() { echo -e "$1" | tee -a "$REPORT_FILE"; }

send_to_server() {
    scp "$1" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}" && \
    echo -e "\e[32m[OK] Rapport envoyé.\e[0m" || echo -e "\e[31m[!] Erreur envoi.\e[0m"
}

# --- DÉBUT DU TRAITEMENT ---
{
    echo "==============================================="
    echo "  RAPPORT D'EFFACEMENT NIST - $(date)  "
    echo "  Opérateur : $GPG_USER"
    echo "==============================================="
} > "$REPORT_FILE"

# Ensure pv is installed for progress
if ! command -v pv &>/dev/null; then
    echo "pv n'est pas installé. Installation..."
    sudo apt update && sudo apt install -y pv
fi

for DISK in $SELECTED_DISKS; do
    SERIAL=$(lsblk -dno SERIAL "$DISK")
    log_info "\n\e[34mTraitement de $DISK (S/N: $SERIAL)\e[0m"
    
    # Audit SMART
    HEALTH=$(smartctl -H "$DISK" 2>/dev/null | grep -i "result" | awk -F: '{print $2}' | xargs)
    log_info "Santé SMART : ${HEALTH:-INCONNU}"

    # Effacement NIST
    if [[ "$DISK" == *nvme* ]]; then
        log_info "Action : Effacement NIST NVMe en cours..."
        nvme format "$DISK" --ses=2 --force &>/dev/null || nvme format "$DISK" --ses=1 --force &>/dev/null
        log_info "Effacement NVMe terminé"
    else
        log_info "Action : Effacement NIST HDD en cours..."
        DISK_BYTES=$(blockdev --getsize64 "$DISK")

        # Run dd in background and save PID
        dd if=/dev/zero bs=1M count=$(($DISK_BYTES / 1024 / 1024)) 2>/dev/null | pv -s $DISK_BYTES | dd of="$DISK" bs=1M conv=notrunc status=none &
        DD_PID=$!

        # Monitor for keypress 'q' to abort
        echo -e "\nAppuyez sur 'q' puis Enter pour annuler le wipe..."
        while kill -0 $DD_PID 2>/dev/null; do
            read -t 1 -n 1 key
            if [[ "$key" == "q" ]]; then
                kill -SIGINT $DD_PID
                log_info "Effacement annulé par l'utilisateur !"
                wait $DD_PID 2>/dev/null
                break
            fi
        done

        # Wait for dd to finish if not aborted
        wait $DD_PID 2>/dev/null
        log_info "Effacement HDD terminé"
    fi

    # Validation
    if ! dd if="$DISK" bs=1M count=5 2>/dev/null | od -A n -X | grep -v "0000000" > /dev/null; then
        log_info "Résultat : CONFORME"
    else
        log_info "Résultat : ÉCHEC"
    fi
done

# --- SIGNATURE ET ENVOI ---
if gpg --batch --yes --clear-sign --local-user "$GPG_USER" "$REPORT_FILE"; then
    send_to_server "${REPORT_FILE}.asc"
    rm "$REPORT_FILE" "${REPORT_FILE}.asc"
else
    send_to_server "$REPORT_FILE"
fi

echo -e "\n--- OPÉRATION TERMINÉE ---"
