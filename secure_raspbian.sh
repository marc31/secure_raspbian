#!/usr/bin/env bash

######################## HELPERS

## Get path of this file
path_of_this_file=$(dirname "$0")
path_of_this_file=$(cd "${path_of_this_file}" && pwd)

# colorize and formatting command line
green='\x1B[0;32m'
cyan='\x1B[1;36m'
blue='\x1B[0;34m'
grey='\x1B[1;30m'
red='\x1B[0;31m'
bold='\033[1m'
normal='\033[0m'

function say_blue() {
	echo -e "${blue}${bold}$1${normal}"
}

function say_red() {
	echo -e "${red}${bold}$1${normal}"
}

function say_green() {
	echo -e "${green}${bold}$1${normal}"
}

function say_grey() {
	echo -e "${green}$1${normal}"
}

# 	Ask Something With Choice
# 		$1     : MESSAGE
# 		$2     : DEFAULT (AS INDEX IN $choices) IF USER PROVIDES AN EMPTY ANSWER
# 		$3-n   : CHOICES (WITH UNIQUE LEADING CHARACTER, E.G: "yes" "no" "abort")
# 		returns: 0, AND SETS $BOTASK_ANSWER TO THE ANSWER'S INDEX WITHIN $choices
#	------------------------------------------------------------
function ask_choice() {
	## EASE OUR DEVS' LIFE
	if ! [[ $2 =~ ^-?[0-9]+$ ]]; then
		say_red "'$2' IS NOT AN INTEGER"
		return 1
	fi

	local msg="$1"
	local def_choice=$2
	shift 2
	local choices=("$@")
	local prompt=""
	BOTASK_ANSWER="$def_choice" #XXX: ACCESS TO USER'S CHOICE
	for c in "$@"; do
		if [[ "$c" == "${choices[$def_choice]}" ]]; then
			prompt="${prompt}${blue}${bold}[${c:0:1}]${c:1}${normal} "
		else
			prompt="${prompt}[${c:0:1}]${c:1} "
		fi
	done

	while true; do
		say_green "$msg"
		echo -ne "$prompt> "
		read -r ans

		if [ -n "$ZSH_VERSION" ]; then
			# assume Zsh
			for ((i = 1; i <= ${#choices[@]}; i++)); do
				test -z "${ans}" && return 0 #TDL: PRESSING SPACE (RETURN OK)
				c=${choices[$i]}
				if [[ "${ans}" == "${c:0:1}" ]]; then
					echo
					BOTASK_ANSWER=$i && return 0 #XXX: set -e SO RETURN 0
				fi
			done
		elif [ -n "$BASH_VERSION" ]; then
			for ((i = 0; i <= ${#choices[@]} - 1; i++)); do
				test -z "${ans}" && return 0 #TDL: PRESSING SPACE (RETURN OK)
				c=${choices[$i]}
				if [[ "${ans}" == "${c:0:1}" ]]; then
					echo
					BOTASK_ANSWER=$i && return 0 #XXX: set -e SO RETURN 0
				fi
			done
		fi
		say_red "Please choose a valid answer" ## USER MISTYPED: EMBARRASSMENT
	done
}

# 	Generate a random password
#  		$1 = number of characters; defaults to 32
# 		remove LC_CTYPE in linux this is for mac
# 		you can remplace $CHAR by "a-zA-Z0-9-_\$\?\@\.\!"
#   -----------------------------------------------------------------------------------
function randpass() {
	env LC_CTYPE=C tr -cd "a-zA-Z0-9-_\\$\\?\\@\\.\\!" </dev/urandom | head -c "${1:-32}"
}

function checkandinstallprog() {
	command -v "$1" >/dev/null 2>&1 || sudo apt install "$1"
}

function makesysD() {
	if [ -z "$1" ]; then
		say_red "You must give a name for the script"
		return 1
	fi

	if [ -f "${path_of_this_file}/$1.init" ]; then
		say_red "The file ${path_of_this_file}/$1.init must exists"
		return 1
	fi

	if [ -f "${path_of_this_file}/$1.service" ]; then
		say_red "The file ${path_of_this_file}/$1.service must exists"
		return 1
	fi

	say_blue "Make a systemD script $1"

	say_grey "Link to /usr/local/bin"
	sudo ln -sf "${path_of_this_file}/$1.init" "/usr/local/bin/$1.init"

	say_grey "Make script executable"
	sudo chmod u+x "/usr/local/bin/$1.init"

	say_grey "Copy to /etc/systemd/system/$1.service"
	sudo cp -rf "${path_of_this_file}/$1.service" "/etc/systemd/system/$1.service"

	say_grey "Enable service"
	sudo systemctl enable "$1"

	say_grey "Start service"
	sudo systemctl start "$1"
}

# Test if function exist
# use like this :
#   if fnExists paramfct; then
#     echo 'paramfct exsists'
#   fi
fnExists() {
	type "$1" 2>/dev/null | grep -q 'is a function'
}

######################## END HELPERS

# In the param.sh file you can give some config
# to don't aswer at all question here
if [ -f "params.sh" ]; then source "params.sh"; fi

# Add a new user or change pi password
function addnewuser() {
	# Create new user or change pi password
	ask_choice "Add new user ? (it's better for security reason)" 1 no yes
	if [[ $BOTASK_ANSWER == 1 ]]; then

		ADDNEWUSER=true

		while [ -z "$NEWUSERNAME" ] && say_grey "New user name ?" && read -r NEWUSERNAME && [ -z "$NEWUSERNAME" ]; do
			say_red "No-no, please, no blank passwords!"
		done

		# Add new user
		sudo adduser "$NEWUSERNAME"

		# Check if the new user exist
		if [ "$(sudo getent passwd | grep -c "^${NEWUSERNAME}:")" -ne 1 ]; then
			say_red "Problem when creating the user $NEWUSERNAME ! "
			exit 1
		fi

		# Add user to sudo minimun
		sudo adduser "$NEWUSERNAME" sudo

		# Add newuser to all pi groups
		PIGROUPS=$(groups)
		for EACH in $(echo "$PIGROUPS" | grep -o -e "[^ ]*"); do
			sudo adduser "$NEWUSERNAME" "$EACH"
		done

		# Make a ssh directory
		sudo mkdir "/home/$NEWUSERNAME/.ssh"
		sudo chown "$NEWUSERNAME":"$NEWUSERNAME" "/home/$NEWUSERNAME/.ssh/"

		# Lock the pi user
		say_blue "Lock the pi user"
		sudo passwd -l pi

	else
		say_blue "Change the pi Password"
		sudo passwd
	fi
}

# Generate new RSA host keys
function generatenewrsa() {
	sudo rm /etc/ssh/ssh_host_*
	sudo dpkg-reconfigure openssh-server
}

# USB auto-mount
function usbautomount() {
	# pauliucxz https://raspberrypi.stackexchange.com/questions/66169/auto-mount-usb-stick-on-plug-in-without-uuid
	# This script mounts drives to /media/usb*,
	# so make sure those folders aren't occupied.
	# If you want a cleaner look, don't create any folders.
	ask_choice "Enable usb auto mount in /media with pmout ?" 1 no yes
	if [[ $BOTASK_ANSWER == 1 ]]; then
		sudo apt-get install pmount

		# Add something to /etc/udev/rules.d/usbstick.rules
		echo 'ACTION=="add", KERNEL=="sd[a-z][0-9]", TAG+="systemd", ENV{SYSTEMD_WANTS}="usbstick-handler@%k"' | sudo tee -a /etc/udev/rules.d/usbstick.rules

		cat >~/tmpusbdisk <<EOL
  [Unit]
  Description=Mount USB sticks
  BindsTo=dev-%i.device
  After=dev-%i.device

  [Service]
  Type=oneshot
  RemainAfterExit=yes
  ExecStart=/usr/local/bin/automount %I
  ExecStop=/usr/bin/pumount /dev/%I
EOL

		sudo chown root:root ~/tmpusbdisk
		sudo mv ~/tmpusbdisk /lib/systemd/system/usbstick-handler@.service

		cat >~/tmpusbdiskautomount <<EOL
#!/bin/bash

PART=\$1
FS_LABEL=\`lsblk -o name,label | grep \${PART} | awk '{print \$2}'\`

if [ -z \${FS_LABEL} ]
then
    /usr/bin/pmount --umask 000 --noatime -w --sync /dev/\${PART} /media/\${PART}
else
    /usr/bin/pmount --umask 000 --noatime -w --sync /dev/\${PART} /media/\${FS_LABEL}_\${PART}
fi
EOL

		sudo chown root:root ~/tmpusbdiskautomount
		sudo mv ~/tmpusbdiskautomount /usr/local/bin/automount
		sudo chmod +x /usr/local/bin/automount
	fi
}

# Replace the hostname in /etc/hosts and /etc/hostname.
# Reboot to apply it
function changehostname() {
	ask_choice "Do I need to change the hostname (default : ${HOSTNAME}) ? " 1 no yes
	if [[ $BOTASK_ANSWER == 1 ]]; then

		while [ -z "$NEWHOSTNAME" ] && say_grey "What hostname do you whant ?" && read -r NEWHOSTNAME && [ -z "$NEWHOSTNAME" ]; do
			say_red "No-no, please, no blank !"
		done

		sudo sed -i "s/${HOSTNAME}$/${NEWHOSTNAME}/" /etc/host{s,name}
		say_grey 'Need a reboot to see new hostname'
	fi
}

# Improve ssh security
function improvessh() {
	ask_choice "Do i need to enhance security for ssh ?" 1 no yes
	if [[ $BOTASK_ANSWER == 1 ]]; then

		# Make sshusers group
		sudo addgroup sshusers

		# Add user to this group
		if [ "$ADDNEWUSER" = true ]; then
			sudo adduser "$NEWUSERNAME" sshusers
		else
			sudo adduser pi sshusers
		fi

		while ! [[ $SSHPORT =~ ^[0-9]+$ ]] && say_grey "New ssh port ?" && read -r SSHPORT && ! [[ $SSHPORT =~ ^[0-9]+$ ]]; do
			say_red "No-no, please, no blank port!"
		done

		#sudo sed -i "s/#Port 22/Port ${SSHPORT}/" /etc/ssh/sshd_config

		sudo tee -a /etc/ssh/sshd_config <<EOL
Port ${SSHPORT}
Protocol 2

LoginGraceTime 120
PermitRootLogin no
StrictModes yes
MaxAuthTries 4
MaxStartups 3

PasswordAuthentication yes
RSAAuthentication no
UsePAM no
KerberosAuthentication no
GSSAPIAuthentication no
ChallengeResponseAuthentication no

PermitEmptyPasswords no
X11Forwarding no
AllowGroups sshusers
EOL
	fi
}

# ennable SSH
function enablessh() {
	ask_choice "Do i need to enable ssh ?" 1 no yes
	if [[ $BOTASK_ANSWER == 1 ]]; then
		sudo systemctl enable ssh
		sudo systemctl start ssh
	fi
}

# Add a DuckDns
function duckdns() {
	say_blue 'DuckDns it a free dynamic DNS see: https://www.duckdns.org/'
	ask_choice "If you have a DuckDns do you whant I make a cron job ?" 0 no yes
	if [[ $BOTASK_ANSWER == 1 ]]; then

		while [ -z "$DUCKDNSDOMAIN" ] && say_grey "What is your DuckDnsUrl ( example.duckdns.org ) ?" && read -r DUCKDNSDOMAIN && [ -z "$DUCKDNSDOMAIN" ]; do
			say_red "No-no, please, no blank !"
		done

		while [ -z "$DUCKDNSTOKEN" ] && say_grey "What is your DuckDnsUrl token ?" && read -r DUCKDNSTOKEN && [ -z "$DUCKDNSTOKEN" ]; do
			say_red "No-no, please, no blank !"
		done

		checkandinstallprog curl

		if sudo crontab -l | grep -Fq "* * * * 1 curl -k -o /tmp/duckdns.log \"https://www.duckdns.org/update?domains=$DUCKDNSDOMAIN&token=$DUCKDNSTOKEN&ip=\" >/dev/null 2>&1"
		then
			say_red "DuckDns cron job is already exists"
		else
			(sudo crontab -l && echo "* * * * 1 curl -k -o /tmp/duckdns.log \"https://www.duckdns.org/update?domains=$DUCKDNSDOMAIN&token=$DUCKDNSTOKEN&ip=\" >/dev/null 2>&1") | sudo crontab -
		fi

		say_grey 'You can see log in /tmp/duckdns.log'
	fi
}

# Install ufw
function installufw() {
	ask_choice "Do i need to install a firewall ufw ?" 1 no yes
	if [[ $BOTASK_ANSWER == 1 ]]; then
		sudo apt install -y ufw
		sudo ufw allow "$SSHPORT"
		sudo ufw enable

		say_green 'You can see rules with sudo ufw status verbose'
		say_green 'You can allow traffics with sudo ufw allow PORT'
		say_green 'Check ufw on internet for more information'
	fi
}

function installfail2ban() {
	ask_choice "Do i need to install fail2ban ? Enable it only for ssh" 1 no yes
	if [[ $BOTASK_ANSWER == 1 ]]; then
		sudo apt install -y fail2ban

		sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

		if [ -z "$SSHPORT" ]; then
			sed -i'' "s/port[ ]*=[ ]*ssh/port = ssh,${SSHPORT}/" /etc/fail2ban/jail.local
		fi

		sudo fail2ban-client reload
		sudo fail2ban-client status

	fi
}

function default() {

	say_blue "default user/password : pi/raspberry"

	sudo apt update
	sudo apt upgrade -y

	ask_choice "Do I need to update system distribution ? " 1 no yes
	if [[ $BOTASK_ANSWER == 1 ]]; then
		sudo apt dist-upgrade
	fi

	ask_choice "Do I need to update raspberry firmware ? " 1 no yes
	if [[ $BOTASK_ANSWER == 1 ]]; then
		sudo rpi-update
	fi

	# Add a new user or change pi password
	addnewuser

	#Generate new RSA host keys
	generatenewrsa

	# Replace the hostname in /etc/hosts and /etc/hostname.
	changehostname

	say_blue "Lunch raspi-config"
	say_grey "You must change time zone, local, keyboard data, Expand Filesystem, wifi"
	say_grey "May be you can change overclock"
	say_red "Don't change default password because we have already did it and if you do"
	say_red "that you going to unlock pi user"
	say_grey "Press enter to continue"
	read -r
	sudo raspi-config

	# Enable usb auto mount in /media with pmout ?
	usbautomount

	# Improve ssh security
	improvessh

	# ennable SSH
	enablessh

	# add duckdns cron job
	duckdns

	# Install ufw and open ssh port
	installufw

	# Install fail2ban protect sshport
	installfail2ban

	say_blue "Unattended-upgrades install automatically update"
	say_blue "Needrestart restart automatically services that uses old library"
	ask_choice "Do i need to install then ?" 0 no yes
	if [[ $BOTASK_ANSWER == 1 ]]; then
		sudo apt install unattended-upgrades needrestart -y
		sudo dpkg-reconfigure unattended-upgrades
	fi

	say_blue 'I clean apt'
	sudo apt-get autoremove -y
	sudo apt-get clean

	# Check if paramfct exsist in param and execute it
	if fnExists paramfct; then
		paramfct
	fi

	say_blue "Reboot now"
	sudo reboot now
}

function help() {
	echo -n "$(basename "$0") script to secure Raspbian after fresh install

where:
    -h|--help : show this help text
    -a|addnewuser : add a new user or change pi password
    -g|generatenewrsa : Generate new RSA host keys
    -c|changehostname : Replace the hostname in /etc/hosts and /etc/hostname
    -u|usbautomount : Enable usb auto mount in /media with pmout
    -issh|improvessh : Improve ssh security
    -essh|enablessh : enablessh
    -d|duckdns : add duckdns cron job
    -iufw|installufw : Install ufw and open ssh port
    -ifail|installfail2ban : Install fail2ban protect sshport
"
}

case "$1" in
-a | addnewuser)
	addnewuser
	exit
	;;
-g | generatenewrsa)
	generatenewrsa
	exit
	;;
-c | changehostname)
	changehostname
	exit
	;;
-u | usbautomount)
	usbautomount
	exit
	;;
-issh | improvessh)
	improvessh
	exit
	;;
-essh | enablessh)
	enablessh
	exit
	;;
-d | duckdns)
	duckdns
	exit
	;;
-iufw | installufw)
	installufw
	exit
	;;
-ifail | installfail2ban)
	installfail2ban
	exit
	;;
'')
	default
	exist
	;;
-h | --helph | *)
	help
	exit
	;;
esac
