#!/bin/sh

set -eux

# This script is being written with the nerd-fonts repo in mind. To be generalized later.
# HOME_DIR=$(getent passwd $USER | cut -d: -f6)
# CODE_BASE_DIR="$HOME_DIR/nb/CodeProjects"
# NERD_FONTS_DIR="$CODE_BASE_DIR/nerd-fonts"

# local_git_repository_dir="$NERD_FONTS_DIR"

# interval_in_seconds=3600 # Watch interval time in seconds 

# run_once=true


#!/usr/bin/env bash
# Minimal Git Updater for Static List
# Usage: ./update-static-repos.sh

# set -euo pipefail

# # --- CONFIGURATION ---
# REPOS=(
#     "/home/nbhirud/projects/backend-api"
#     "/home/nbhirud/projects/frontend-ui"
#     "/home/nbhirud/projects/rust-compiler"
#     # Add your specific directories here
# )

REPOS=(
    ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab
)




# --- LOGIC ---
for repo in "${REPOS[@]}"; do
    if [[ ! -d "$repo/.git" ]]; then
        echo "⚠️  SKIP: $repo (Not a git repo)"
        continue
    fi

    cd "$repo"

    # Safety: Skip if working tree has changes
    if ! git diff-index --quiet HEAD --; then
        echo "🛑 SKIPPED: $repo (Dirty working tree - local changes exist)"
        cd - > /dev/null
        continue
    fi

    echo "🔄 PULLING: $repo"
    git pull --rebase --autostash
    
    cd - > /dev/null
done

echo "✅ Update process finished."



############################3

# same thing as a stand alone function: pass directories one by one
# usage: 
# gup /dfdf/fafdsa/<path to directory>

# Add the gup function to .zshrc and
# If you need to update multiple directories frequently, add this alias to .zshrc:
# alias gupa='gup /home/nbhirud/projects/backend-api && gup /home/nbhirud/projects/frontend-ui'

gup() {
    local repo="$1"
    
    if [[ -z "$repo" ]]; then
        echo "📁 Usage: gup /path/to/repo"
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

############################################
# same thing as a stand alone script: pass directories one by one


#!/usr/bin/env bash
set -euo pipefail

repo="${1:-}"
[[ -z "$repo" ]] && { echo "Usage: gup.sh <path>"; exit 1; }

[[ ! -d "$repo/.git" ]] && { echo "Skip: Not a git repo"; exit 0; }
cd "$repo"
git diff-index --quiet HEAD -- && echo "🔄 Pulling..." && git pull --rebase --autostash || echo "🛑 Dirty tree - skipped"