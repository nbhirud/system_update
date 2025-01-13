

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