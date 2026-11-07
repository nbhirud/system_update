#!/usr/bin/env bash
# =============================================================================
# setup_zsh.sh — Zsh + Oh My Zsh + Powerlevel10k setup for Fedora (KDE/Server)
# =============================================================================
# What this script does:
#   1. Detects hardware/profile using the shared common/ detection scripts
#   2. Backs up ALL existing zsh-related config, then wipes and reinstalls fresh
#   3. Installs zsh + CLI toolbelt via dnf, sets zsh as login shell
#   4. Installs Oh My Zsh (unattended), community plugins, Powerlevel10k
#   5. Generates a complete ~/.zshrc with RUNTIME tool detection (docker, aws,
#      podman, kubectl... are only enabled as plugins if actually installed —
#      this replaces the old "flag file" approach and the old static plugin list)
#   6. Verifies the result (--verify-setup re-runs just the verification)
#   7. Can update OMZ + plugins later (--update-omz)
#
# -----------------------------------------------------------------------------
# USEFUL LINKS
# -----------------------------------------------------------------------------
# Zsh (Arch Wiki — best zsh reference on the internet):
#   https://wiki.archlinux.org/title/Zsh
# Oh My Zsh:
#   https://ohmyz.sh/  |  https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins
# OMZ update modes (why we use 'disabled'):
#   https://github.com/ohmyzsh/ohmyzsh/wiki/Settings#automatic-updates
# Powerlevel10k (instant prompt must be first non-comment line of .zshrc):
#   https://github.com/romkatv/powerlevel10k
# fzf-tab (load AFTER compinit, BEFORE zsh-autosuggestions):
#   https://github.com/Aloxaf/fzf-tab
# zsh-autosuggestions:
#   https://github.com/zsh-users/zsh-autosuggestions
# zsh-syntax-highlighting (must be the LAST plugin loaded):
#   https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md
# zsh-completions:
#   https://github.com/zsh-users/zsh-completions
# Fedora zsh + chsh notes (util-linux-user provides chsh on Fedora):
#   https://docs.fedoraproject.org/en-US/quick-docs/configure-zsh-shell/
# zsh options reference:
#   https://man.archlinux.org/man/zshoptions.1
# Bash parameter expansion / arrays (used heavily below):
#   https://www.gnu.org/software/bash/manual/html_node/Arrays.html
# colorizing man pages / LS_COLORS:
#   https://wiki.archlinux.org/title/Color_output_in_console
# previous approaches that were researched and merged/retired are described
# in the "Notes" section at the bottom of this file.
# =============================================================================

set -euo pipefail

#############################################################
# User defined variables — edit before running if desired
#############################################################

# Theme engine for graphical machines. p10k = Powerlevel10k (recommended).
# Headless servers always fall back to robbyrussell regardless of this value.
THEME_ENGINE="p10k"

# Vi mode in zsh (true/false). Nice if you live in neovim; breaks Ctrl+A/Ctrl+E
# muscle memory slightly (restored manually below when enabled). Off by default.
ENABLE_VI_MODE="false"

# Extra packages installed when --setup-type full (default). Set via option too.
DEFAULT_SETUP_TYPE="full"

#############################################################
# Inferred variables
#############################################################

REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
FILENAME_TIMESTAMP="${FILENAME_TIMESTAMP:-$(date +%Y-%m-%d_%H-%M-%S)}"
HOME_DIR="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
NBDIR="${HOME_DIR}/nb"
CODEPROJECTS_DIR="${NBDIR}/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"

SCRIPT_DATA="${NBDIR}/nb_script_data"
SCRIPT_DATA_DOWNLOADS="${SCRIPT_DATA}/downloads"
SCRIPT_DATA_BACKUPS="${SCRIPT_DATA}/backups"
ZSH_BACKUP_DIR_BASE="${SCRIPT_DATA_BACKUPS}/zsh"
ZSH_CURRENT_BACKUP_DIR="${ZSH_BACKUP_DIR_BASE}/zsh_${FILENAME_TIMESTAMP}"

# Distro / desktop / pc-type are inferred if not passed as options.
# The shared detection scripts in linux/commong are the canonical source;
# inline fallbacks keep the script usable on a brand-new machine before the
# repo has ever been cloned.
infer_or_default() {
  # $1 = variable name, $2 = detection script name, $3 = fallback logic
  local var="$1" script="$2" fallback="$3" val
  if [[ -x "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/${script}" ]]; then
    val="$(sh "${SYSUPDATE_CODE_BASE_DIR}/linux/commong/${script}")"
  else
    val="$(eval "$fallback")"
  fi
  printf '%s' "$var" "${val:-}"
}

GETTER_DIR="${SYSUPDATE_CODE_BASE_DIR}/linux/commong"

run_commong() {
  # Run a shared detection script if present, else echo the fallback value.
  # Usage: FOO=$(run_commong get_foo.sh "fallback command")
  local script="$1" fallback="$2"
  if [[ -x "${GETTER_DIR}/${script}" ]]; then
    sh "${GETTER_DIR}/${script}"
  else
    log_warn "Common getter '${script}' not found — using inline fallback"
    eval "$fallback"
  fi
}

CPU_CORES="$(run_commong get_cpu_cores.sh 'nproc')"
RAM_MB="$(run_commong get_ram_size.sh "awk '/MemTotal/{printf \"%d\", \$2/1024}' /proc/meminfo")"
PC_TYPE="$(run_commong get_pc_type.sh 'systemctl is-active graphical.target &>/dev/null && echo desktop || echo server')"
DESKTOP="${DESKTOP:-$(run_commong get_desktop_env.sh 'echo "${XDG_CURRENT_DESKTOP:-unknown}" | tr "[:upper:]" "[:lower:]"')}"
DISTRO="${DISTRO:-$(run_commong get_distro_name.sh "source /etc/os-release && echo \"\$ID\"")}"

IS_HEADLESS=false
[[ "$PC_TYPE" == "server" ]] && IS_HEADLESS=true

# Effective theme: servers never get p10k (no benefit, keeps prompt lean)
if [[ "$IS_HEADLESS" == true ]]; then
  EFFECTIVE_THEME="robbyrussell"
else
  EFFECTIVE_THEME="$THEME_ENGINE"
fi

# Paths of the zsh artifacts we manage
OMZ_DIR="${HOME_DIR}/.oh-my-zsh"
OMZ_CUSTOM="${OMZ_DIR}/custom"
ZSHRC_FILE="${HOME_DIR}/.zshrc"
ZSHRC_LOCAL="${HOME_DIR}/.zshrc.local"
P10K_FILE="${HOME_DIR}/.p10k.zsh"
HIST_FILE="${HOME_DIR}/.zsh_history"

# Distinct ways older versions of this setup scattered zsh config around.
# All of these get backed up (where they exist) in the Backup section and then
# removed, so we always start from a clean slate (fresh > repair-in-place).
OLD_BACKUP_LOCATIONS=(
  "${NBDIR}/nb_script_backups"                                   # zsh.sh-era backup dir
  "${HOME_DIR}/.config/zsh-backups"                              # 'ch'-variant backup dir
  "${ZSHRC_FILE}.bak."*                                          # ad-hoc .zshrc.bak.<ts> copies
)

#############################################################
# Helpers
#############################################################

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'

log_header() { echo -e "\n${CYAN}==================== $* ====================${NC}\n"; }
log_info() { echo -e "${BLUE}[INFO] $* ${NC}"; }
log_success() { echo -e "${GREEN}[✓] $* ${NC}"; }
log_warn() { echo -e "${YELLOW}[!] $* ${NC}"; }
log_error() { echo -e "${RED}[✗] $* ${NC}" >&2; }
log_die() { echo -e "${RED}[✗] $* ${NC}" >&2; exit 1; }

# Backup helper: copies $1 (file or directory) into $ZSH_CURRENT_BACKUP_DIR,
# preserving relative structure, only if it exists.
backup_path() {
  local src="$1"
  [[ -e "$src" ]] || return 0
  mkdir -p "$ZSH_CURRENT_BACKUP_DIR"
  cp -a "$src" "${ZSH_CURRENT_BACKUP_DIR}/$(basename "$src")"
  log_info "Backed up: $src"
}

# Clone-or-pull a git repo (used for OMZ, plugins, theme).
# Keeps shallow clones shallow; if the target exists it is updated, not cloned.
clone_or_pull() {
  local repo_url="$1" dest="$2"
  if [[ -d "$dest/.git" ]]; then
    log_info "Updating $(basename "$dest")..."
    git -C "$dest" pull --quiet --ff-only || log_warn "Could not update $(basename "$dest") (local changes?) — continuing"
  else
    log_info "Cloning $(basename "$dest")..."
    git clone --depth 1 "$repo_url" "$dest" || log_die "Failed to clone $repo_url"
  fi
}

#############################################################
# Named Options processing
#############################################################

# All options are optional; sensible defaults are inferred above.
# Sample call 1 (everything, from the master setup script that already knows
# the environment):
#   bash linux/common/zsh.sh --distro fedora --setup-type full \
#        --desktop kde --theme p10k
# Sample call 2 (bare, on any machine — everything inferred):
#   bash linux/common/zsh.sh
# Update OMZ + plugins in place (no reinstall):
#   bash linux/common/zsh.sh --update-omz
# Just re-run the self-check:
#   bash linux/common/zsh.sh --verify-setup

print_usage() {
  cat <<USAGE
Usage: $0 [OPTIONS]
  --distro <name>      Target distro (default: auto-detected, e.g. fedora)
  --setup-type <type>  full | minimal  (default: ${DEFAULT_SETUP_TYPE})
                       full    = install the whole CLI toolbelt
                       minimal = zsh + core plugins only
  --desktop <name>     kde | gnome | none (default: auto-detected)
  --theme <name>       p10k | robbyrussell | agnoster (default: ${THEME_ENGINE})
  --user <name>        Target user (default: ${REAL_USER})
  --update-omz         Update Oh My Zsh + plugins + theme, then exit
  --verify-setup       Run the verification section only, then exit
  --help               This help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --distro)      DISTRO="$2"; shift 2 ;;
    --setup-type)  SETUP_TYPE="$2"; shift 2 ;;
    --desktop)     DESKTOP="$2"; shift 2 ;;
    --theme)       THEME_ENGINE="$2"; shift 2 ;;
    --user)        REAL_USER="$2"; shift 2 ;;
    --update-omz)  MODE_UPDATE_OMZ=true; shift ;;
    --verify-setup) MODE_VERIFY=true; shift ;;
    --help|-h)     print_usage; exit 0 ;;
    *) log_error "Unknown option: $1"; print_usage; exit 1 ;;
  esac
done

SETUP_TYPE="${SETUP_TYPE:-$DEFAULT_SETUP_TYPE}"
[[ "$IS_HEADLESS" == true ]] && EFFECTIVE_THEME="robbyrussell"

#############################################################
# Distro guard (anything Fedora-specific happens below this)
#############################################################

if [[ "$DISTRO" != "fedora" ]]; then
  log_die "This script targets Fedora (detected/requested: '${DISTRO}').
Aborting before touching anything — dnf-based sections would fail elsewhere."
fi
log_info "Distro: $DISTRO | Setup type: $SETUP_TYPE | Desktop: $DESKTOP | PC type: $PC_TYPE"
log_info "Target user: $REAL_USER | Theme: $EFFECTIVE_THEME | Timestamp: $FILENAME_TIMESTAMP"

#############################################################
# Update mode — update git-installed components and exit
#############################################################

# OMZ + plugins are git clones, NOT dnf packages, so dnf/system upgrades will
# never touch them. This mode (plus the 'nbomzupdate' alias in .zshrc) is how
# they get updated. It can also be wired into a cron job/timer later
# (see linux/common cron_jobs plans).
if [[ "${MODE_UPDATE_OMZ:-false}" == true ]]; then
  log_header "Update OMZ + plugins + theme"
  [[ -d "$OMZ_DIR/.git" ]] || log_die "Oh My Zsh not installed at $OMZ_DIR — run full setup first"
  git -C "$OMZ_DIR" pull --quiet --ff-only || log_warn "OMZ pull failed"
  for p in fzf-tab zsh-autosuggestions zsh-syntax-highlighting zsh-completions; do
    [[ -d "${OMZ_CUSTOM}/plugins/${p}" ]] && clone_or_pull x "${OMZ_CUSTOM}/plugins/${p}" 2>/dev/null || \
      git -C "${OMZ_CUSTOM}/plugins/${p}" pull --quiet --ff-only 2>/dev/null || true
  done
  [[ -d "${OMZ_CUSTOM}/themes/powerlevel10k" ]] && \
    git -C "${OMZ_CUSTOM}/themes/powerlevel10k" pull --quiet --ff-only || true
  log_success "Updates done"
  exit 0
fi

#############################################################
# Backup
#############################################################

log_header "Backup existing configuration"

mkdir -p "$ZSH_CURRENT_BACKUP_DIR"

# Back up every artifact a previous zsh setup (ours or foreign) may own.
# NOTE on strategy: old versions debated rm -rf vs mv for ~/.oh-my-zsh.
# We now COPY .zshrc/.p10k.zsh (small files, easy to diff) and MOVE the big
# .oh-my-zsh tree (it is replaced wholesale anyway, moving is instant and
# atomic on the same filesystem).
backup_path "$ZSHRC_FILE"
backup_path "$ZSHRC_LOCAL"   # local overrides preserved on purpose (secrets);
                             # backed up here only for safety, NOT deleted below
backup_path "$P10K_FILE"
backup_path "$HIST_FILE"
backup_path "${HOME_DIR}/.zshenv"
backup_path "${HOME_DIR}/.zprofile"
backup_path "${HOME_DIR}/.zlogin"
backup_path "${HOME_DIR}/.zcompdump"          # stale completion caches cause weird bugs
backup_path "${HOME_DIR}/.zcompdump."*
backup_path "${HOME_DIR}/.cache/p10k-instant-prompt-${REAL_USER}.zsh"

# Foreign/legacy backup folders left behind by earlier iterations of this
# setup (each past attempt picked its own location). They are copied under
# legacy_locations/ for archaeology and then removed.
LEGACY_DST="${ZSH_CURRENT_BACKUP_DIR}/legacy_locations"
mkdir -p "$LEGACY_DST"
shopt -s nullglob
for loc in "${OLD_BACKUP_LOCATIONS[@]}"; do
  if [[ -e "$loc" ]]; then
    cp -a "$loc" "${LEGACY_DST}/" 2>/dev/null || true
    log_info "Backed up legacy location: $loc"
  fi
done
shopt -u nullglob

chown -R "$REAL_USER:" "$ZSH_CURRENT_BACKUP_DIR" 2>/dev/null || true
log_success "Backup complete: $ZSH_CURRENT_BACKUP_DIR"

# If .zshrc.local existed, keep it (it is intentionally not wiped — it holds
# per-machine secrets/overrides that must survive re-runs of this script).
if [[ -f "$ZSHRC_LOCAL" ]]; then
  log_info "$ZSHRC_LOCAL exists and will be PRESERVED (sourced at end of .zshrc)"
fi

#############################################################
# Reset — remove old setup completely (already backed up)
#############################################################

log_header "Remove old installation"

# Fresh install beats fixing an unknown prior state. Everything removed here
# has a copy in $ZSH_CURRENT_BACKUP_DIR.
[[ -f "$ZSHRC_FILE" ]] && rm -f "$ZSHRC_FILE"
[[ -f "$P10K_FILE" ]] && rm -f "$P10K_FILE"
rm -f "${HOME_DIR}/.zcompdump" "${HOME_DIR}/.zcompdump."*

# .oh-my-zsh is MOVED not deleted: instant, atomic, reversible.
if [[ -d "$OMZ_DIR" ]]; then
  rm -rf "${OMZ_DIR}.old.$FILENAME_TIMESTAMP"   # paranoid: never collide
  mv "$OMZ_DIR" "${ZSH_CURRENT_BACKUP_DIR}/oh-my-zsh"
  log_info "Moved old ~/.oh-my-zsh into backup"
fi

# Remove legacy backup locations themselves (their contents were copied above)
shopt -s nullglob
for loc in "${OLD_BACKUP_LOCATIONS[@]}"; do
  [[ "$loc" == "${NBDIR}/nb_script_backups" || "$loc" == "${HOME_DIR}/.config/zsh-backups" ]] && rm -rf "$loc"
  [[ "$loc" == "${ZSHRC_FILE}.bak."* && -f "$loc" ]] && rm -f "$loc"
done
shopt -u nullglob

log_success "Old setup removed"

#############################################################
# Package installation
#############################################################

log_header "Install packages"

CORE_PACKAGES=(
  zsh             # the shell itself
  git             # version control + used to fetch plugins
  curl            # downloads
  util-linux-user # provides 'chsh' on Fedora (NOT installed by default!)
  fzf             # fuzzy finder — Ctrl+R history, Ctrl+T files, Alt+C dirs
  zoxide          # smarter 'cd' that learns your habits ('z foo')
  eza             # modern ls replacement (successor of exa)
  bat             # cat with syntax highlighting
  ripgrep         # rg — fast grep, respects .gitignore
  fd-find         # fd — fast find, respects .gitignore (binary: /usr/bin/fd)
  jq              # JSON swiss army knife
  tree
  htop
  fastfetch
)

FULL_EXTRA_PACKAGES=(
  lazygit         # terminal git UI
  wl-clipboard    # clipboard access for Wayland (copypath/copyfile plugins)
)

# Filter out what is already installed (pure speed optimization; dnf is a no-op
# for installed packages anyway, but this prints a nicer log).
PKGS_TO_INSTALL=()
for pkg in "${CORE_PACKAGES[@]}"; do
  rpm -q "$pkg" &>/dev/null || PKGS_TO_INSTALL+=("$pkg")
done
if [[ "$SETUP_TYPE" == "full" && "$IS_HEADLESS" == false ]]; then
  for pkg in "${FULL_EXTRA_PACKAGES[@]}"; do
    rpm -q "$pkg" &>/dev/null || PKGS_TO_INSTALL+=("$pkg")
  done
fi

if [[ ${#PKGS_TO_INSTALL[@]} -gt 0 ]]; then
  log_info "Installing: ${PKGS_TO_INSTALL[*]}"
  dnf install -y "${PKGS_TO_INSTALL[@]}"
else
  log_success "All packages already installed"
fi

# torsocks/tor are referenced by shell aliases further down — soft dependency,
# install only if torsocks is configured on this machine. Checked, not assumed.
TOR_SUPPORT=""
command -v torsocks &>/dev/null && TOR_SUPPORT="yes"

#############################################################
# Set zsh as the login shell
#############################################################

log_header "Set zsh as default shell"

ZSH_BIN="$(command -v zsh)"

# chsh requires the target shell to be listed in /etc/shells.
if ! grep -qx "$ZSH_BIN" /etc/shells; then
  echo "$ZSH_BIN" >> /etc/shells
  log_info "Added $ZSH_BIN to /etc/shells"
fi

CURRENT_SHELL="$(getent passwd "$REAL_USER" | cut -d: -f7)"
if [[ "$CURRENT_SHELL" != "$ZSH_BIN" ]]; then
  chsh -s "$ZSH_BIN" "$REAL_USER"
  log_success "Default shell for $REAL_USER changed to $ZSH_BIN"
else
  log_success "zsh already the default shell"
fi

#############################################################
# Install Oh My Zsh + plugins + theme
#############################################################

log_header "Install Oh My Zsh"

# Unattended install as the REAL user (never as root — OMZ lives in $HOME).
# Env vars: RUNZSH=no (don't spawn a shell mid-script),
#           CHSH=no (we did it ourselves above),
#           KEEP_ZSHRC=yes (irrelevant since we deleted it, but explicit).
sudo -u "$REAL_USER" env RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
  sh -c '"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended' \
  || log_die "Oh My Zsh install failed"

log_success "Oh My Zsh installed at $OMZ_DIR"

log_header "Install plugins and theme"

mkdir -p "${OMZ_CUSTOM}/plugins"

# fzf-tab: fuzzy-completes ANY tab-completion through fzf.
# Ordering matters: must load after compinit and before zsh-autosuggestions.
# OMZ's lib/completion.zsh runs compinit BEFORE plugins are sourced, so simply
# listing fzf-tab early in plugins=() satisfies this — the old manual
# 'source fzf-tab.plugin.zsh after compinit' hack is retired.
sudo -u "$REAL_USER" git clone --depth 1 \
  https://github.com/Aloxaf/fzf-tab "${OMZ_CUSTOM}/plugins/fzf-tab"

sudo -u "$REAL_USER" git clone --depth 1 \
  https://github.com/zsh-users/zsh-autosuggestions "${OMZ_CUSTOM}/plugins/zsh-autosuggestions"

# MUST be the last plugin in the array: it wraps ZLE widgets and needs
# everything else already loaded.
sudo -u "$REAL_USER" git clone --depth 1 \
  https://github.com/zsh-users/zsh-syntax-highlighting "${OMZ_CUSTOM}/plugins/zsh-syntax-highlighting"

sudo -u "$REAL_USER" git clone --depth 1 \
  https://github.com/zsh-users/zsh-completions "${OMZ_CUSTOM}/plugins/zsh-completions"

if [[ "$EFFECTIVE_THEME" == "p10k" ]]; then
  log_info "Installing Powerlevel10k theme"
  sudo -u "$REAL_USER" git clone --depth 1 \
    https://github.com/romkatv/powerlevel10k "${OMZ_CUSTOM}/themes/powerlevel10k"
fi

# Ownership sanity (in case anything ran as root)
chown -R "$REAL_USER:" "$OMZ_DIR"

#############################################################
# Generate ~/.zshrc
#############################################################

log_header "Generate .zshrc"

# Written as the real user, NOT with sudo tee (old script did 'sudo tee -a
# ~/.zshrc' which silently creates ROOT-owned dotfiles — a classic footgun).
sudo -u "$REAL_USER" tee "$ZSHRC_FILE" > /dev/null <<'ZSHRC_EOF'
# ============================================================================
# ~/.zshrc — generated by setup_zsh.sh
# Machine profile baked at generation time; tool detection is RUNTIME (below).
# ============================================================================

# ---------------------------------------------------------------------------
# Powerlevel10k instant prompt.
# Must be the FIRST non-comment line in .zshrc: it renders the prompt before
# the rest of the config loads, hiding startup latency entirely.
# Note: p10k-instant-prompt-cache must also be the last source for the
# cleanup trap; OMZ+p10k handle this via 'p10k finalize'.
# ---------------------------------------------------------------------------
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ============================================================================
# Path / environment
# ============================================================================

export PATH="$HOME/.local/bin:$PATH"
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"   # Rust

export EDITOR="nvim"
export VISUAL="vscodium"

# Suffix aliases — type a filename directly and it opens in the right app.
# Works anywhere zsh runs, complements xdg-open/MIME defaults.
alias -s {txt,md,json,yaml,yml,py,rs,toml}=nvim
alias -s {html,pdf}=librewolf

# ============================================================================
# Oh My Zsh core
# ============================================================================

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="__THEME__"

# ---------------------------------------------------------------------------
# RUNTIME plugin detection.
# Previous versions built the plugin list at INSTALL time based on what was
# installed that day (and the earliest version just hardcoded everything,
# relying on manual maintenance). Both went stale: install Docker a week later
# and the plugin never appeared.
# Now: every optional plugin is guarded by a 'command -v' check that costs
# microseconds at shell startup, so the plugin list is ALWAYS accurate.
# This replaces the old "write a flag file when docker.sh runs" idea — no
# coupling between setup scripts, no stale flags.
# ---------------------------------------------------------------------------
__have() { command -v "$1" &>/dev/null }

__plugins=(git sudo colored-man-pages command-not-found copypath)

# fzf-tab must precede zsh-autosuggestions (it patches the completion system;
# see https://github.com/Aloxaf/fzf-tab#install)
__plugins+=(fzf-tab)

# Distro plugins — detected at runtime, same principle
if [[ -r /etc/os-release ]]; then
  source /etc/os-release
  case "$ID" in
    fedora)  __plugins+=(dnf firewalld) ;;
    ubuntu)  __plugins+=(ubuntu ufw snap) ;;
    debian)  __plugins+=(debian ufw) ;;
    arch)    __plugins+=(archlinux) ;;
  esac
fi

# Developer tools — enabled only when actually present
__have docker   && __plugins+=(docker docker-compose)
__have podman   && __plugins+=(podman)
__have kubectl  && __plugins+=(kubectl)
__have helm     && __plugins+=(helm)
__have aws      && __plugins+=(aws)
__have poetry   && __plugins+=(poetry)
__have uv       && __plugins+=(uv)
__have rsync    && __plugins+=(rsync)
__have fzf      && __plugins+=(zoxide)

# Desktop notification plugin (needs a notification daemon — kdialog on KDE,
# notify-send on GNOME; harmless if absent but skip it on servers)
__have kdialog || __have notify-send && __plugins+=(bgnotify)

# Community plugins, in the required order:
#   zsh-completions  → extra completion definitions
#   zsh-autosuggestions → ghost-text from history (→ to accept)
#   zsh-syntax-highlighting → ALWAYS LAST (wraps ZLE widgets)
__plugins+=(zsh-completions zsh-autosuggestions zsh-syntax-highlighting)

plugins=("${__plugins[@]}")
unset __plugins __have

# No automatic OMZ update checks: zero background git/network activity at
# shell launch. Update deliberately via 'nbomzupdate' alias (bottom).
zstyle ':omz:update' mode disabled

source "$ZSH/oh-my-zsh.sh"

# ============================================================================
# History
# ============================================================================

HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000

setopt INC_APPEND_HISTORY      # write history immediately, not on shell exit
setopt SHARE_HISTORY            # live history shared across open terminals
setopt HIST_IGNORE_ALL_DUPS    # purge older duplicates of a new command
setopt HIST_FIND_NO_DUPS        # skip duplicates while searching
setopt HIST_IGNORE_SPACE        # leading-space commands are NOT logged
                                 # (use for commands containing secrets)
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY              # confirm before executing history expansions

# ============================================================================
# Completion tuning
# ============================================================================

zstyle ':completion:*' menu select                          # arrow keys in menus
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   # case-insensitive
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'

# ============================================================================
# Options
# ============================================================================

unsetopt BEEP
setopt AUTO_CD              # type a dir name to cd into it
setopt EXTENDED_GLOB
setopt INTERACTIVE_COMMENTS # allow # comments interactively

# ============================================================================
# Aliases — modern replacements
# ============================================================================

alias ls='eza --group-directories-first'
alias ll='eza -lah --group-directories-first --git'
alias lt='eza --tree --level=2'
alias cat='bat --paging=never'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip --color=auto'
alias df='df -h'
alias du='du -sh'
alias free='free -h'
alias mkdir='mkdir -pv'
alias cp='cp -iv'
alias mv='mv -iv'
# rm deliberately NOT aliased to -i: muscle memory of being prompted fades
# exactly when it matters. Prefer being careful over synthetic safety.
alias ping='ping -c 5'
alias ports='ss -tulpn'
alias psg='ps aux | grep -v grep | grep'
alias myip='curl -s ifconfig.me'
alias flushdns='sudo resolvectl flush-caches'
alias ff='fastfetch'
alias h='history | tail -50'
alias c='clear'
alias q='exit'
alias top='htop 2>/dev/null || top'

# Editors
alias v='nvim'
alias vi='nvim'
alias vim='nvim'
alias sv='sudo -e'   # sudoedit: safer than sudo nvim (edits a temp copy)

# Fedora / dnf
alias dnfi='sudo dnf install'
alias dnfr='sudo dnf remove'
alias dnfs='dnf search'
alias dnfu='sudo dnf upgrade --refresh'
alias zshrc='${EDITOR} ~/.zshrc'
alias reload='source ~/.zshrc && echo "zshrc reloaded"'

# Git
alias gs='git status -sb'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias glog='git log --oneline --graph --decorate --all'

# Containers
alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dimg='docker images'
alias dlogs='docker logs -f'
alias dexec='docker exec -it'
alias dprune='docker system prune -af'
alias p='podman'

# Python
alias py='python3'
alias venv='python3 -m venv .venv && source .venv/bin/activate'
alias activate='source .venv/bin/activate'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# ============================================================================
# Functions
# ============================================================================

mkcd() { mkdir -p "$1" && cd "$1"; }

up() {  # up 3 == cd ../../..
  local count="${1:-1}" path=""
  for i in $(seq 1 "$count"); do path="../$path"; done
  cd "$path"
}

fcd() {  # fzf-powered cd with directory preview
  local dir
  dir=$(fd --type d --hidden --exclude .git 2>/dev/null | \
        fzf --preview 'eza --tree --level=2 {}') && cd "$dir"
}

fkill() {  # fzf-powered process killer
  local pid
  pid=$(ps aux | fzf --header='Select process to kill' | awk '{print $2}')
  [[ -n "$pid" ]] && kill -9 "$pid" && echo "Killed PID $pid"
}

fe() {  # open a file in $EDITOR via fzf
  local file
  file=$(fzf --preview 'bat --color=always --style=numbers {}') && ${EDITOR:-nvim} "$file"
}

# ============================================================================
# fzf / fd integration (fzf-tab covers completion; these are key bindings)
# ============================================================================

if [[ -f /usr/share/fzf/shell/key-bindings.zsh ]]; then
  source /usr/share/fzf/shell/key-bindings.zsh
  source /usr/share/fzf/shell/completion.zsh
fi

export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

# zoxide init (must come after compinit)
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# ============================================================================
# Prompt / theme finalization
# ============================================================================

# Powerlevel10k user config — regenerate anytime with 'p10k configure'.
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# Show hostname on the right side — instantly identifies SSH sessions even
# when the theme doesn't render a context segment (works with ANY theme).
export RPROMPT='%F{yellow}%m%f'

# ============================================================================
# Per-machine convenience block (kept from previous setup, with fixes)
# ============================================================================

# --- Constants, flags, paths ------------------------------------------------
HOME_DIR=$(getent passwd "$USER" | cut -d: -f6)
NBDIR="$HOME_DIR/nb"
CODEPROJECTS_DIR="$NBDIR/CodeProjects"
SYSUPDATE_CODE_BASE_DIR="${CODEPROJECTS_DIR}/system_update"

# --- Update / maintenance aliases --------------------------------------------
# OLD: alias nbupdate="... aws update ... omz update -y ..."
#   'aws update' is not a valid command (aws cli has no update subcommand) —
#   it failed silently in a && chain, aborting the rest. Removed.
#   'omz update -y': -y is not an omz flag; unattended is '--unattended',
#   but plain 'omz update' prompts only when there are changes. Kept plain.
#   torsocks guards added: '. torsocks off' in a && chain aborts everything
#   on machines where torsocks isn't installed.
alias nbupdate=". torsocks off 2>/dev/null; sudo dnf upgrade --refresh -y && flatpak update -y && uv self update 2>/dev/null; omz update; . torsocks on 2>/dev/null; fastfetch"
alias nbupdateextra=". torsocks off 2>/dev/null; sh ${SYSUPDATE_CODE_BASE_DIR}/linux/fedora/update_all.sh && nbupdate"
alias nbreload="systemctl daemon-reload && source ~/.zshrc"
# OLD: alias nbclean="... dnf clean -y all && yum clean -y all ..."
#   Fixed: 'dnf clean' takes no -y, and 'yum clean' is a redundant shim on
#   modern Fedora (dnf replaced yum; the yum binary only forwards).
alias nbclean="sync && sudo dnf autoremove && sudo dnf clean all && flatpak uninstall --unused && sudo bleachbit --clean --preset && bleachbit --clean --preset && sudo resolvectl flush-caches && sudo resolvectl reset-statistics"
alias nbtoron=". torsocks on"
alias nbtoroff=". torsocks off"
alias nbshutdown="nbupdateextra && nbclean && shutdown"
alias nbreboot="nbupdate && nbclean && reboot"

# Update OMZ + plugins + theme (the git-based pieces; see --update-omz mode
# of setup_zsh.sh for the scripted equivalent)
alias nbomzupdate="omz update && git -C \${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/plugins/fzf-tab pull --ff-only && git -C \${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions pull --ff-only && git -C \${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting pull --ff-only && git -C \${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/plugins/zsh-completions pull --ff-only"

# --- Misc -------------------------------------------------------------------
alias nbjoplinupdate="wget -O - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash"
alias nbuvupdate="uv self update"
alias gearlever='flatpak run it.mijorus.gearlever'
# flatpak run it.mijorus.gearlever --update <name of appimage>  # updates 1 appimage at a time

# OLD (agnoster era): overriding prompt_context() to show [SSH] in the prompt.
# Retired: only worked with the agnoster theme's internals. Under p10k, the
# 'context' prompt segment already shows user@host on SSH/root sessions, and
# the RPROMPT hostname above covers every other theme.

# --- Enable tor (guarded) ----------------------------------------------------
# OLD: bare '. torsocks on' — broke every new shell on machines without
# torsocks installed, and hung prompts when the tor daemon was down.
# Guarded version: only when torsocks exists AND tor looks reachable.
if command -v torsocks >/dev/null 2>&1 && systemctl is-active --quiet tor 2>/dev/null; then
  . torsocks on
fi

# --- VS Code-family integration ----------------------------------------------
# Used by OMZ's vscode plugin to decide the editor binary (codium here).
VSCODE=codium

# ============================================================================
# Local overrides — machine-specific, never synced/shared
# ============================================================================
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# ============================================================================
# Startup profiling — uncomment BOTH zprof lines to debug slow shells:
#   zmodload zsh/zprof   (top of file)
#   zprof                (here)
# ============================================================================
ZSHRC_EOF

# Substitute the baked-in theme
sed -i "s|__THEME__|${EFFECTIVE_THEME}/powerlevel10k|" "$ZSHRC_FILE" 2>/dev/null || \
  sed -i "s|__THEME__|${EFFECTIVE_THEME}|" "$ZSHRC_FILE"
# If theme is not p10k, the slash-suffixed sed failed on purpose; run plain:
if grep -q '__THEME__' "$ZSHRC_FILE"; then
  sed -i "s|__THEME__|${EFFECTIVE_THEME}|" "$ZSHRC_FILE"
fi

chmod 600 "$ZSHRC_FILE"
chown "$REAL_USER:" "$ZSHRC_FILE"
log_success ".zshrc written ($EFFECTIVE_THEME theme, runtime tool detection)"

#############################################################
# Verification
#############################################################

verify_setup() {
  log_header "Verification"
  local failures=0
  local check_desc

  # Each check: describe, run, count failures.
  vcheck() {
    if eval "$2"; then log_success "$1"; else log_error "FAILED: $1"; failures=$((failures+1)); fi
  }

  vcheck "zsh binary installed"        'command -v zsh &>/dev/null'
  vcheck "zsh in /etc/shells"          'grep -qx "$(command -v zsh)" /etc/shells'
  vcheck "login shell is zsh"          '[[ "$(getent passwd "$REAL_USER" | cut -d: -f7)" == "$(command -v zsh)" ]]'
  vcheck "OMZ installed"               '[[ -d "$OMZ_DIR" ]]'
  vcheck "OMZ owned by $REAL_USER"     '[[ "$(stat -c %U "$OMZ_DIR")" == "$REAL_USER" ]]'
  vcheck ".zshrc exists, owned by $REAL_USER, mode 600" '[[ "$(stat -c %U "$ZSHRC_FILE")" == "$REAL_USER" && "$(stat -c %a "$ZSHRC_FILE")" == "600" ]]'
  vcheck "fzf-tab plugin present"      '[[ -f "${OMZ_CUSTOM}/plugins/fzf-tab/fzf-tab.plugin.zsh" ]]'
  vcheck "zsh-autosuggestions present" '[[ -f "${OMZ_CUSTOM}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]'
  vcheck "zsh-syntax-highlighting present" '[[ -f "${OMZ_CUSTOM}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]'
  vcheck "zsh-completions present"     '[[ -d "${OMZ_CUSTOM}/plugins/zsh-completions" ]]'
  vcheck "zoxide installed"            'command -v zoxide &>/dev/null'
  vcheck "fzf installed"               'command -v fzf &>/dev/null'

  if [[ "$EFFECTIVE_THEME" == "p10k" ]]; then
    vcheck "powerlevel10k theme present" '[[ -d "${OMZ_CUSTOM}/themes/powerlevel10k" ]]'
  fi

  # Syntax check of the generated config (parses without executing)
  vcheck ".zshrc parses cleanly (zsh -n)" 'zsh -n "$ZSHRC_FILE"'

  # Functional smoke test: spawn an interactive zsh that sources .zshrc.
  # timeout guards against something hanging the shell at startup.
  if timeout 15 sudo -u "$REAL_USER" zsh -ic 'echo SMOKE_OK' 2>/dev/null | grep -q SMOKE_OK; then
    log_success "interactive shell smoke test passed"
  else
    log_error "FAILED: interactive shell smoke test (shell hangs or errors on startup)"
    log_error "Debug with: zsh -xv 2> >(tee /tmp/zsh-debug.log)"
    failures=$((failures+1))
  fi

  echo ""
  if [[ $failures -eq 0 ]]; then
    log_success "ALL CHECKS PASSED"
  else
    log_die "$failures verification check(s) failed"
  fi
}

verify_setup

#############################################################
# Summary
#############################################################

log_header "Setup complete"

cat <<SUMMARY
Machine      : $(hostname -s) ($PC_TYPE)
Theme        : $EFFECTIVE_THEME
Setup type   : $SETUP_TYPE
Backup at    : $ZSH_CURRENT_BACKUP_DIR
Tor support  : ${TOR_SUPPORT:-absent (aliases guarded)}

NEXT STEPS:
  1. Log out / back in (or: exec zsh)
  2. On first graphical login run: p10k configure   # one-time wizard
     (pick 'Lean' or 'Classic'; your Nerd Fonts are already installed)
  3. Per-machine secrets/overrides: ~/.zshrc.local (preserved across reruns)
  4. Keep OMZ/plugins updated:  nbomzupdate  (or: $0 --update-omz)
SUMMARY

# =============================================================================
# Notes
# =============================================================================
#
# DESIGN DECISIONS (and what they replaced)
#
# 1. Runtime plugin detection replaces the static plugin list.
#    OLDER APPROACHES: (a) hardcoded plugin lists maintained by hand
#    (zsh_orig.sh), (b) building the list at install time based on what was
#    installed that day (zsh.sh), (c) the never-implemented TODO of writing a
#    flag file from docker.sh/podman.sh for zsh.sh to read.
#    WHY REPLACED: all of them go stale — install docker a month later and
#    the plugin never activates. A 'command -v' guard costs microseconds per
#    shell start and is always accurate. No inter-script coupling either.
#
# 2. Theme: Powerlevel10k on desktops, robbyrussell on headless server.
#    OLDER APPROACHES: RAM-based theme selection (zsh_cl.sh picked Starship
#    under 6 GiB, P10k above), agnoster (zsh_orig.sh/notes era).
#    WHY REPLACED: prompt latency comes from fork-heavy widgets and slow
#    compinit, not RAM. p10k's instant prompt makes startup appear ~0ms even
#    on the i3-6100U, and p10k is in-tree maintained; agnoster needs patched
#    powerline fonts and shows no git timings. Starship on a machine that
#    runs KDE comfortably buys nothing measurable.
#
# 3. fzf-tab in the plugins array (was: manual 'source' after compinit).
#    OMZ sources lib/completion.zsh (which runs compinit) BEFORE plugins,
#    so array placement 'after zsh-completions, before zsh-autosuggestions'
#    satisfies fzf-tab's ordering contract with zero extra code.
#
# 4. OMZ updates: mode disabled + nbomzupdate alias.
#    'mode disabled' stops background git/network activity at every shell
#    launch (privacy + startup speed). Because OMZ/plugins are git clones
#    rather than dnf packages, this script provides --update-omz and the
#    alias keeps the manual path one keystroke away. A cron/systemd-timer
#    can call --update-omz for automation later.
#
# 5. Backups: standardized under ${SCRIPT_DATA_BACKUPS} (was: four different
#    ad-hoc locations across script generations — all now swept into
#    legacy_locations/ during Backup).
#
# 6. Writing .zshrc as the real user via 'sudo -u ... tee' (was: 'sudo tee -a
#    ~/.zshrc'), which created root-owned dotfiles and caused bizarre
#    permission bugs later.
#
# 7. No Security section: zsh opens no network listeners and adds no daemons,
#    so there is nothing meaningful for firewalld/SELinux/clamav here.
#    .zshrc is chmod 600 and history hygiene is handled via setopts.
#
# 8. Known limitation: generated .zshrc uses baked values for theme; if you
#    change your mind, edit ZSH_THEME= in ~/.zshrc or rerun this script with
#    --theme <name>.
#
# =============================================================================
# Troubleshooting / Debugging
# =============================================================================
#
# Slow shell startup:
#   - Uncomment 'zmodload zsh/zprof' at the very top of ~/.zshrc and 'zprof'
#     at the very bottom; restart zsh; read the table top-down.
#   - Most common culprits: compinit (fixed by the daily-cache pattern —
#     already unnecessary under OMZ which caches), nvm/pyenv init scripts,
#     autosuggestions with huge history. Check: time zsh -i -c exit
#
# Weird completions after a zsh/OMZ update:
#   rm -f ~/.zcompdump* && exec zsh
#
# p10k icons show as boxes/question marks:
#   Terminal font must be a NERD FONT (JetBrainsMono Nerd Font etc.), set in
#   the terminal emulator settings (Alacritty/Konsole), not in p10k.
#
# 'p10k configure' never prompts / config lost after reinstall:
#   Config lives in ~/.p10k.zsh. This script backs it up and removes it on
#   rerun (fresh setup policy). Restore with:
#     cp "<backup dir>/p10k.zsh" ~/.p10k.zsh
#
# History seems truncated:
#   SAVEHIST was raised to 50000; old shells running concurrently with
#   SHARE_HISTORY can interleave writes — close old terminals first.
#   Commands typed with a LEADING SPACE are intentionally not recorded
#   (HIST_IGNORE_SPACE).
#
# chsh: "shell is invalid":
#   zsh wasn't in /etc/shells. The script appends it; manual fix:
#     echo "$(command -v zsh)" | sudo tee -a /etc/shells
#
# torsocks aliases do nothing:
#   Guarded by: torsocks installed AND tor service active. Check:
#     command -v torsocks; systemctl status tor
#   Enable: sudo systemctl enable --now tor
#
# Shell starts, then drops to sh / OMZ complains "can't find module":
#   Usually a half-written ~/.oh-my-zsh from an interrupted clone. Rerun this
#   script (it wipes and reinstalls cleanly) rather than repairing by hand.
#
# Verification smoke test fails but zsh -n passes:
#   Something in .zshrc errors only at runtime (typical suspects:
#   ~/.zshrc.local or a tool that prints to stdout during init). Debug:
#     zsh -xv 2> >(tee /tmp/zsh-debug.log)
#     less /tmp/zsh-debug.log
#
# Want to try a different theme without a full rerun:
#     omz theme set robbyrussell      # temporarily
#     # or permanently: edit ZSH_THEME= in ~/.zshrc
#
# Roll everything back:
#   The full previous state is in $ZSH_CURRENT_BACKUP_DIR —
#   .zshrc, .p10k.zsh, .zshrc.local, history, and the whole old .oh-my-zsh.
#     cp "$ZSH_CURRENT_BACKUP_DIR/.zshrc" ~/.zshrc
#     rm -rf ~/.oh-my-zsh && mv "$ZSH_CURRENT_BACKUP_DIR/oh-my-zsh" ~/.oh-my-zsh
# =============================================================================
