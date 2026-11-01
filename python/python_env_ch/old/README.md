# Fedora Python Development Setup

A local-first, reproducible Python development foundation for Fedora 44 KDE. It is designed to be cloned into a dedicated Git repository and rerun on new systems.

## Scope

- Phase 1: read-only inventory, Fedora foundation RPMs, official standalone uv, uv-managed stable CPython, isolated CLI tools (Ruff, basedpyright, mypy, ty, pytest, coverage, debugpy, pre-commit, pip-audit and Poetry), Zsh/Oh My Zsh + direnv hook.
- Phase 2: intentionally separate; editor settings and privacy hardening are not changed by these scripts.
- Phase 3: reusable project templates and a disposable FastAPI validation project with CLI checks and Git-hook validation.

## Safety principles

- Does not replace or modify Fedora's system Python.
- Never uses `sudo pip`, never runs uv as root.
- Never installs/configures DuckDB or Valkey.
- Does not install Jupyter or marimo globally.
- Does not edit VSCodium, VS Code, PyCharm, or Neovim configuration.
- Backs up `~/.zshrc` before adding managed blocks. Backups and inventory reports live under `~/nb/nbPython_script_backups/`.
- Does not approve `.envrc`; each project requires explicit `direnv allow` after review.
- Does not overwrite an existing Phase 3 validation directory.
- Existing project files and their package-manager choices remain authoritative.

## Run Phase 1

Clone this repository, inspect the scripts, then run:

```bash
cd python-dev-setup
bash scripts/python_setup_phase1.sh
```

The script writes a read-only inventory before asking to proceed. To accept the prompt non-interactively:

```bash
bash scripts/python_setup_phase1.sh --yes
```

Optional native-extension build prerequisites:

```bash
bash scripts/python_setup_phase1.sh --with-build-deps
```

Upgrade existing uv and uv-managed CLI tools intentionally:

```bash
bash scripts/python_setup_phase1.sh --upgrade-tools
```

Install Pyright as an additional CLI alternative to basedpyright:

```bash
bash scripts/python_setup_phase1.sh --install-pyright
```

Do not run with `--yes` until you have reviewed the scripts and understand the changes. `--yes` only skips the confirmation; it does not skip inventory.

## Run Phase 3

After Phase 1:

```bash
bash scripts/python_setup_phase3.sh
```

This creates `~/nb/CodeProjects/python-setup-validation` only if that path does not already exist. It generates a uv lockfile and `.venv`, installs FastAPI and dev tools, runs smoke tests, initializes Git, and installs/runs pre-commit hooks. It intentionally does not launch editors or edit their settings.

## New-project workflow (uv)

For a new project, use a current stable Python compatible with the libraries you need:

```bash
cd ~/nb/CodeProjects
mkdir my-project && cd my-project
git init
uv init --python 3
# Add dependencies and development tools as needed:
uv add fastapi pydantic
uv add --dev ruff basedpyright pytest pip-audit pre-commit
uv lock
uv sync --locked --group dev
cp /path/to/python-dev-setup/templates/.envrc.template .envrc
cp /path/to/python-dev-setup/templates/pre-commit-config.yaml.template .pre-commit-config.yaml
cp /path/to/python-dev-setup/templates/.gitignore.python.template .gitignore
# Review .envrc before approving it:
direnv allow
uv run pre-commit install
```

Adapt `.gitignore` rather than blindly replacing an existing one. Commit `pyproject.toml`, `uv.lock`, `.pre-commit-config.yaml`, source, tests, and safe examples; never commit `.venv`, `.env`, or real credentials.

## Existing project workflow

- uv project: follow `pyproject.toml` and `uv.lock`; use `uv sync --locked`.
- Poetry project: use its existing `pyproject.toml` and `poetry.lock`; use Poetry unless the repository maintainers specify otherwise.
- requirements.txt/pip project: use the documented Python version and requirements files, preferably in `.venv`; do not convert automatically.
- Other package managers: preserve the repository's established workflow.

## direnv security

`direnv` is opt-in. Inspect `.envrc` before running `direnv allow`. Approval authorizes executable shell code. Do not put secrets in `.envrc`; use environment variables, a protected local secret file, KeePassXC, or an appropriate secret manager.

## Tool policy

- Shared isolated CLI tools: uv, Ruff, basedpyright, mypy, ty, pre-commit, pip-audit and Poetry.
- Project-specific versions should be declared in the project and lockfile. The global CLI tools are conveniences, not a replacement for reproducible project dependencies.
- The pre-commit `pip-audit` hook audits the active project environment via `uv run`; it does not pass `--locked` to pip-audit, because pip-audit's `--locked` option targets supported `pylock.*.toml` files rather than uv's `uv.lock` format.
- Ruff is preferred for new projects. Existing Black/Flake8/isort projects retain their own configured tools.
- VSCodium/Neovim: basedpyright is the preferred language-server choice. VS Code work projects can use Pylance. Phase 2 will handle editor-specific setup and telemetry/privacy settings while preserving Copilot.
- Jupyter/marimo are intentionally not installed by default.

## Privacy / telemetry boundary

Phase 1 does not apply broad DNS/firewall blocks or change IDE settings. The Python CLI tools installed here do not require a blanket telemetry block. IDE, extension and JetBrains privacy settings are deliberately reserved for Phase 2, where settings can be backed up and tested individually. VS Code Copilot is not blocked by this setup.

## Hardware-aware behavior

The inventory reports CPU, RAM, storage, and GPU. The setup avoids expensive source builds by default and uses prebuilt packages where available. Pass `--with-build-deps` only if you need to compile native extensions. No GPU-specific Python stack is installed automatically.

## Backups and recovery

Backups and inventory reports are stored in `~/nb/nbPython_script_backups/`. Review the exact timestamped directory printed by the script. The scripts only modify the managed blocks they add; they do not automatically roll back package installations.
