
echo "************************ Setup avahi mDNS ************************"
sudo dnf install avahi

# sudo systemctl start avahi-daemon
# sudo systemctl enable avahi-daemon
sudo systemctl enable --now avahi-daemon

# Firewall
sudo firewall-cmd --permanent --add-service=mdns
sudo firewall-cmd --reload

sleep 5s # Check mDNS *.local in status

##################################################
# Debugging
##################################################

# sudo systemctl status avahi-daemon 
sleep 5s # Check mDNS *.local in status
