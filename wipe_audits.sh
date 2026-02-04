#!/bin/bash
set -o pipefail

#######################################
# ROOT CHECK
#######################################
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31mErreur: Exécutez en ROOT.\e[0m"
    exit 1
fi

#######################################
# DEPENDENCY CHECK
#######################################
REQUIRED_CMDS=(lsblk smartctl gpg scp shred dd od awk grep)
for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo -e "\e[31mCommande manquante: $cmd\e[0m"
        exit 1
    }
done

#######################################
# INTERACTIVE CONFIG
#######################################
echo -e "\e[36m=== CONFIGURATION DE L'AUDIT ===\e[0m"
read -rp "Email pour signature GPG : " GPG_USER
read -rp "IP Serveur : " REMOTE_HOST
read -rp "User SSH [root] : " REMOTE_USER
REMOTE_USER=${REMOTE_USER:-root}
read -rp "Dossier distant [/tmp] : " REMOTE_DIR
REMOTE_DIR=${REMOTE_DIR:-/tmp}

#######################################
# DISK SELECTION
#######################################
echo -e "\n\e[33m[CHOIX DU DISQUE]\e[0m"
mapfile -t DISK_LIST < <(lsblk -dno NAME,SIZE,MODEL | grep -Ev "loop|ram")

echo "0) TOUS LES DISQUES"
for i in "${!DISK_LIST[@]}"; do
    printf "%d) %s\n" "$((i+1))" "${DISK_LIST[$i]}"
done

read -rp "Sélectionnez le numéro du disque à traiter : " DISK_CHOICE

# Validate numeric input
if ! [[ "$DISK_CHOICE" =~ ^[0-9]+$ ]]; then
    echo "Choix invalide."
    exit 1
fi

if (( DISK_CHOICE == 0 )); then
    SELECTED_DISKS=$(lsblk -dno NAME | grep -Ev "loop|ram" | awk '{print "/dev/"$1}')
else
    if (( DISK_CHOICE < 1 || DISK_CHOICE > ${#DISK_LIST[@]} )); then
        echo "Choix invalide."
        exit 1
    fi
    DISK_NAME=$(awk '{print $1}' <<< "${DISK_LIST[$((DISK_CHOICE-1))]}")
    SELECTED_DISKS="/dev/$DISK_NAME"
fi

#######################################
# REPORT SETUP
#######################################
REPORT_FILE="audit_$(date +%Y%m%d_%H%M%S).txt"

log_info() {
    echo -e "$1" | tee -a "$REPORT_FILE"
}

send_to_server() {
    scp -o BatchMode=yes -o ConnectTimeout=10 \
        "$1" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}" \
        && echo -e "\e[32m[OK] Rapport envoyé.\e[0m" \
        || echo -e "\e[31m[!] Échec envoi SCP.\e[0m"
}

#######################################
# REPORT HEADER
#######################################
{
    echo "==============================================="
    echo "  RAPPORT D'EFFACEMENT NIST - $(date)"
    echo "  Opérateur : $GPG_USER"
    echo "==============================================="
} > "$REPORT_FILE"

#######################################
# DISK PROCESSING
#######################################
for DISK in $SELECTED_DISKS; do
    [[ -b "$DISK" ]] || {
        log_info "Erreur: $DISK n'est pas un périphérique bloc."
        continue
    }

    SERIAL=$(lsblk -dno SERIAL "$DISK")
    log_info "\n\e[34mTraitement de $DISK (S/N: ${SERIAL:-INCONNU})\e[0m"

    HEALTH=$(smartctl -H "$DISK" 2>/dev/null | awk -F: '/result/{print $2}' | xargs)
    log_info "Santé SMART : ${HEALTH:-INCONNU}"

    log_info "Action : Effacement NIST en cours..."

    if [[ "$DISK" == *nvme* ]]; then
        if ! nvme format "$DISK" --ses=2 --force &>/dev/null && \
           ! nvme format "$DISK" --ses=1 --force &>/dev/null; then
            log_info "ERREUR: Effacement NVMe échoué"
            continue
        fi
    else
        if ! shred -v -n 1 -z "$DISK" &>/dev/null; then
            log_info "ERREUR: shred a échoué"
            continue
        fi
    fi

    ###################################
    # BASIC VALIDATION
    ###################################
    if ! dd if="$DISK" bs=1M count=5 2>/dev/null \
        | od -A n -X | grep -vq "0000000"; then
        log_info "Résultat : CONFORME"
    else
        log_info "Résultat : ÉCHEC"
    fi
done

#######################################
# SIGN & SEND
#######################################
if gpg --batch --yes --clear-sign --local-user "$GPG_USER" "$REPORT_FILE" 2>/dev/null; then
    send_to_server "${REPORT_FILE}.asc"
    rm -f "$REPORT_FILE" "${REPORT_FILE}.asc"
else
    log_info "ATTENTION: Signature GPG échouée"
    send_to_server "$REPORT_FILE"
fi

echo -e "\n\e[32m--- OPÉRATION TERMINÉE ---\e[0m"
