#!/usr/bin/env bash

set -eux

# Script to setup git on a new machine or new installation of OS
echo "************************ Install and Configure git ************************"

GIT_USER_EMAIL=""
GIT_USER_NAME=""

if [[ -z $1 ]];
then 
    echo "Need to run later: git config --global user.email <xyz@users.noreply.github.com>"
    sleep 5s
else
    GIT_USER_EMAIL=$1
    echo "Will set user.email to $GIT_USER_EMAIL"
fi

if [[ -z $2 ]];
then 
    echo "Need to run later: git config --global user.name \"Firstname Lastname\""
    sleep 5s
else
    GIT_USER_NAME=$2
    echo "Will set user.email to $GIT_USER_NAME"
fi

# Note: git may not come already installed on some flavors like xfce, etc.
sudo dnf install -y git

# https://git-scm.com/book/en/v2/Customizing-Git-Git-Configuration
# TODO replace with correct Name
git config --global user.name "$GIT_USER_NAME"

# TODO replace with correct email
git config --global user.email "$GIT_USER_EMAIL"

# https://code.visualstudio.com/docs/sourcecontrol/overview#_vs-code-as-git-difftool-and-mergetool
# git config --global core.editor codium
git config --global core.editor "codium --wait" # # https://git-scm.com/book/en/v2/Appendix-C:-Git-Commands-Setup-and-Config

# # Other options for "git config --global core.editor"
# git config --global core.editor "nvim" # Neovim
# git config --global core.editor "nano" # Nano (nano) or Micro
# git config --global core.editor "kwrite" # kwrite
# git config --global core.editor "code --wait" # VS Code


git config --global merge.tool codium # codium might not be supported. vscode is supported
git config --global mergetool.codium.cmd 'codium --wait --merge "$REMOTE" "$LOCAL" "$BASE" "$MERGED"' # Not sure if this will work

# # Other options for "git config --global merge.tool"
# # KDiff3
# sudo dnf install kdiff3
# git config --global merge.tool "kdiff3"
# # Meld
# sudo dnf install meld
# git config --global merge.tool "meld"
# # VS Codium
# git config --global merge.tool "vscodium"
# git config --global mergetool.vscodium.cmd 'codium --wait --merge "$REMOTE" "$LOCAL" "$BASE" "$MERGED"'
# # VS Code
# git config --global merge.tool "vscode"
# git config --global mergetool.vscode.cmd 'code --wait --merge "$REMOTE" "$LOCAL" "$BASE" "$MERGED"'
# Neovim (nvimdiff)
# git config --global merge.tool "nvimdiff"
# # Beyond Compare (Proprietary)
# git config --global merge.tool "bc"

# check supported merge tools:
# git mergetool --tool-help

# Essential Companion Git Settings: Regardless of which two tools you pick, set these two global defaults alongside them:
# Prevent Git from leaving clutter (.orig files) in your repo after a merge
git config --global mergetool.keepBackup false
# Show the original common ancestor (BASE) + trimmed context in conflict blocks
git config --global merge.conflictstyle "zdiff3"


git config --global core.autocrlf input # # Configure Git to ensure line endings in files you checkout are correct for Linux

git config --global init.defaultBranch main


git config --global  help.autocorrect 1


git config --global color.ui true # default is true

# The above sets all the below. Allowed values = true, false, or always:
# color.branch
# color.diff
# color.interactive
# color.status

############################
# git config --global commit.template ~/.gitmessage.txt
# # TODO create the temopate file ~/.gitmessage.txt as follows (uncomment):
# # Subject line (try to keep under 50 characters)

# # Multi-line description of commit,
# # feel free to be detailed.

# # [Ticket: X]
############################

# git config --global core.excludesfile ~/.gitignore_global
# # create file ~/.gitignore_global with following content syntax (uncomment):
# # *~
# # .*.swp
# # .DS_Store

############################

# git hooks
# https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks
############################

# # garbage collect
# # https://git-scm.com/book/en/v2/Git-Internals-Maintenance-and-Data-Recovery
# git gc 
# # git gc --auto

############################
# # git config --list

# # https://docs.github.com/en/get-started/git-basics/set-up-git
# gh auth login

# # also see:
# # https://www.jetbrains.com/help/idea/using-git-integration.html
# # https://git-scm.com/book/en/v2/Appendix-A:-Git-in-Other-Environments-Git-in-IntelliJ-/-PyCharm-/-WebStorm-/-PhpStorm-/-RubyMine
# # https://git-scm.com/book/en/v2/Appendix-A:-Git-in-Other-Environments-Git-in-Zsh # if not using omz

# # 
