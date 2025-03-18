####################################################
# from ubuntu
####################################################

echo $SHELL # To check current shell
# Did basic research of bash vs zsh vs fish and felt like zsh was the right one for me. Also, fish isn't POSIX
# compliant. bash and zsh are mostly compatible with each other, but fish isn't.
# sudo apt install zsh

# https://itsfoss.com/zsh-ubuntu/
sudo apt install -y zsh fonts-font-awesome
chsh -s $(which zsh) # sets zsh as default
zsh
# Looks like restarting terminal doesn't apply this change of default shell. But seems to work after a reboot.



################33


##### Make terminal beautiful and productive

# Step 1 - If not already done, set nerd fonts as default in "GNOME Tweaks", "GNOME Terminal -> unnamed",

##### oh my zsh - https://ohmyz.sh/
# https://github.com/ohmyzsh/ohmyzsh/wiki/Installing-ZSH
sudo apt install wget curl xclip autojump
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"


# Interesting Built-in plugins:
# debian, systemd, aliases, colored-man-pages, colorize,
# command-not-found, cp, rsync, safe-paste, screen, rbw,
# autojump, github, git, gitignore, postgres, redis-cli,
# golang, docker, repo, pip, python, pyenv, virtualenv,
# autopep8, pylint,  themes, sudo, history, JsonTools
# you-should-use, Auto-Notify,
# zsh-autosuggestions, zsh-syntax-highlighting

# https://github.com/zsh-users/zsh-autosuggestions
# https://github.com/zsh-users/zsh-autosuggestions?tab=readme-ov-file#configuration

# https://github.com/zsh-users/zsh-syntax-highlighting

# TLDR:
cd $ZSH_CUSTOM/plugins
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# oh-my-zsh config:
#cd
#nano .zshrc
## do the following changes:
## ZSH_THEME="robbyrussell" # comment this line
#ZSH_THEME="agnoster"
#zstyle ':omz:update' mode auto # Uncomment this
#zstyle ':omz:update' frequency 7 # Uncomment and change value
#ENABLE_CORRECTION="true" # Uncomment - Give it a try
#COMPLETION_WAITING_DOTS="true"
#plugins=(git sudo safe-paste github python repo zsh-autosuggestions zsh-syntax-highlighting)
## At the bottom of oh-my-zsh stuff:
#ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#ff00ff,bg=cyan,bold,underline"
#ZSH_AUTOSUGGEST_STRATEGY=(history completion match_prev_cmd)
#ZSH_HIGHLIGHT_HIGHLIGHTERS+=(main brackets pattern cursor)

omz update
# Reloads the updated terminal theme
source ~/.zshrc


############3

# Poetry completion:
mkdir $ZSH_CUSTOM/plugins/poetry
poetry completions zsh > $ZSH_CUSTOM/plugins/poetry/_poetry
# Add to plugins omz array:
         # plugins(
         #  ...
         #	poetry
         #	...
         #	)


####################################################
# from fedora
####################################################

sudo dnf install -y zsh 
chsh -s $(which zsh) 
zsh


################3


# omz
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

cd $ZSH_CUSTOM/plugins
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

#cd
#nano .zshrc
## do the following changes:
## ZSH_THEME="robbyrussell" # comment this line
#ZSH_THEME="agnoster"
#zstyle ':omz:update' mode auto # Uncomment this
#zstyle ':omz:update' frequency 7 # Uncomment and change value
#ENABLE_CORRECTION="true" # Uncomment - Give it a try
#COMPLETION_WAITING_DOTS="true"
#plugins=(git sudo safe-paste github python repo zsh-autosuggestions zsh-syntax-highlighting)
## At the bottom of oh-my-zsh stuff:
#ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#ff00ff,bg=cyan,bold,underline"
#ZSH_AUTOSUGGEST_STRATEGY=(history completion match_prev_cmd)
#ZSH_HIGHLIGHT_HIGHLIGHTERS+=(main brackets pattern cursor)


###############

# set up nerd fonts before setting up omz


##############


# zsh
sudo dnf install -y zsh autojump
chsh -s $(which zsh) # set zsh as default

# Rest of the OMZ setup is same as on Ubuntu
omz update
source .zshrc 

##############

echo $SHELL
sudo dnf install -y zsh autojump
chsh -s $(which zsh)
zsh

#############


### OMZ
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

cd $ZSH_CUSTOM/plugins
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

cd
nano .zshrc
# do changes in .zshrc
omz update
source ~/.zshrc


############

mkdir $ZSH_CUSTOM/plugins/poetry
poetry completions zsh > $ZSH_CUSTOM/plugins/poetry/_poetry
# add poetry in OMZ plugins array


###########


### Interesting/Useful Oh My ZSH plugins
# python related: autopep8 conda conda-env dotenv pep8 pip pipenv poetry poetry-env pyenv pylint python virtualenvwrapper
# fedora related: dnf yum
# linux (general) related: colored-man-pages colorize history history-substring-search perms safe-paste screen sudo systemadmin systemd 
# security: firewalld gpg-agent keychain ufw
# git related: branch gh git git-auto-fetch git-commit git-escape-magic gitfast github gitignore git-prompt  pre-commit
# cloud and containers: aws docker docker-compose helm kops kubectl kubectx podman terraform toolbox
# database related: mongocli postgres
# misc: isodate jsontools rsync rust thefuck timer torrent transfer universalarchive urltools vscode web-search wp-cli zsh-interactive-cd zsh-navigation-tools

# use this:
# plugins=(git sudo dnf yum safe-paste screen autojump github postgres docker pip python poetry repo themes zsh-aut)



####################################################
# from Arch
####################################################


# https://wiki.archlinux.org/title/Zsh
# https://github.com/ohmyzsh/ohmyzsh

sudp pacman -S zsh

# plugins=(archlinux)


####################################################
# from alpine
####################################################


sudo apk add  zsh

adduser -g "Nikhil Bhirud" nbhirud -s /bin/zsh -S


