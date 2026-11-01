'''Create an explicit new project and validate non-GUI workflows.

No existing repository is modified. No IDE settings, global git configuration,
direnv approvals, secrets or system Python installations are changed.
'''
from __future__ import annotations
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import textwrap


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(args, cwd=project, env=env, check=True,
                            text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else ""


def write(name: str, text: str) -> None:
    path = project / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(text).lstrip())


name = sys.argv[1]
base = Path.home() / "nb/CodeProjects"
base.mkdir(parents=True, exist_ok=True)
project = base / name
# Atomic mkdir fails for an existing path, including a symlink.
project.mkdir()
env = os.environ.copy()
# Avoid accidental targeting of an activated unrelated environment.
for key in ("VIRTUAL_ENV", "CONDA_PREFIX", "UV_PROJECT_ENVIRONMENT", "UV_PYTHON",
            "UV_PYTHON_PREFERENCE", "UV_PYTHON_DOWNLOADS", "UV_NO_SYNC", "UV_FROZEN"):
    env.pop(key, None)
env["UV_PYTHON_INSTALL_BIN"] = "0"
# Bound workers even if phase 3 is run outside a new zsh session.
mem_gib = 2
try:
    for line in Path("/proc/meminfo").read_text().splitlines():
        if line.startswith("MemTotal:"):
            mem_gib = int(line.split()[1]) // 1048576
except OSError:
    pass
jobs = max(1, min(os.cpu_count() or 2, mem_gib // 2, 8))
env.setdefault("UV_CONCURRENT_BUILDS", str(jobs))
env.setdefault("UV_CONCURRENT_INSTALLS", str(jobs))
env.setdefault("UV_CONCURRENT_DOWNLOADS", "8")
# Resolve latest stable through the installed uv interpreter catalog.
run("uv", "--isolated", "python", "install")
python_path = run("uv", "--isolated", "python", "find", "--managed-python", capture=True)
version = run(python_path, "-c", "import platform; print(platform.python_version())", capture=True)
minor = ".".join(version.split(".")[:2])
write(".python-version", version + "\n")
write("pyproject.toml", f'''
[project]
name = "{name.replace('_', '-')}"
version = "0.1.0"
description = "Repository-local Python development starter"
requires-python = ">={minor}"
dependencies = []

[tool.uv]
package = false

[tool.ruff]
target-version = "py{minor.replace('.', '')}"
line-length = 88

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B"]

[tool.basedpyright]
include = ["app", "scripts", "tests"]
venvPath = "."
venv = ".venv"
pythonVersion = "{minor}"
typeCheckingMode = "standard"

[tool.pyright]
include = ["app", "scripts", "tests"]
venvPath = "."
venv = ".venv"
pythonVersion = "{minor}"
typeCheckingMode = "standard"

[tool.mypy]
python_version = "{minor}"
files = ["app", "scripts", "tests"]
check_untyped_defs = true

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-ra"
''')
write(".gitignore", '''
.venv/
__pycache__/
*.py[cod]
.pytest_cache/
.mypy_cache/
.ruff_cache/
.coverage
htmlcov/
.env
.env.*
!.env.example
.direnv/
.idea/
.vscode/
*.egg-info/
.audit-requirements.txt
''')
write(".envrc", '''
# Review this file, then explicitly execute: direnv allow
# Activation only: no downloads, dependency sync, secrets or arbitrary bootstrap.
watch_file .python-version
watch_file .venv/pyvenv.cfg
if [[ ! -x "$PWD/.venv/bin/python" ]]; then
  log_error "Missing .venv. Run uv sync --locked first."
  return 1
fi
export VIRTUAL_ENV="$PWD/.venv"
PATH_add "$VIRTUAL_ENV/bin"
''')
write(".env.example", "# No secrets are committed. No .env file is automatically loaded.\n")
write("app/__init__.py", '"""Sample application."""\n')
write("app/main.py", '''
"""Small typed FastAPI application for interpreter and debugger verification."""
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()


class Health(BaseModel):
    status: str


@app.get("/health", response_model=Health)
def health() -> Health:
    return Health(status="ok")
''')
write("scripts/hello.py", '''
"""A dependency-free script using the same interpreter as the application."""
import sys


def main() -> None:
    print(f"Hello from {sys.executable}")


if __name__ == "__main__":
    main()
''')
write("tests/test_app.py", '''
"""Exercise the API and simple script without binding a network socket."""
from fastapi.testclient import TestClient
from app.main import app
from scripts.hello import main


def test_health() -> None:
    with TestClient(app) as client:
        response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_script() -> None:
    main()
''')
write("scripts/audit.py", '''
"""Audit every locked dependency, without re-resolving unpinned dependencies.

Runs from the repository root. Temporary requirements are removed on failure too.
Network access to the vulnerability database is expected; findings fail the hook.
"""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="python-audit-") as temporary:
    requirements = Path(temporary) / "requirements.txt"
    subprocess.run(
        ["uv", "export", "--locked", "--all-groups", "--no-emit-project",
         "--no-hashes", "--output-file", str(requirements)],
        cwd=root, check=True,
    )
    subprocess.run(
        [str(root / ".venv/bin/pip-audit"), "--no-deps", "--disable-pip",
         "-r", str(requirements)],
        cwd=root, check=True,
    )
''')
write("scripts/check.sh", '''
#!/usr/bin/env bash
# Run manually and in CI. --locked catches stale lock files; checks do not fix code.
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
uv sync --locked
uv run --locked ruff check .
uv run --locked ruff format --check .
uv run --locked basedpyright
uv run --locked pytest
uv run --locked python scripts/audit.py
''')
(project / "scripts/check.sh").chmod(0o755)
run("uv", "--isolated", "add", "--python", version, "fastapi", "pydantic", "uvicorn")
packages = ["ruff", "basedpyright", "mypy", "ty", "pre-commit", "pip-audit", "pytest",
            "pytest-cov", "debugpy", "httpx"]
run("uv", "--isolated", "add", "--dev", *packages)
# Pin declared direct tool versions to the actual successful resolution.
# Runtime transitives and every tool transitive are also pinned in uv.lock.
versions = json.loads(run(str(project / ".venv/bin/python"), "-c",
    "import json, importlib.metadata as m; print(json.dumps({p:m.version(p) for p in "
    + repr(packages) + "}))", capture=True))
run("uv", "--isolated", "add", "--dev", *(f"{p}=={v}" for p, v in versions.items()))
write(".pre-commit-config.yaml", '''
# Versions live in this repository's exact dev requirements and uv.lock.
# Local hooks use uv, not whichever global ruff happens to be on PATH.
repos:
  - repo: local
    hooks:
      - id: ruff-check
        name: Ruff lint
        entry: uv run --locked ruff check
        language: system
        types_or: [python, pyi]
      - id: ruff-format
        name: Ruff format
        entry: uv run --locked ruff format
        language: system
        types_or: [python, pyi]
      - id: basedpyright
        name: BasedPyright
        entry: uv run --locked basedpyright
        language: system
        pass_filenames: false
        always_run: true
      - id: pip-audit
        name: Audit locked dependencies
        entry: uv run --locked python scripts/audit.py
        language: system
        pass_filenames: false
        always_run: true
''')
write("README.md", f'''
# {name}

CPython {version}; interpreter: `.venv/bin/python`. Fedora's interpreter is unchanged.
Commit `pyproject.toml`, `uv.lock`, `.python-version`, `.envrc` and the hooks.
Never commit `.venv`, API keys, IDE workspace state or `.env` secrets.

## Clone/bootstrap

```sh
uv sync --locked
uv run --locked pre-commit install
# Inspect .envrc before explicitly approving it:
direnv allow
bash scripts/check.sh
```

No implicit direnv approval is performed by setup. A changed `.envrc` needs approval again.
Local hooks require uv and install the locked dev environment when needed.
Audit includes dev tools, needs network access, and fails on vulnerabilities/service errors.
There is no automatic ignore list or audit bypass.

## Application and script

```sh
uv run --locked uvicorn app.main:app --host 127.0.0.1 --port 8000
uv run --locked python scripts/hello.py
uv run --locked pytest --cov=app
uv run --locked mypy
uv run --locked ty check app scripts tests
# Optional debugger: localhost only, no public listener.
uv run --locked python -m debugpy --listen 127.0.0.1:5678 --wait-for-client scripts/hello.py
```

BasedPyright is the default type checker. Mypy and ty are optional alternatives;
configurations and suppression semantics are not interchangeable.

## Optional dependencies: add only when this repository needs them

```sh
uv add numpy pandas boto3 django
uv add duckdb valkey  # Python clients/libraries only; no service installation
uv add --group notebooks jupyterlab ipykernel
uv run --group notebooks jupyter lab --ip=127.0.0.1
# Or, separately:
uv add --group notebooks marimo
uv run --group notebooks marimo edit
```

No notebook dependencies are installed initially. Add pre-commit exclusions and
explicit notebook lint rules if notebooks later enter the repository.

## Manual acceptance in each IDE (phase 2 must already configure extensions)

1. Open this repository as a trusted workspace only after reviewing its contents.
2. Select this repository's `.venv/bin/python`, not Fedora's system Python.
3. Check the integrated terminal: `python -c 'import sys; print(sys.executable)'`.
   Run `uv run --locked python -c 'import sys; print(sys.executable)'` as the control.
4. Confirm imports for FastAPI and Pydantic resolve and show completions.
5. Make a temporary formatting violation; verify the configured Ruff formatter fixes it.
6. Make a temporary wrong return type in `health`; verify the IDE checker flags it.
   Use Pylance in VS Code, BasedPyright in VSCodium/LazyVim, native checks in PyCharm.
7. Discover/run `tests/test_app.py` with pytest.
8. Debug `scripts/hello.py` with a breakpoint on the print statement and inspect sys.executable.
9. Debug `app.main:app` using uvicorn as the Python module, without auto-reload initially.
10. Run `uv run --locked pre-commit run --all-files` and enter/leave the directory
    in a fresh zsh session after `direnv allow` to check activation/unloading.

PyCharm native debugging does not require debugpy. LazyVim needs a Python DAP
adapter/test plugin if graphical debug/test integration is desired. Setup does not
install plugins or certify GUI behavior. No IDE-specific files are written here.
''')
# Verify actual toolchain; formatting runs before check-only hooks.
run("uv", "run", "--locked", "ruff", "check", "--fix", ".")
run("uv", "run", "--locked", "ruff", "format", ".")
run("uv", "run", "--locked", "basedpyright")
run("uv", "run", "--locked", "pytest")
run("uv", "run", "--locked", "python", "scripts/hello.py")
run("uv", "run", "--locked", "python", "-c", "import debugpy,fastapi,pydantic; print('Debug/import smoke test OK')")
# Use local git init only: no remote, commit, credentials or global hooks directory.
run("git", "init")
# An inherited hooksPath can otherwise install into an unrelated global directory.
probe = subprocess.run(["git", "config", "--get", "core.hooksPath"], cwd=project,
                       text=True, capture_output=True)
if probe.returncode == 0 and probe.stdout.strip():
    run("git", "config", "--local", "core.hooksPath", ".git/hooks")
run("uv", "run", "--locked", "pre-commit", "install")
# --all-files operates on tracked files. Stage non-secret starter files, no commit.
run("git", "add", ".")
run("uv", "run", "--locked", "pre-commit", "run", "--all-files")
print(f"Created and CLI-validated {project}. Files staged, no commit made.")
print("Review .envrc, then run direnv allow yourself. Complete the IDE acceptance checklist.")