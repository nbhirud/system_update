# Fedora 44 Python Development Setup

A dedicated, repeatable setup repository for the user's Fedora 44 KDE workstations. Keep this repo separate from application repositories and clone it onto each workstation.

## Design decisions

- Fedora's `/usr/bin/python3` remains managed by RPM. No `sudo pip`, no system interpreter replacement, and no Python packages are installed into the system interpreter.
- `uv` is installed with Astral's official installer. The latest stable Python 3 is managed by `uv` for projects; a separate managed Python 3.12 is used by global CLI tools for compatibility. Project environments are local `.venv` directories and project lockfiles are committed. A managed Zsh block sets `UV_PYTHON_PREFERENCE=only-managed` so new project environments do not silently select Fedora system Python.
- Global CLI utilities are installed in isolated `uv tool` environments, using a `uv`-managed Python: Ruff, Black, Flake8, isort, basedpyright, Pyright, mypy, ty, pytest, coverage, debugpy, pre-commit, pip-audit, and Poetry.
- Phase 1 installs the complete Fedora build foundation by default; there are no selective install flags. RPM checks are only for idempotence.
- Zsh and Oh My Zsh are installed/configured. The installer preserves an existing `.zshrc`, adds marked managed blocks, and sets Zsh as the current user's login shell when permitted.
- `direnv` is integrated into Zsh, but **no `.envrc` is ever approved automatically**.
- Existing projects and their managers/configuration are left alone. New projects may use uv; Poetry and pip/requirements projects remain supported.
- New-project tooling uses Ruff by default. Black, Flake8, isort, mypy, Pyright/basedpyright, and ty remain available for projects which use them.
- Phase 1 and Phase 3 do not modify editor/IDE settings or apply broad firewall/network blocks. VS Code Copilot is not blocked. IDE setup/privacy settings are reserved for Phase 2.
- DuckDB and Valkey are not installed or configured. Jupyter and marimo are not installed globally; add them to a project's own environment when needed.

## Requirements and safety

Designed for Fedora 44 on x86-64 or ARM64 workstations, with network access for DNF and official tool/package downloads. Phase 1 needs `sudo` privileges for RPM installation. The inventory report and configuration backups are stored under `~/nb/nbPython_script_backups/` with restrictive permissions. No `.zshrc` contents, environment variable values, secrets, editor settings, or credentials are copied into the inventory report.

The official `uv` installer and the official Oh My Zsh installer are downloaded over HTTPS and executed. Review these scripts and their upstreams before running them if your threat model requires vendor-script pinning.

## Phase 1 — system foundation

From the root of this repository, run in a terminal:

```bash
bash scripts/python_setup_phase1.sh
```

Phase 1 inventories the machine first, displays the plan, asks for confirmation, installs the complete RPM foundation, installs/updates uv, installs current stable managed CPython 3 plus managed Python 3.12 for CLI-tool compatibility, installs all listed isolated CLI tools, configures Oh My Zsh/Zsh and direnv, and then verifies the resulting commands. It does not configure IDEs.

The default RPM foundation includes `curl`, `ca-certificates`, `git`, `zsh`, `direnv`, `pciutils` (for `lspci` hardware inventory), `gcc`, `gcc-c++`, `make`, `pkgconf-pkg-config`, OpenSSL/FFI/Zlib/BZip2/readline/SQLite/XZ/Tk/GDBM/ncurses/UUID development headers, `python3-devel`, and Fedora's `python3-pip` package. The package is installed for compatibility with system-managed Python workflows, but these scripts never use it to install packages.

## Phase 3 — templates and end-to-end CLI validation

After Phase 1 completes:

```bash
bash scripts/python_setup_phase3.sh
```

Phase 3 creates `~/nb/CodeProjects/python-setup-validation` only if the path does not already exist. It provisions a project-local `.venv`, pins a current managed Python, locks dependencies and tests:

- FastAPI and Pydantic
- Django
- NumPy and pandas
- boto3
- pytest and coverage
- Ruff linting and formatting
- basedpyright
- pre-commit hooks, including pip-audit
- a simple Python script smoke test

This validation project intentionally exercises the requested libraries in one disposable development project. Ordinary project templates do **not** force every runtime library into every application: add only what that application needs to its own `.venv` to avoid unnecessary dependency coupling. The validation project downloads dependencies and pip-audit queries vulnerability data, so this phase needs network access.

If that path already exists, Phase 3 stops rather than overwriting data. Remove it manually only if you have confirmed it is disposable.

## Start a new uv project

```bash
mkdir -p ~/nb/CodeProjects
cd ~/nb/CodeProjects
uv python install 3
mkdir my-project && cd my-project
uv init --python 3
uv --version
uv add pydantic fastapi       # only if this project needs them
uv add --dev ruff basedpyright pytest pytest-cov pip-audit pre-commit
uv lock
uv sync --locked --group dev
uv run --locked --group dev pre-commit install
```

Copy/merge `templates/pyproject.toml.template`, `templates/.envrc.template`, `templates/.gitignore.python.template`, `templates/.flake8.template`, and `templates/pre-commit-config.yaml.template` as appropriate. Projects using Black/Flake8/isort instead of Ruff can use `templates/pre-commit-config.legacy.yaml.template` and add those tools to their own `dev` dependency group. Do not blindly overwrite existing project settings. Review `.envrc` before running `direnv allow`.

## Existing projects

- **uv:** use the project's `pyproject.toml`, `.python-version` and `uv.lock`; preserve its pin and use `uv sync --locked`.
- **Poetry:** preserve `pyproject.toml` and `poetry.lock`, and use Poetry's project environment.
- **pip/requirements:** preserve the declared Python version and requirements/constraints files; create a project-local `.venv` and use that environment's pip only.
- **Conda/PDM/Pipenv or another manager:** inventory them first and do not convert projects automatically.
- Tool versions and hooks should be defined per-project and locked, rather than relying on globally upgraded CLIs for reproducible CI.

## Libraries by project type

```bash
uv add pydantic fastapi uvicorn  # API/service
uv add django                    # Django
uv add numpy pandas              # data/numerical work
uv add boto3                     # AWS SDK
uv add --dev pytest pytest-cov httpx  # tests
uv add --dev jupyter              # only projects which need notebooks
uv add --dev marimo               # only projects which need marimo
```

## Backup and recovery

Backups are created before managed file edits under `~/nb/nbPython_script_backups/`. Backup filenames begin with the script name (for example, `python_setup_direnv_...`). Inventory report filenames begin with `python_setup_inventory_...`. Installation is not automatically rolled back because removing RPMs or managed tools could damage a pre-existing setup.

## Phase 2 (separate)

Phase 2 will handle Python setup inside VSCodium (personal default), VS Code (work; preserve Copilot), Neovim/LazyVim, PyCharm, and RustRover via JetBrains Toolbox; configure run/test/debug, linting and type-checking; and harden privacy/telemetry settings without breaking functionality. The current phases do not edit those IDEs.

## Validate this repository without installing anything

```bash
bash scripts/validate_repository.sh
```

This checks required file presence, non-empty contents, Bash syntax, template parsing where the relevant Python modules are available, and the shared managed-block helper in a temporary test directory. It does not install Fedora packages or claim a live Fedora end-to-end run.
