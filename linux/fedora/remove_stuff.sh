# ➜  ~ dnf list --installed | grep libreo
# libreoffice-calc.x86_64                              1:26.2.2.2-2.fc44                   updates
# libreoffice-core.x86_64                              1:26.2.2.2-2.fc44                   updates
# libreoffice-data.x86_64                              1:26.2.2.2-2.fc44                   updates
# libreoffice-draw.x86_64                              1:26.2.2.2-2.fc44                   updates
# libreoffice-emailmerge.x86_64                        1:26.2.2.2-2.fc44                   updates
# libreoffice-graphicfilter.x86_64                     1:26.2.2.2-2.fc44                   updates
# libreoffice-gtk3.x86_64                              1:26.2.2.2-2.fc44                   updates
# libreoffice-gtk4.x86_64                              1:26.2.2.2-2.fc44                   updates
# libreoffice-help-en.x86_64                           1:26.2.2.2-2.fc44                   updates
# libreoffice-impress.x86_64                           1:26.2.2.2-2.fc44                   updates
# libreoffice-kf6.x86_64                               1:26.2.2.2-2.fc44                   updates
# libreoffice-langpack-en.x86_64                       1:26.2.2.2-2.fc44                   updates
# libreoffice-math.x86_64                              1:26.2.2.2-2.fc44                   updates
# libreoffice-ogltrans.x86_64                          1:26.2.2.2-2.fc44                   updates
# libreoffice-opensymbol-fonts.noarch                  1:26.2.2.2-2.fc44                   updates
# libreoffice-pdfimport.x86_64                         1:26.2.2.2-2.fc44                   updates
# libreoffice-pyuno.x86_64                             1:26.2.2.2-2.fc44                   updates
# libreoffice-ure.x86_64                               1:26.2.2.2-2.fc44                   updates
# libreoffice-ure-common.noarch                        1:26.2.2.2-2.fc44                   updates
# libreoffice-writer.x86_64                            1:26.2.2.2-2.fc44                   updates


# Libreoffice stuff
sudo dnf remove -y libreoffice-calc libreoffice-draw libreoffice-impress libreoffice-math libreoffice-writer libreoffice-help libreoffice-help-en

sudo dnf remove -y neochat kolourpaint khelpcenter mullvad-browser

# Games
sudo dnf remove -y kmahjongg kmines kpat




#!/bin/bash
# Comprehensive KDE Plasma Performance Optimization Script

echo "Applying full KDE Plasma performance optimizations..."

# 1. Disable Baloo File Indexing completely
balooctl6 disable 2>/dev/null || balooctl disable 2>/dev/null

# 2. Disable heavy visual effects (blur, contrast, animations)
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key backgroundContrastEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key slideEnabled false

# 3. Optimize rendering performance and compositor latency for integrated graphics
kwriteconfig6 --file kwinrc --group Compositing --key ScaleMethod 1
kwriteconfig6 --file kwinrc --group Compositing --key Latency 3

# 4. Reload KWin configuration dynamically
if command -v qdbus-qt6 &>/dev/null; then
    qdbus-qt6 org.kde.KWin /KWin org.kde.KWin.reconfigure
elif command -v qdbus &>/dev/null; then
    qdbus org.kde.KWin /KWin org.kde.KWin.reconfigure
else
    dbus-send --session --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure
fi

echo -e "\n[✓] All optimizations applied successfully!"

# Verification check
echo -e "\nVerifying active configuration:"
kreadconfig6 --file kwinrc --group Plugins --key blurEnabled | xargs echo "blurEnabled:"
grep -E "ScaleMethod|Latency" ~/.config/kwinrc
