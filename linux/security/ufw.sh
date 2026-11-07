
######################################################
# From Fedora
######################################################

# # UFW
# # Recommended rules from https://christitus.com/linux-security-mistakes/
# sudo ufw limit 22/tcp
# sudo ufw allow 80/tcp
# sudo ufw allow 443/tcp
# sudo ufw default deny incoming
# sudo ufw default allow outgoing
# # Enable ufw
# sudo ufw enable
# #sudo systemctl enable ufw # Didn't work for some reason
# #sudo systemctl start ufw # Didn't work for some reason
# # sudo ufw status numbered
# # sudo ufw delete 7 # Use numbers from above numbered command

# ufw

# https://linuxconfig.org/how-to-install-and-use-ufw-firewall-on-linux
# https://www.baeldung.com/linux/uncomplicated-firewall

########################################3
# from ubuntu
##########################################


# Firewall
sudo apt install -y ufw



# UFW
# Recommended rules from https://christitus.com/linux-security-mistakes/
sudo ufw limit 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
# Enable ufw
sudo ufw enable
#sudo systemctl enable ufw # Didn't work for some reason
#sudo systemctl start ufw # Didn't work for some reason
# sudo ufw status numbered
# sudo ufw delete 7 # Use numbers from above numbered command

# AppArmor
# https://ubuntu.com/server/docs/security-apparmor
sudo apt install apparmor-profiles
sudo apparmor_status
# sudo systemctl reload apparmor.service
sudo systemctl enable apparmor.service
sudo systemctl start apparmor.service

########################################3
# from alpine
##########################################

doas apk add ufw

doas ufw limit ssh/tcp
sudo ufw allow http/tcp
sudo ufw allow https/tcp
doas ufw default deny incoming
doas ufw default allow outgoing
doas ufw enable
doas ufw status

# https://wiki.alpinelinux.org/wiki/OpenRC
# doas rc-status # View status of all services
# doas rc-status --list # View service list
doas rc-update add ufw
doas rc-service ufw start

######################################################
# Originally in this file
######################################################

sudo apt update
sudo apt dist-upgrade

sudo apt install -y ufw

sudo systemctl status ufw # check status

### configure
sudo ufw disable
sudo ufw status

# default rules:
sudo ufw default allow outgoing
sudo ufw default deny incoming # careful - don't lock yourself out

# other settings 
sudo ufw allow ssh # to not lock yourself out
# ufw allow 22 # same as above


sudo ufw status
sudo ufw enable
sudo ufw status

# if you are running http website
sudo ufw allow http/tcp # better than 80
# ufw allow 80 # similar than above

# enable ssh from only your IP:
# ensure first that your IP doesn't keep changing (dynamic) before doing this
sudo ufw allow from <xx.yy.zz.aa (your IP)> to any port 22 proto tcp

sudo ufw status


# to remove a rule:
sudo ufw status numbered # copy the number to delete
sudo ufw delete 1

sudo ufw status

sudo systemctl enable ufw
sudo systemctl start ufw
sudo systemctl status ufw

# Can modify default ufw configuration from here (but use above method to be safe): 
# sudo nano /etc/default/ufw
