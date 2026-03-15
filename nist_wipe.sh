#!/bin/bash
# Vérification ROOT
[[ $EUID -ne 0 ]] && echo -e "\e[31mErreur: Exécutez en ROOT.\e[0m" && exit 1

# --- CONFIGURATION INTERACTIVE ---
echo -e "\e[36m=== CONFIGURATION DE L'AUDIT ===\e[0m"
read -p "Email pour identification (pour logs locaux) : " GPG_USER

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

# --- CHOIX DE LA TABLE DE PARTITIONS ---
echo -e "\nChoisissez le type de table de partitions à créer après le wipe :"
echo "1) GPT (moderne, recommandé pour UEFI)"
echo "2) MBR / DOS (ancien BIOS)"
read -p "Entrez 1 ou 2 [1] : " PART_CHOICE
PART_CHOICE=${PART_CHOICE:-1}
[[ "$PART_CHOICE
