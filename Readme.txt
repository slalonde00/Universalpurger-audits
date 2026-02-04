1. use a program to create a custom linux bootable usb key
2. add the software called memtest86 to test the ram as you cannot test ram while booted on a usb key, since linux is loading into the ram when booting from a usb key
3. copy paste the .sh file anywhere on the usb key
4. connect the usb key to a computer you wish to erase data on
5. boot onto the usb key
6. use memtest86 to test the ram
7. install the dependancies using the following command :  

sudo apt update && sudo apt install smartmontools nvme-cli GnuPG openssh-client -y

8.  rendez le script exécutable avec la commande : 

chmod +x wipe_audits.sh

9. exécutez le script en utilisant : 

sudo ./wipe_audits.sh

10. suivez les instructions à l'écran pour utiliser le script et effacer des disque et pour envoyer un rapport signé unique à un serveur distant de votre choix
