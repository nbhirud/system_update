
######################################
## Useful commands, etc
######################################


dconf write /org/gnome/desktop/interface/font-name "'Ubuntu Nerd Font 11'"
dconf write /org/gnome/desktop/interface/document-font-name "'Ubuntu Nerd Font 11'"
dconf write /org/gnome/desktop/wm/preferences/titlebar-font "'Ubuntu Nerd Font Bold 11'"
dconf write /org/gnome/desktop/interface/monospace-font-name "'JetBrainsMono Nerd Font 10'"

# You can also use the gsettings commandline tool instead of the Dconf Editor GUI tool

# Example font search for setting as default as monospace font for firefox
# fc-list | grep Nerd | grep -v Propo | grep -v Bold | grep -v Condense | grep -v Extra | grep -v Light | grep -v Italic | grep -v Thin | grep -v Medium | grep -v Black | grep "Noto" 

# print font family and style
# fc-list : family style


######################################
## from Alpine 
######################################

# Fonts: https://wiki.alpinelinux.org/wiki/Fonts
sudo apk add font-terminus font-inconsolata font-dejavu font-noto font-noto-cjk font-awesome font-noto-extra font-noto-devanagari 
fc-cache -fv # display the font locations and to update the cache

######################################
## from Fedora 40 
######################################
# Also check
# https://github.com/powerline/fonts
# https://github.com/powerline/fonts/blob/master/install.sh



cd ~/nb/CodeProjects
git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git
# delete using script


# fonts
mkdir -p ~/.local/share/fonts
# paste folder 
fc-cache -fr 
# fc-list | grep "JetBrains" 



# Better Fonts:
# sudo dnf copr enable dawid/better_fonts -y
# sudo dnf install fontconfig-font-replacements -y
# sudo dnf install fontconfig-enhanced-defaults -y

# Change default fonts using GNOME Tweaks
# Change app specific fonts 






######################################
## from Fedora 41
######################################

mkdir nb
mkdir nb/CodeProjects
cd nb/CodeProjects

git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git

cd nerd-fonts
find . -name "*.md" -type f -delete
find . -name "*.txt" -type f -delete
find . -name "LICENSE" -type f -delete
find . -name ".uuid" -type f -delete

mkdir -p ~/.local/share/fonts # this fonts folder is absent by default
cp ~/nb/CodeProjects/nerd-fonts/patched-fonts ~/.local/share/fonts/nerd-fonts -r
rm -rf ~/nb/CodeProjects/nerd-fonts

fc-cache -fr
fc-list | grep "JetBrains"


######################################
## Ubuntu
######################################


##### Fonts setup early to make zsh look good from beginning (needs nerd fonts)

# Install some fonts
# sudo apt install fonts-jetbrains-mono fonts-roboto fonts-cascadia-code fonts-firacode # Covered by nerd-fonts below, so skip this

# https://needforbits.wordpress.com/2017/07/19/install-microsoft-windows-fonts-on-ubuntu-the-ultimate-guide/
sudo apt install ttf-mscorefonts-installer # Windows Core fonts (2007) like Arial, Times New Roman, etc
wget https://gist.github.com/maxwelleite/10774746/raw/ttf-vista-fonts-installer.sh -q -O - | sudo bash # Installs Microsoft’s ClearType fonts (Windows Vista Fonts) like Calibri, Consolas, etc
wget https://gist.githubusercontent.com/maxwelleite/913b6775e4e408daa904566eb375b090/raw/cbfd8eb70184fa509fcab37dad7905676c93d587/ttf-ms-tahoma-installer.sh -q -O - | sudo bash # Install Tahoma fonts
# install the full pack of Segoe UI fonts
sudo mkdir -p /usr/share/fonts/truetype/msttcorefonts/
cd /usr/share/fonts/truetype/msttcorefonts/
sudo wget -q https://github.com/martinring/clide/blob/master/doc/fonts/segoeui.ttf?raw=true -O segoeui.ttf # regular
sudo wget -q https://github.com/martinring/clide/blob/master/doc/fonts/segoeuib.ttf?raw=true -O segoeuib.ttf # bold
sudo wget -q https://github.com/martinring/clide/blob/master/doc/fonts/segoeuib.ttf?raw=true -O segoeuii.ttf # italic
sudo wget -q https://github.com/martinring/clide/blob/master/doc/fonts/segoeuiz.ttf?raw=true -O segoeuiz.ttf # bold italic
sudo wget -q https://github.com/martinring/clide/blob/master/doc/fonts/segoeuil.ttf?raw=true -O segoeuil.ttf # light
sudo wget -q https://github.com/martinring/clide/blob/master/doc/fonts/seguili.ttf?raw=true -O seguili.ttf # light italic
sudo wget -q https://github.com/martinring/clide/blob/master/doc/fonts/segoeuisl.ttf?raw=true -O segoeuisl.ttf # semilight
sudo wget -q https://github.com/martinring/clide/blob/master/doc/fonts/seguisli.ttf?raw=true -O seguisli.ttf # semilight italic
sudo wget -q https://github.com/martinring/clide/blob/master/doc/fonts/seguisb.ttf?raw=true -O seguisb.ttf # semibold
sudo wget -q https://github.com/martinring/clide/blob/master/doc/fonts/seguisbi.ttf?raw=true -O seguisbi.ttf # semibold italic
fc-cache -f /usr/share/fonts/truetype/msttcorefonts/
# WPS Office Fonts (Symbol fonts) - Will install them here: /usr/share/fonts/wps-fonts
cd /tmp
wget -O ttf-wps-fonts-master.zip https://github.com/IamDH4/ttf-wps-fonts/archive/master.zip
unzip -LL ttf-wps-fonts-master.zip
cd ttf-wps-fonts-master
sudo ./install.sh

# Also install these:
# https://github.com/ryanoasis/nerd-fonts
# https://github.com/powerline/fonts

cd ~/Downloads
git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git



# [nbhirud@nbFedora]~/Downloads/nerd-fonts% ls
# AnonymousPro     CascadiaCode  CodeNewRoman     DejaVuSansMono  FiraCode  Gohu  HeavyData  IBMPlexMono  InconsolataGo   JetBrainsMono   Meslo   Mononoki              Noto          ProFont      RobotoMono     SpaceMono  Tinos   UbuntuMono
# BigBlueTerminal  CascadiaMono  ComicShannsMono  EnvyCodeR       FiraMono  Hack  Hermit     Inconsolata  InconsolataLGC  LiberationMono  Monoid  NerdFontsSymbolsOnly  OpenDyslexic  ProggyClean  SourceCodePro  Terminus   Ubuntu  UbuntuSans
# [nbhirud@nbFedora]~/Downloads/nerd-fonts% 

# To delete unnecessary files, run the following:
# find . -name "*.md" -type f -delete
# find . -name "*.txt" -type f -delete
# find . -name "LICENSE" -type f -delete
# find . -name ".uuid" -type f -delete

# But first verify without the -delete option like following:
find . -name "*.bak" -type f

# Copy above folders from patched-fonts dir into a new directory called "nerd_fonts" -> Delete all files that are
# not either *.ttf or *.otf -> move the nerd_fonts directory to ~/.local/share/fonts:
mkdir -p ~/.local/share/fonts # this fonts folder is absent by default
cp ~/Downloads/nerd-fonts ~/.local/share/fonts/ -r
rm ~/Downloads/nerd-fonts

fc-cache -fr # clear font cache
# sudo fc-cache -f -v # Find out difference
fc-list | grep "JetBrains" # To check if jetbrains fond was installed successfully

# ~/config/fontconfig/fonts.conf # Did not find this. Use GNOME Tweaks app instead
# set multiple <family> tags with different font families under <prefer> section
# This is a way to set preferred font and fall-back fonts





# # Use Gnome-Tweaks -> Appearance -> Choose individual themes to set these themes.
# Fonts:
# Interface Text = Ubuntu Nerd Font Regular
# Document Text = JetBrainsMono Nerd Font Regular
# Monospace Text = JetBrainsMono Nerd Font Mono Regular
# reboot







######################################
## 
######################################



######################################
## 
######################################



