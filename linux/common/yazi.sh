#!/bin/bash

set -eux


# TODO - move all this here: linux/common/yazi.sh

# https://yazi-rs.github.io/docs/installation
# https://yazi-rs.github.io/docs/configuration/overview/
sudo dnf copr enable -y lihaohong/yazi
sudo dnf install -y yazi ffmpegthumbnailer ImageMagick poppler fd-find ripgrep fzf zoxide

# alternative using crgo
# cargo install --locked yazi-fm yazi-cli

# config: ~/.config/yazi/config.toml
#   yazi.toml - General configuration.
#   keymap.toml - Keybindings configuration.
#   theme.toml - Color scheme configuration.
sudo tee -a ~/.config/yazi/config.toml <<'YAZI_EOF'
[manager]
ratio = [1, 3, 4]         # Panel ratio: sidebar | file_list | preview
show_hidden = true        # Show hidden files by default (you'll like this)
sort_by = "alphabetical"  # Or "natural", "mtime", "size"
sort_reverse = false

[opener]
edit = [
	{ run = '${EDITOR:-nvim} "$@"', desc = "Edit with $EDITOR" },
	{ run = 'yq "$@"', for = "unix", orphan = true, block = false }
]
open = [
	{ run = 'xdg-open "$@"', desc = "Open", for = "linux" },
	{ run = 'open "$@"', desc = "Open", for = "mac" },
	{ run = 'start "" "$@"', desc = "Open", for = "windows" }
]
reveal = [
	{ run = 'xdg-open "$(dirname "$1")"', desc = "Reveal", for = "linux" }
]

[preview]
max_width = 200
max_height = 100
cache_dir = "/tmp/yazi-cache"  # Make sure this exists
sixel = true                   # Enable sixel fallback for non-Kitty terminals

[plugin]
# Enable plugins
fetchers = [
	{ name = "*", cmd = "file", args = ["--mime-type", "-b"] }
]
YAZI_EOF

  # install yazi plugins:
  # Official plugin manager
  ya pkg add yazi-rs/plugins:git          # Git status display
  # ya pkg add yazi-rs/plugins:full-border  # Pretty borders
  # ya pkg add yazi-rs/plugins:history      # Directory history (like ranger's)
  # Community plugins
  # ya pkg add S1mba/yazi-git-status        # Enhanced Git integration
  ya pkg add yazi-rs/plugins:diff         # File diff preview
  # List installed: ya pkg list
  # Also added changes to 1. .zshrc, and 2. neovim setup




########################################################
# Add to .zshrc
########################################################


sudo tee -a ~/.zshrc <<'YAZI_ZSHRC_EOF'

############################
# yazi file manager
############################

# Yazi shell function to cd into the directory where Yazi exits
function y() {
	temp="$(yazi "$@" --cwd-file)"
	if [ -n "$temp" ]; then
		cd "$temp" && pwd
	fi
}

# Optional: bind yazi to Ctrl+O (opens Yazi from anywhere in shell)
bindkey -s '^O' 'y\n'

# For fzf integration (you already use fzf)
# yazi can act as the picker instead of fzf
alias ff="yazi"

############################

YAZI_ZSHRC_EOF



########################################################
# NeoVim Integration
########################################################

# TODO - First check if neovim is installed

# # To integrate yazi file manager dd to your LazyVim lua/plugins/yazi.lua:


sudo tee -a /home/nbhirud/.config/nvim/lua/plugins/yazi.lua <<'YAZI_NVIM_EOF'

return {
  {
    "mikavilpas/yazi.nvim",
    event = "VeryLazy",
    keys = {
      {
        "<leader>-",
        "<cmd>Yazi<cr>",
        desc = "Open Yazi at current file/directory",
      },
      {
        "<c-up>",
        "<cmd>Yazi toggle<cr>",
        desc = "Resume Yazi",
      },
    },
    opts = {
      -- Keymaps in Yazi
      keymaps = {
        show_help = "<f1>",
        open_file = "<enter>",
        open_files = { "<enter>" },
        open_cwd = "<c-d>",  -- Opens parent dir in yazi, then you can cd
        tab_new = "<a-t>",
        tab_rename = "<a-r>",
        -- Custom keymaps
        open_with_nvim = { "<space>e" },
      },
      open_for_directories = false,  -- Set true if you want Yazi to open folders too
      integrations = {
        -- Jump to file when opened from Neovim
        jump_to_markdown = true,
        -- Sync cwd between Neovim and Yazi
        sync_cwd = true,
      },
    },
  },
  -- Optional: Enhance preview inside Neovim
  {
    "echasnovski/mini.icons",
    lazy = true,
  },
  -- File type icons for Yazi
  {
    "stevearc/dressing.nvim",
    opts = {
      input = { default_title = false },
      confirm = { default_title = false },
    },
  },
}

YAZI_NVIM_EOF

#######################
# # After installing yazi.nvim, create the integration wrapper script:
mkdir -p ~/.config/yazi
cat > ~/.config/yazi/init.lua << 'EOF'
-- ~/.config/yazi/init.lua
local M = {}

function M.yazi_setup()
  -- Custom keybinding: Press <Space-e> to open in Neovim
  vim.keymap.set("n", "<Space-e>", "<cmd>yazi<CR>", { remap = false })
end

return M
EOF
# # Then in your Neovim, run: :Yazi from any buffer. It opens at your current cursor location/file.

