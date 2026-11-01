# Python development foundation (Fedora 44)

Production-ready setup for a multi-machine Fedora 44 + KDE environment.

## Goals

- **uv** as the primary package / environment / Python version manager
- System Python left completely untouched
- In-project `.venv`
- Global tools via `uv tool` (ruff, pre-commit, basedpyright, mypy, ty, pip-audit)
- **direnv** opt-in per project
- Support existing Poetry / requirements.txt / pip projects
- Hardware-aware concurrency (low-RAM machines get reduced parallelism)
- Project config lives in the git repo; this setup repo is cloned on new machines

## Layout

```
python-dev-setup/
├── python_setup_phase1.sh      # Foundation (uv, tools, shell)
├── python_setup_phase3.sh      # Templates + validation projects
├── lib/
│   ├── common.sh
│   ├── hardware.sh
│   ├── checks.sh
│   ├── install_uv.sh
│   ├── install_tools.sh
│   └── configure_shell.sh
├── templates/
│   ├── pyproject.toml.tmpl
│   ├── envrc.tmpl
│   └── pre-commit-config.yaml.tmpl
└── README.md
```

Phase 2 (IDE-specific configuration for VSCodium, VSCode, PyCharm, LazyVim) is intentionally separate.

## Quick start (new machine)

```bash
# Clone this repo somewhere convenient, then:
cd python-dev-setup
chmod +x python_setup_phase1.sh python_setup_phase3.sh

# 1. Inventory only (safe)
./python_setup_phase1.sh --checks

# 2. Install foundation
./python_setup_phase1.sh

# 3. New shell so PATH / direnv / completions take effect
exec zsh   # or open a new terminal

# 4. Templates + validation
./python_setup_phase3.sh
```

## Phase 1 details

| Item | Action |
|------|--------|
| uv | Official standalone installer → `~/.local/bin` |
| Python versions | `uv python install 3.12 3.13 3.14` (managed) |
| Global tools | `uv tool install` ruff, pre-commit, basedpyright, mypy, ty, pip-audit |
| direnv | `dnf install direnv` + zsh hook |
| Shell | Managed block in `~/.zshrc` (PATH, UV_PYTHON_PREFERENCE, direnv, completions, aliases) |

Backups of modified files go under `~/nb/nbscript_backups/`.

## Phase 3 details

Creates under `~/nb/CodeProjects/python-setup-validation/`:

1. **fastapi-demo** — minimal FastAPI + pytest + ruff + basedpyright
2. **simple-script** — demonstrates requirements.txt + uv interop

Runs interpreter check, imports, ruff, type check, pytest, and pre-commit.

## New project workflow

```bash
cd ~/nb/CodeProjects
uv init myapp --package
cd myapp
uv python pin 3.14          # or 3.12 / 3.13 as needed
# Optional: copy templates from this repo
cp /path/to/python-dev-setup/templates/envrc.tmpl .envrc
cp /path/to/python-dev-setup/templates/pre-commit-config.yaml.tmpl .pre-commit-config.yaml
# Merge useful bits from templates/pyproject.toml.tmpl into pyproject.toml
direnv allow                # only if you use the .envrc
uv add fastapi pydantic     # example
uv add --group dev ruff pytest basedpyright
uv run pre-commit install
```

## Working with non-uv projects

| Project type | Command |
|--------------|---------|
| Poetry | `uv sync` often works; or `uv pip install` from exported requirements |
| requirements.txt | `uv venv && uv pip install -r requirements.txt` |
| plain pip | Prefer migrating to `pyproject.toml` + uv when practical |

## Aliases (after Phase 1)

| Alias | Expands to |
|-------|------------|
| `uvs` | `uv sync` |
| `uva` | `uv add` |
| `uvr` | `uv run` |
| `uvt` | `uv tree` |
| `uvp` | `uv python` |
| `uvl` | `uv lock` |

## Hardware notes

On machines with ≤ 8 GB RAM the scripts lower `UV_CONCURRENT_DOWNLOADS` / `UV_CONCURRENT_INSTALLS` automatically. Override by exporting those variables before running.

## Out of scope (by design)

- Jupyter / marimo (install per project only)
- DuckDB / Valkey system packages
- IDE settings (Phase 2)
- Cross-machine config sync (Syncthing etc.)
- Changing Fedora system Python
