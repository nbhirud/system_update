
echo "************************ Setup avahi mDNS ************************"
sudo dnf install avahi

sudo systemctl start avahi-daemon
sudo systemctl enable avahi-daemon

sudo systemctl status avahi-daemon 
sleep 5s # Check mDNS *.local in status
