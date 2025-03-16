
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


###### firewalld #TODO
# https://www.redhat.com/en/blog/how-to-configure-firewalld

sudo dnf install firewall-config # GUI

## basic commands
systemctl status firewalld
# systemctl start --now firewalld
systemctl enable --now firewalld
# systemctl stop firewalld
# systemctl restart firewalld

## config

firewall-cmd --state
# firewall-cmd --reload
firewall-cmd --list-all






# GSConnect firewalld rules
firewall-cmd --permanent --zone=public --add-service=kdeconnect 
firewall-cmd --reload


# SELinux
# TODO

# ufw

# https://linuxconfig.org/how-to-install-and-use-ufw-firewall-on-linux
# https://www.baeldung.com/linux/uncomplicated-firewall


# Fedora comes with firewalld
# Figure out which is better and learn an configure

######################################################
#
######################################################


######################################################
#
######################################################


######################################################
#
######################################################


######################################################
#
######################################################


######################################################
#
######################################################


######################################################
#
######################################################


######################################################
#
######################################################

