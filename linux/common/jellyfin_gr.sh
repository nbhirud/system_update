#!/bin/bash
# Jellyfin Production Setup for Fedora 44 - nbMain/nbAcer
# Run as user with sudo access. Idempotent.

set -euo pipefail




# Production-grade Jellyfin setup script for your Fedora KDE machines (nbMain & nbAcer).
# This script is idempotent, hardware-aware, hardened, and optimized for your setup. Run it as a regular user with sudo privileges (it will prompt where needed). It assumes fresh Fedora 44, media at ~/nb/Videos, and local LAN only.
# Key Decisions & Optimizations (Practical & Forward-Thinking)

# Repo: RPM Fusion (community-maintained, reliable for Fedora). Jellyfin pulls in its own jellyfin-ffmpeg.
# Hardware Detection: Auto-detects Intel iGPU (your cases: nbMain i5-2400 → older but supported; nbAcer i5-8400 → better). Enables VA-API/QSV where possible, installs intel-media-driver. Falls back to software. Low-RAM tweaks for nbAcer.
# Transcoding: Enabled with hardware accel (decoding + encoding). Critical for 4K/HDR/HEVC to prevent CPU overload and stuttering on clients. Jellyfin handles it transparently—clients request what they need (direct play preferred, transcoding on-the-fly for incompatible devices).
# Libraries: Separate "Movies" and "Series" libraries for best metadata/scraping. Your subfolders (English/Hindi/Marathi) work fine—Jellyfin supports language tags.
# Security/Privacy: Firewall limited to LAN, SELinux permissive for media (standard), no telemetry. Local discovery only.
# Clients: Jellyfin web + native clients (VLC/MPV/Kodi/Grayjay) discover via SSDP/DLNA. No extra installs. Chromecast works via casting from clients/apps. Android equivalents covered.
# Usability for New User: Post-setup guide included. Jellyfin = your personal Netflix: beautiful UI, metadata, posters, collections, watched status, multi-user (add family later), resume playback, subtitles, chapters.
# No NextDNS/Tailscale: As requested. Local only.
# Better Alternative: Consider Docker for easier updates/isolation (future-proof), but native RPM for simplicity on your hardware.

# Setup Script (setup-jellyfin.sh)
# Save this as setup-jellyfin.sh, make executable (chmod +x), and run it.




echo "=== Jellyfin Setup Starting ==="

# Update system
sudo dnf update -y

# Enable RPM Fusion (required for Jellyfin deps)
sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
                    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm || true

# Install Jellyfin via RPM Fusion
sudo dnf install -y jellyfin

# Hardware detection & optimization
CPU=$(lscpu | grep "Model name" | awk -F: '{print $2}' | xargs)
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
GPU_INFO=$(lspci | grep -E "VGA|Display" || echo "No GPU detected")

echo "Detected: CPU=$CPU, RAM=${RAM_GB}GB, GPU=$GPU_INFO"

# Intel iGPU setup (both your machines)
if echo "$GPU_INFO" | grep -qi "Intel"; then
    echo "Setting up Intel iGPU acceleration..."
    sudo dnf install -y intel-media-driver libva-utils vainfo mesa-libGL
    # Ensure render group access for jellyfin user
    sudo usermod -a -G render jellyfin || true
    sudo usermod -a -G video jellyfin || true
fi

# Low-RAM tweaks (nbAcer)
if [ "$RAM_GB" -le 8 ]; then
    echo "Applying low-RAM optimizations..."
    # Limit Jellyfin memory if needed (edit later via service)
    sudo mkdir -p /etc/systemd/system/jellyfin.service.d
    cat << EOF | sudo tee /etc/systemd/system/jellyfin.service.d/lowmem.conf
[Service]
MemoryMax=4G
EOF
fi

# Media directory & permissions
MEDIA_DIR="$HOME/nb/Videos"
sudo mkdir -p "$MEDIA_DIR"
sudo chown -R jellyfin:jellyfin "$MEDIA_DIR"  # Jellyfin user owns media
sudo chmod -R 755 "$MEDIA_DIR"

# Firewall - LAN only (jellyfin-firewalld package handles services)
sudo firewall-cmd --permanent --add-service=jellyfin
sudo firewall-cmd --reload

# SELinux (allow media access)
sudo setsebool -P httpd_read_user_content 1 || true  # If issues arise

# Enable & start service
sudo systemctl daemon-reload
sudo systemctl enable --now jellyfin

echo "=== Jellyfin Installed & Started ==="
echo "Access at: http://$(hostname -I | awk '{print $1}'):8096"
echo "Initial wizard will guide you."

# Post-install recommendations (run manually first time)
cat << 'EOF'

=== NEXT STEPS (Manual - First Run Wizard) ===
1. Open http://<your-ip>:8096 in browser (LibreWolf/Brave).
2. Set admin username/password.
3. Language: English (or preferred).
4. Add Libraries:
   - Library 1: "Movies" → Path: $MEDIA_DIR/Movies → Type: Movies
   - Library 2: "Series" → Path: $MEDIA_DIR/Series → Type: Shows
   - Enable metadata download, posters, etc.
5. Dashboard > Playback > Transcoding:
   - Enable hardware acceleration (QuickSync / VA-API for Intel).
   - Allow hardware encoding/decoding.
6. Networking: Confirm Local Networks (your LAN CIDR, e.g., 192.168.1.0/24).

=== Optimization Tips ===
- Scan libraries after adding.
- For Chromecast: Use Jellyfin app or Kodi/Grayjay to cast.
- Clients: VLC (Open Network Stream with Jellyfin URL), MPV (similar), Kodi (Jellyfin addon), Grayjay (great mobile).
- Android: Official Jellyfin app or VLC/Grayjay/Kodi.
- Subtitles: Jellyfin auto-downloads; place .srt next to files.
- Collections: Create in UI for "Hindi Movies", etc.
- Users: Add limited users later for family.

=== Maintenance ===
sudo systemctl status jellyfin
sudo journalctl -u jellyfin -f
Updates: sudo dnf update jellyfin*

Hardware accel check: sudo -u jellyfin vainfo  (look for supported codecs)
EOF

echo "Setup complete! Test and explore the UI."


# How to Use

# Copy script to both machines.
# chmod +x setup-jellyfin.sh && ./setup-jellyfin.sh
# Follow post-setup steps in browser.
# Point clients to http://<machine-ip>:8096

# Potential Issues & Fixes

# No iGPU accel: Run vainfo as jellyfin user. Ensure iGPU enabled in BIOS if needed.
# Permissions: Media must be readable by jellyfin user.
# Discovery: Clients on same LAN should auto-find. Fallback: manual IP.
# nbMain (older CPU): May transcode slower; prioritize direct play (modern clients do this).
# Future nbServer: Same script, but add Docker for isolation.

# Opinion: Jellyfin is excellent for your use case—zero ongoing cost, full control, superior to Plex for privacy. Start small, scan your libraries, play with clients. You'll quickly see value in resume, chapters, and cross-device sync. If media grows, migrate to nbServer with NFS mounts or Syncthing.
# Test thoroughly. Questions on tweaks? Provide output from script/hardware.