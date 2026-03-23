1. download rufus to create a default linux bootable usb key
2. boot on the usb key and download diskwipepro from this page
3. extract the .sh file anywhere on the usb key from the .zip archive 

7. install the dependancies using the following command in the terminal  :  

sudo apt update && sudo apt install smartmontools nvme-cli GnuPG openssh-client -y

8.  rendez le script exécutable avec la commande : 

chmod +x nist-wipe.sh

9. exécutez le script en utilisant : 

sudo ./nist-wipe.sh /dev/*répertoire du disque 

par exemple : 

sudo ./nist-wipe.sh /dev/sdb pour votre disque primaire ou 
sudo ./nist-wipe.sh /dev/sdc pour un disque secondaire and so on.


