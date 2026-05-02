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
sudo dnf remove -y libreoffice-calc libreoffice-draw libreoffice-impress libreoffice-math libreoffice-writer libreoffice-help

sudo dnf remove -y neochat kolourpaint khelpcenter mullvad-browser

# Games
sudo dnf remove -y kmahjongg kmines kpat


