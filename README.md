Script to secure Raspbian after fresh install.
-----------------------


Run this bash script after flashing raspbian lite on SD card.

This script install some basis to secure your server.

- Update the system/dist/firmware
- Create a new user and block pi user
- Change Host Name
- Generate new RSA host keys
- Usb auto mount (via pmount)
- Enable/Secure ssh
- Add a DuckDns (DuckDns it a free dynamic DNS see: https://www.duckdns.org/)
- Install a firewall ufw
- Install Fail2ban
- Install Unattended-upgrades that install automatically update"
- Install Needrestart restart automatically services that uses old library


You can put some default configuration in the params.exemple.sh just rename it params.sh