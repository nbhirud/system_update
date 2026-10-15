#!/bin/sh

set -eux

# Alacritty config
# https://alacritty.org/config-alacritty.html


# --- Configuration Variables ---
ALACRITTY_CONF="$HOME/.config/alacritty/alacritty.toml"
FONT_FAMILY="Noto Sans Mono Nerd Font"
FONT_SIZE=12 # Adjusted for high-DPI on XPS/KDE
COLOR_THEME="Dracula" # Clean, high contrast for coding

# --- 1. Hardware Detection & Optimization ---
echo "🔍 Detecting Hardware..."

# Check RAM (in GB)
RAM_KB=$(free | grep Mem | awk '{print $2}')
RAM_GB=$((RAM_KB / 1024 / 1024))
echo "   RAM Detected: ${RAM_GB} GB"

# Check GPU
GPU_MODEL=$(lspci | grep -i vga | grep -i nvidia || echo "Integrated")
IS_NVIDIA=false
if [[ "$GPU_MODEL" == *"nvidia"* ]] || [[ "$GPU_MODEL" == *"GTX"* ]]; then
    IS_NVIDIA=true
    echo "   NVIDIA GPU Detected: Enabling OpenGL Hardware Acceleration"
else
    echo "   Integrated GPU or AMD detected: Using standard renderer"
fi

# Determine Buffer Size based on RAM
if [ "$RAM_GB" -gt 12 ]; then
    SCROLLBACK_LINES=10000
    echo "   High RAM: Allocating 10k scrollback lines"
elif [ "$RAM_GB" -lt 8 ]; then
    SCROLLBACK_LINES=2000
    echo "   Low RAM: Limiting scrollback to 2k to save memory"
else
    SCROLLBACK_LINES=5000
    echo "   Moderate RAM: Allocating 5k scrollback lines"
fi


echo "************************ Install alacritty ************************"
sudo dnf install -y alacritty


echo "************************ Configure alacritty ************************"
mkdir -p $HOME/.config/alacritty/
cp $HOME/nb/CodeProjects/system_update/linux/common/data/.alacritty.toml $HOME/.config/alacritty/alacritty.toml


echo "⚙️ Generating ~/.config/alacritty/alacritty.toml..."

cat > "$ALACRITTY_CONF" <<EOF
# Alacritty Configuration for Nik
# Generated: $(date)
# Hardware Optimizations: RAM=${RAM_GB}GB, NVIDIA=$IS_NVIDIA

[env]
# Ensure clean environment
TERM = "xterm-256color"


[terminal]
# shell = "/usr/bin/zsh" # Or /usr/bin/fish, but ensure env vars pass through
# Crucial for Neovim clipboard integration
shell = { program = "/usr/bin/zsh", args = ["-l"] }

[window]
# KDE Integration: Let Plasma handle borders/decorations for seamless tiling
decorations = "none"
opacity = 0.95 # Slight transparency for depth
blur = true # KDE supports blur behind windows
startup_mode = "Windowed"
padding = { x = 8, y = 8 }
dynamic_title = true # Title bar shows current file path

# Dynamic sizing based on RAM
scrolling = { history = $SCROLLBACK_LINES, multiplier = 3 }

# Hardware Acceleration Hint
option_as_alt = "OnlyLeft"

[font]
# Your preferred Nerd Font
normal = { family = "$FONT_FAMILY", style = "Regular" }
bold = { family = "$FONT_FAMILY", style = "Bold" }
italic = { family = "$FONT_FAMILY", style = "Italic" }
bold_italic = { family = "$FONT_FAMILY", style = "Bold Italic" }
size = $FONT_SIZE
# normal = { family = "Noto Sans Mono Nerd Font", style = "Regular" }
# size = 12.0

# Enable live reload for rapid iteration
live_config_reload = true

[colors.primary]
background = "#282a36" # Dracula Base
foreground = "#f8f8f2"
dim_foreground = "#797979"
bright_foreground = "#ffffff"
# background = "#1e1e2e" # Dark theme recommended for coding
# foreground = "#cdd6f4"

# Dracula Palette (Standard for Dark Mode Coding)
[colors.cursor]
text = "#282a36"
cursor = "#f8f8f2"

[colors.vi_mode_cursor]
text = "#282a36"
cursor = "#ff79c6"

[colors.search.matches]
foreground = "#44475a"
background = "#50fa7b"

[colors.selection]
text = "#282a36"
background = "#ffb86c"

[colors.normal]
black = "#21222c"
red = "#ff5555"
green = "#50fa7b"
yellow = "#f1fa8c"
blue = "#bd93f9"
magenta = "#ff79c6"
cyan = "#8be9fd"
white = "#bfbfbf"

[colors.bright]
black = "#6272a4"
red = "#ff6e6e"
green = "#69ff94"
yellow = "#ffffa5"
blue = "#d6acff"
magenta = "#ff92df"
cyan = "#a4ffff"
white = "#ffffff"

[bell]
animation = "None"
command = "None"
visual = "None"

# Mouse binding for efficiency
[mouse]
hide_when_typing = true
bindings = [
    { mouse = "Middle", action = "PasteSelection" },
]

# Keyboard bindings for workflow speed
[keyboard]
bindings = [
    { key = "Insert", mods = "Control|Shift", action = "Paste" },
    { key = "C", mods = "Control|Shift", action = "Copy" },
    { key = "V", mods = "Control|Shift", action = "Paste" },
]
EOF



# --- 5. MIME & Desktop Integration ---
echo "🖥️ Integrating with KDE Plasma..."
# Set as default terminal
xdg-mime default org.alacritty.Alacritty.desktop x-terminal-emulator


###############################################################
# tmux
###############################################################

# Step 1: Basic Integration (The "Launch" Method)
# You don't need to configure Alacritty to "talk" to tmux. You just tell your shell to start tmux automatically.
# Edit your ~/.zshrc (since you use Oh My Zsh):

# Result: Now, every time you open Alacritty, you drop straight into your persistent tmux session. Close the window? Session keeps running in the background. Reopen? You are right back where you left off.

sudo tee -a ~/.zshrc <<'ZSHRC_EOF'


#################################################################
# tmux
#################################################################

# Only attach/start tmux if we are in an interactive shell and NOT already inside tmux
if [[ -z "$TMUX" ]] && [ -t 1 ]; then
    # Start or attach a session named "main"
    # -a attaches if it exists, creates new if not
    exec tmux attach -t main || tmux new -s main
fi

ZSHRC_EOF

#####################################

# By default, copying from Neovim inside tmux won't copy to your system clipboard on Wayland. We need to bridge tmux to wl-clipboard.

#  Install Dependencies
sudo dnf install wl-clipboard



# Configure Tmux (~/.tmux.conf)
# Add these lines to enable OSC 52 (the escape sequence that tells Alacritty to push text to the system clipboard).

sudo tee -a ~/.tmux.conf <<'TMUX_EOF'

# Set terminal type for better color support
set -g default-terminal "tmux-256color"

# Enable OSC 52 clipboard support
set -g set-clipboard on
set -as terminal-features ",osc52"

# Map Copy Mode to use wl-copy for Wayland
# This replaces the standard paste-buffer logic for the 'y' key in copy mode
bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "wl-copy -n"
bind -T copy-mode send-keys -X copy-pipe-and-cancel "wl-copy -n"

# Optional: Allow pasting directly with mouse (middle click)
bind M paste-buffer

# Reload tmux config: tmux source-file ~/.tmux.conf

TMUX_EOF


# NeoVim

# Configure Neovim (init.lua) - see neovim file

