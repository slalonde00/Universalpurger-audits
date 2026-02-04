1. use a program to create a custom linux bootable usb key
2. add the software called memtest86 to test the ram as you cannot test ram while booted on a usb key, since linux is loading into the ram when booting from a usb key
3. copy paste the .sh file anywhere on the usb key
4. connect the usb key to a compuuter you wish to erasee data on
5. boot onto the usb key
6. use memtest86 to test the ram
7. install the depenaancies using the following command :   
sudo apt update && sudo apt install smartmontools nvme-cli GnuPG openssh-client -y
8.  rendez le acript exécutable avec la commande : 
chmod +x wipe_audit.sh
9. exécutez le script en utilisant : sudo ./wipe_audit.sh
