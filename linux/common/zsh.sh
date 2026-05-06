#!/bin/sh

set -eux

DISTRO=""
SETUP_TYPE=""
DESKTOP=""
TIMESTAMP_FILENAME=""

if [[ -z $1 ]] && [[ -z $2 ]] && [[ -z $3 ]];
then 
  echo "DISTRO and/or SETUP_TYPE and/or DESKTOP not passed as input. Need to pass both"
  exit 1
  
else
  DISTRO=$1
  SETUP_TYPE=$2
  DESKTOP=$3
  echo "Inputs provided: DISTRO = $DISTRO, SETUP_TYPE = $SETUP_TYPE, DESKTOP = $DESKTOP"

fi

if [[ -z $4 ]];
then 
  echo "TIMESTAMP_FILENAME not passed. It will be calculated based on current time."
  TIMESTAMP_FILENAME="$(date +%Y-%m-%d_%H-%M-%S)"

else
  TIMESTAMP_FILENAME=$4

fi


# if [[ -z $1 ]];
# then 
#   echo "Distro not provided. Identifying"
#   DISTRO=$(sh $SYSUPDATE_CODE_BASE_DIR/linux/common/get_distro_name.sh)
  
#   if [ "$DISTRO" != "" ];
#   then 
#     echo "Distro identified = $DISTRO"

#   else
#     echo "Distro could not be identified."

#   fi

#   sleep 5s

# else
#   DISTRO=$1
#   echo "Distro privided as input = $DISTRO"
# fi

# Check if OMZ is already setup
OMZ_DIR=~/.oh-my-zsh
if [ -d $OMZ_DIR ]; 
then
  # Can backup before removing this directory. But that is of no good use. Remove directly
  echo "$OMZ_DIR exists. This will be deleted before fresh setup."
  rm -rf "$OMZ_DIR"
fi

HOME_DIR=$(getent passwd $USER | cut -d: -f6)
ZSHRC_FILENAME=".zshrc"
ZSHRC_BKP_FILENAME="$ZSHRC_FILENAME"_nbbkp_"$TIMESTAMP_FILENAME"

if [ -e "$HOME_DIR/$ZSHRC_FILENAME" ]
then
    echo "$HOME_DIR/$ZSHRC_FILENAME already exists. Creating a backup and deleting. Backup: $ZSHRC_BKP_FILENAME"
    mv "$HOME_DIR/$ZSHRC_FILENAME" "$HOME_DIR/$ZSHRC_BKP_FILENAME"
else
    echo "$HOME_DIR/$ZSHRC_FILENAME does not already exist."
fi


echo "************************ Install zsh ************************"
# sudo dnf install -y zsh

echo "************************ Make zsh the default shell ************************"
# chsh -s $(which zsh) 
# chsh -s $(which zsh) nbhirud
# chsh -s $(which zsh) $USER

echo "************************ Install omz (Oh My zsh) unattended ************************"
# sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || {
  echo "Could not install Oh My Zsh" >/dev/stderr
  exit 1
}

echo "************************ Install omz plugins ************************"
# cd $ZSH_CUSTOM/plugins  # $ZSH_CUSTOM returns nothing here # also, this cd is actually unnecessary
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/Aloxaf/fzf-tab ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab

# https://docs.docker.com/engine/install/fedora/
# https://docs.docker.com/engine/cli/completion/#zsh
# mkdir -p ~/.oh-my-zsh/completions
# docker completion zsh > ~/.oh-my-zsh/completions/_docker

# echo "************************ Configure omz ************************"
# nano ~/.zshrc


# # ZSH_THEME="robbyrussell" # comment this line
# ZSH_THEME="agnoster"
# zstyle ':omz:update' mode auto # Uncomment this
# zstyle ':omz:update' frequency 7 # Uncomment and change value
# ENABLE_CORRECTION="true" # Uncomment - Give it a try
# COMPLETION_WAITING_DOTS="true"
# plugins=(git branch gh github gitignore pre-commit dnf yum sudo safe-paste python pip poetry repo zsh-autosuggestions zsh-syntax-highlighting colorize history history-substring-search aws docker docker-compose helm kops kubectl podman mongocli postgres rsync rust timer rsync vscode zsh-interactive-cd zsh-navigation-tools screen fzf-tab)



# Change theme from robbyrussell to agnoster
sed -i 's|^ZSH_THEME=.*|ZSH_THEME=\"agnoster\"|' ~/.zshrc


# sed -i '/<search string>/s/^/#/g' <file>    (syntax to comment out)
# sed -i '/<search string>/s/^#//g' <file>    (syntax to uncomment)
# sed -i "/# zstyle ':omz:update' mode auto/s/^#//g" ~/.zshrc # Just uncommenting an existing line

# Append a line below the searched commented line:
# https://www.gnu.org/software/sed/manual/html_node/Other-Commands.html
sed -i "/# zstyle ':omz:update' mode auto/a zstyle ':omz:update' mode auto" ~/.zshrc

sed -i "/# zstyle ':omz:update' frequency.*/a zstyle ':omz:update' frequency 7" ~/.zshrc

sed -i "/# ENABLE_CORRECTION.*/a ENABLE_CORRECTION=\"true\"" ~/.zshrc

sed -i "/# COMPLETION_WAITING_DOTS.*/a COMPLETION_WAITING_DOTS=\"true\"" ~/.zshrc

# Plugins
# https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins

# plugins=(git branch gh github gitignore pre-commit dnf yum sudo safe-paste python pip poetry repo zsh-autosuggestions zsh-syntax-highlighting colorize history history-substring-search aws docker docker-compose helm kops kubectl podman mongocli postgres rsync rust timer rsync vscode zsh-interactive-cd zsh-navigation-tools screen fzf-tab)


#https://www.baeldung.com/linux/file-insert-multiple-lines
# If I write "....*/a \n" instead of "....*/a #\n" it is printing the character n in the file. Learn about this
sed -i "/# ZSH_CUSTOM.*/a #\n\n# Added by nbhirud - For vscode plugin\
\n# Add the following line to ~/.zshrc between the ZSH_THEME and plugins=() lines\
\n# Choose one of \`code\`, \`code-insiders\`, \`codium\`, or \`cursor\`.\
\nVSCODE=codium" ~/.zshrc

OMZ_PLUGINS_ONE=""
OMZ_PLUGINS_TWO_DISTRO=""
OMZ_PLUGINS_THREE_DESKTOP=""
OMZ_PLUGINS_FOUR=""
OMZ_PLUGINS_FIVE_FULL=""

OMZ_PLUGINS_ONE="git python uv pip autopep8 pep8 sudo colorize colored-man-pages command-not-found"
# conda conda-env pipenv poetry poetry-env pyenv pylint tig
# virtualenv virtualenvwrapper

if [ "$DISTRO" = "fedora" ];
then 
  OMZ_PLUGINS_TWO_DISTRO="dnf firewalld"
  # yum

elif  [ "$DISTRO" = "ubuntu" ];
then
  OMZ_PLUGINS_TWO_DISTRO="ubuntu ufw snap"

elif  [ "$DISTRO" = "arch" ];
then
  OMZ_PLUGINS_TWO_DISTRO="archlinux ufw"

elif  [ "$DISTRO" = "debian" ];
then
  OMZ_PLUGINS_TWO_DISTRO="debian ufw"

fi

OMZ_PLUGINS_FOUR="branch gh gitignore zsh-autosuggestions zsh-syntax-highlighting vscode zsh-interactive-cd  fzf-tab "
# fzf - do not use this plugin
# github history history-substring-search - not useful for me
# pre-commit repo
# rsync - start using this tool
# safe-paste - very good plugin, but need to get used to using terminal without it
# zsh-navigation-tools

if [ "$SETUP_TYPE" = "full" ];
then 
  OMZ_PLUGINS_FIVE_FULL="aws docker docker-compose timer ssh screen emoji"
  # cask emacs - enable these when you start using emacs
  # tailscale
  # flutter jira jsontools
  # helm kops kubectl k9s podman kompose kubectx kube-ps1 microk8s minikube svcat toolbox
  # postgres rust mongocli mongo-atlas nomad rclone terraform vault
  # kitty - if using kitty terminal
  # redis-cli 
  # shell-proxy ssh-agent
  # systemd - not useful for me
  # thefuck - lol

  # https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/bgnotify - it is configurable
  # zbell - also plays the bell like bgnotify
  if [ "$DESKTOP" = "kde" ];
  then 
    # bgnotify uses kdialog on kde
    OMZ_PLUGINS_THREE_DESKTOP="bgnotify" 

  elif  [ "$DESKTOP" = "gnome" ];
  then
    # bgnotify may use notify-send on gnome. check
    OMZ_PLUGINS_THREE_DESKTOP="bgnotify"

  fi

fi

OMZ_PLUGINS="$OMZ_PLUGINS_ONE $OMZ_PLUGINS_TWO_DISTRO $OMZ_PLUGINS_THREE_DESKTOP $OMZ_PLUGINS_FOUR $OMZ_PLUGINS_FIVE_FULL"

sed -i "s|^plugins=(git)|plugins=($OMZ_PLUGINS)|" ~/.zshrc


sudo tee -a ~/.zshrc <<'OMZ_LAST_EOF'


#################################################################
# OMZ setup added by nbhirud:
#################################################################

#ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#ff00ff,bg=cyan,bold,underline"
ZSH_AUTOSUGGEST_STRATEGY=(history completion match_prev_cmd)
ZSH_HIGHLIGHT_HIGHLIGHTERS+=(main brackets pattern cursor)

#################################################################

OMZ_LAST_EOF


# echo "************************ Update omz ************************"
# omz update
# source .zshrc 

echo $SHELL
echo "************************ NOTE: Reboot/Re-login to see changes ************************"
sleep 5s

