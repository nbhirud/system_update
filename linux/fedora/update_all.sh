#!/bin/bash

# https://www.baeldung.com/linux/set-command
set -eux

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"

NBDIR="$HOME_DIR/nb"
SYSUPDATE_CODE_BASE_DIR="$NBDIR/CodeProjects/system_update"
# APPIMAGES_DIR="$HOME_DIR/AppImages"
SCRIPT_DATA="${NBDIR}/nb_script_data"
FILENAME_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"

SCRIPT_DOWNLOADS_DIR="${SCRIPT_DATA}/downloads"

UPDATE_ALL_DOWNLOADS_DIR_BASE="${SCRIPT_DOWNLOADS_DIR}/update_all"
UPDATE_ALL_CURRENT_DOWNLOADS_DIR="${UPDATE_ALL_DOWNLOADS_DIR_BASE}/update_all_${FILENAME_TIMESTAMP}"

mkdir -p "${UPDATE_ALL_CURRENT_DOWNLOADS_DIR}"
chown "${REAL_USER}":"${REAL_USER}" "${UPDATE_ALL_DOWNLOADS_DIR_BASE}" "${UPDATE_ALL_CURRENT_DOWNLOADS_DIR}"

cd "$UPDATE_ALL_CURRENT_DOWNLOADS_DIR" || exit

DESKTOP="kde"
SETUP_TYPE="full" # full or light (or minimal - TBD - bare minimum, remove all optional stuff)

# torsocks off

# echo "************************ Update AppImages ************************"

# alias gearlever='flatpak run it.mijorus.gearlever'
# flatpak run it.mijorus.gearlever --update <name of appimage> # updates 1 appimage at a time

# flatpak run it.mijorus.gearlever --update -y --force "$APPIMAGES_DIR/obsidian.appimage"
# flatpak run it.mijorus.gearlever --update -y --force "$APPIMAGES_DIR/caprine.appimage"
# flatpak run it.mijorus.gearlever --update -y --force "$APPIMAGES_DIR/helium.appimage"
# flatpak run it.mijorus.gearlever --update -y "$APPIMAGES_DIR/helium.appimage"

# echo "************************ Update joplin ************************"
# alias nbjoplinupdate="wget -O - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash"

# echo "************************ Update clamav signatures ************************"
# sudo freshclam


echo "************************ Update hosts ************************"
sh $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/hosts.sh


echo "************************ Update bleachbit ************************"
sh $SYSUPDATE_CODE_BASE_DIR/linux/common/bleachbit.sh


# echo "************************ Update fonts ************************"
# sh $SYSUPDATE_CODE_BASE_DIR/linux/common/fonts.sh
# Skipping this till I implement the faster downloads code in fonts script. It takes forever right now.


echo "************************ Update/Pull git repos ************************"

gup() {
    local repo="$1"
    
    if [[ -z "$repo" ]]; then
        echo "📁 Either the path is incorrect or usage is incorrect. Usage: gup /path/to/repo"
        return 1
    fi
    
    if [[ ! -d "$repo/.git" ]]; then
        echo "⚠️  Skip: $repo (Not a git repo)"
        return 0
    fi
    
    cd "$repo" || { echo "❌ Cannot access: $repo"; return 1; }
    
    # Safety: skip if uncommitted changes exist
    if ! git diff-index --quiet HEAD --; then
        echo "🛑 Skipped: $(pwd) [dirty tree]"
        cd - > /dev/null
        return 0
    fi
    
    echo "🔄 Updating: $(pwd)"
    git pull --rebase --autostash && echo "✅ Done" || echo "❌ Failed"
    
    cd - > /dev/null
}

REPOS=(
    ~/.oh-my-zsh
    # -~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    # ~/.oh-my-zsh/plugins/zsh-syntax-highlighting
    # ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    ~/.oh-my-zsh/custom/plugins/fzf-tab
    
)

# --- LOGIC ---
for repo in "${REPOS[@]}"; do
    # echo $repo
    gup "$repo"
done

echo "************************ Update proton_ag_stuff ************************"
sh $SYSUPDATE_CODE_BASE_DIR/linux/security_os_level/proton_ag.sh --setup-type $SETUP_TYPE --desktop $DESKTOP
# bash linux/security_os_level/proton_ag.sh --setup-type full --desktop kde

# echo "************************ Update dnf packages ************************"
# sudo dnf update -y
# sudo dnf upgrade --refresh -y
# echo "************************ Update flatpak apps ************************"
# flatpak update -y

# echo "************************ Update aws ************************"
# aws update

# echo "************************ Update uv ************************"
# uv self update


# echo "************************ Update omz ************************"

# # omz update -y
# sh $ZSH/tools/upgrade.sh

# echo "************************ fastfetch ************************"
# fastfetch

# alias nbupdate=". torsocks off && sudo dnf update -y && sudo dnf upgrade --refresh -y && flatpak update -y && aws update && uv self update && omz update -y && . torsocks on && fastfetch"

# torsocks on

echo "Done!"
