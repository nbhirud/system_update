
sudo dnf install -y zsh
# chsh -s $(which zsh) 
chsh -s $(which zsh) nbhirud

# sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || {
  echo "Could not install Oh My Zsh" >/dev/stderr
  exit 1
} # EXPERIMENTAL

cd $ZSH_CUSTOM/plugins
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# nano ~/.zshrc

# # tee -a = append
# tee -a ~/.zshrc <<EOL
# # ZSH_THEME="robbyrussell" # comment this line
# ZSH_THEME="agnoster"
# zstyle ':omz:update' mode auto # Uncomment this
# zstyle ':omz:update' frequency 7 # Uncomment and change value
# ENABLE_CORRECTION="true" # Uncomment - Give it a try
# COMPLETION_WAITING_DOTS="true"
# plugins=(git branch gh github gitignore pre-commit dnf yum sudo safe-paste python pip poetry repo zsh-autosuggestions zsh-syntax-highlighting colorize history history-substring-search aws docker docker-compose helm kops kubectl podman mongocli postgres rsync rust timer rsync vscode zsh-interactive-cd zsh-navigation-tools screen fzf-tab)
# # At the bottom of oh-my-zsh stuff:
# #ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#ff00ff,bg=cyan,bold,underline"
# ZSH_AUTOSUGGEST_STRATEGY=(history completion match_prev_cmd)
# ZSH_HIGHLIGHT_HIGHLIGHTERS+=(main brackets pattern cursor)
# EOL

# omz update
# source .zshrc 

echo $SHELL

