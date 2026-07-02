#!/bin/sh

set -eux
# set -euo pipefail

echo "Run this after running nerd fonts script and alacritty script"

# https://github.com/jesseduffield/lazygit
sudo dnf copr enable -y dejan/lazygit

sudo dnf install -y neovim git lazygit tree-sitter-cli gcc curl fzf ripgrep fd-find make python3-pip python3
# gcc-c++ unzip nodejs

# Make a backup of your current Neovim files. Check if they exist first, if not, print a message
mkdir -p ~/.config ~/.local/share ~/.local/state ~/.cache
[[ -d ~/.config/nvim ]] && mv ~/.config/nvim ~/.config/nvim.bak."$(date +%Y%m%d%H%M%S)" || echo "Directory ~/.config/nvim DOES NOT exist."
[[ -d ~/.local/share/nvim ]] && mv ~/.local/share/nvim ~/.local/share/nvim.bak."$(date +%Y%m%d%H%M%S)" || echo "Directory ~/.local/share/nvim DOES NOT exist."
[[ -d ~/.local/state/nvim ]] && mv ~/.local/state/nvim ~/.local/state/nvim.bak."$(date +%Y%m%d%H%M%S)" || echo "Directory ~/.local/state/nvim/ DOES NOT exist."
[[ -d ~/.cache/nvim ]] && mv ~/.cache/nvim ~/.cache/nvim.bak."$(date +%Y%m%d%H%M%S)" || echo "Directory ~/.cache//nvim DOES NOT exist."

# Install the LazyVim Starter - Clone the starter
git clone https://github.com/LazyVim/starter ~/.config/nvim

# Remove the .git folder, so you can add it to your own repo later
rm -rf ~/.config/nvim/.git

DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"

# Create application shortcut that lists in all applications
cat <<'EOF' >"$DESKTOP_DIR/nvim.desktop"
[Desktop Entry]
Name=Neovim (LazyVim)
GenericName=Text Editor
Comment=Vim-based text editor with LazyVim IDE configuration
Exec=alacritty -e nvim %F
Terminal=false
Type=Application
Icon=nvim
Categories=Development;TextEditor;Utility;
MimeType=text/plain;text/markdown;text/x-python;text/x-lua;text/x-sh;
Keywords=text;editor;vim;lazyvim;
StartupNotify=true
EOF

# Associate standard text MIME types with the desktop profile
# xdg-mime default nvim.desktop text/plain  # This sets neovim as the default text editor. Do this after getting used to it.
update-desktop-database "$DESKTOP_DIR"

echo "=== Setup Sequence Complete ==="
echo "1. Fire up 'nvim' inside your terminal to watch LazyVim execute its dependency compilation."
echo "2. Run ':LazyHealth' once dependencies settle down to ensure everything satisfies health checks."
echo "3. Remember to update your alacritty profile fonts to leverage the installed Nerd Font!"

