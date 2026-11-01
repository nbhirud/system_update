#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script Name: python_setup_phase3.sh
# Description: Scaffolds universal project template and configures IDE integrations
# ==============================================================================

TEMPLATE_DIR="$HOME/nb/CodeProjects/_template"
BACKUP_DIR="$HOME/nb/nbscript_backups/python_phase3"
mkdir -p "$TEMPLATE_DIR" "$BACKUP_DIR"

echo "==> [Phase 3] Generating universal project template with full tool configs..."

# 1. Comprehensive pyproject.toml with Ruff, ty, mypy, and pytest configs
cat << 'EOF' > "$TEMPLATE_DIR/pyproject.toml"
[project]
name = "python-project-template"
version = "0.1.0"
description = "Universal Python template configured for FastAPI, Pydantic, ruff, ty, mypy, and pre-commit"
readme = "README.md"
requires-python = ">=3.11"
dependencies = [
    "fastapi>=0.115.0",
    "pydantic>=2.9.0",
    "uvicorn>=0.31.0",
    "duckdb>=1.1.0",
]

[dependency-groups]
dev = [
    "pytest>=8.3.0",
    "pytest-cov>=5.0.0",
    "ruff>=0.6.0",
    "mypy>=1.11.0",
    "ty>=0.1.0",
    "pip-audit>=2.7.0",
]

[tool.ruff]
target-version = "py311"
line-length = 88

[tool.ruff.lint]
select = [
    "E4", # Error: Importations
    "E7", # Error: Statement syntax
    "E8", # Error: Syntax errors
    "E9", # Error: Runtime errors
    "F",  # Pyflakes
    "I",  # Isort (Import sorting)
    "B",  # Flake8-bugbear (Common bugs/gotchas)
    "UP", # Pyupgrade (Modern syntax upgrades)
]
ignore = []

[tool.ruff.lint.isort]
known-first-party = ["src"]

[tool.ty.rules]
# Astral ty type checker configuration
possibly-missing-import = "warn"
unused-ignore-comment = "warn"

[tool.mypy]
python_version = "3.11"
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = false
check_untyped_defs = true

[tool.pytest.ini_options]
minversion = "6.0"
addopts = "-ra -q"
testpaths = ["tests"]
EOF

# 2. .envrc template for direnv (opt-in security model)
cat << 'EOF' > "$TEMPLATE_DIR/.envrc"
# Automatically activate local uv virtual environment if present
if [ -d ".venv" ]; then
    source .venv/bin/activate
elif command -v uv &>/dev/null; then
    echo "==> Creating new uv virtual environment..."
    uv venv --python 3.11
    source .venv/bin/activate
    uv sync --all-extras
fi

export PYTHONPATH="$PWD/src"
EOF

# 3. .pre-commit-config.yaml with Ruff and pip-audit wired in
cat << 'EOF' > "$TEMPLATE_DIR/.pre-commit-config.yaml"
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.0
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/pypa/pip-audit
    rev: v2.7.3
    hooks:
      - id: pip-audit
        args: ["--requirement", "pyproject.toml"]
EOF

# 4. Sample application structure
mkdir -p "$TEMPLATE_DIR/src" "$TEMPLATE_DIR/tests"
cat << 'EOF' > "$TEMPLATE_DIR/src/main.py"
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="Validated App")

class HealthCheck(BaseModel):
    status: str
    version: str

@app.get("/health", response_model=HealthCheck)
def health_check() -> HealthCheck:
    return HealthCheck(status="healthy", version="0.1.0")
EOF

cat << 'EOF' > "$TEMPLATE_DIR/tests/test_main.py"
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
EOF

echo "==> [Phase 3] Template generated at $TEMPLATE_DIR."

# 5. Automated IDE Settings Injection & Telemetry Hardening for VSCode & VSCodium
inject_ide_configs() {
    local ide_name="$1"
    local settings_path="$2"
    local language_server="$3"

    echo "==> Configuring & hardening $ide_name ($settings_path)..."
    mkdir -p "$(dirname "$settings_path")"
    if [ -f "$settings_path" ]; then
        cp "$settings_path" "$BACKUP_DIR/${ide_name}_settings.json.bak.$(date +%Y%m%d_%H%M%S)"
    else
        echo "{}" > "$settings_path"
    fi

    python3 -c '
import json, sys
path, ls = sys.argv[1], sys.argv[2]
try:
    with open(path, "r") as f:
        data = json.load(f)
except Exception:
    data = {}

# Privacy & Telemetry Hardening (Preserving Copilot)
data["telemetry.telemetryLevel"] = "off"
data["telemetry.enableCrashReporter"] = false
data["telemetry.enableTelemetry"] = false
data["extensions.telemetry"] = false

# Python Tool Integrations
data["python.languageServer"] = ls
data["editor.formatOnSave"] = true
data["editor.codeActionsOnSave"] = {
    "source.fixAll.ruff": "explicit",
    "source.organizeImports.ruff": "explicit"
}

python_block = data.setdefault("[python]", {})
python_block["editor.defaultFormatter"] = "charliermarsh.ruff"

with open(path, "w") as f:
    json.dump(data, f, indent=4)
' "$settings_path" "$language_server"
    echo "    -> $ide_name configured successfully."
}

# Inject into VSCode (Work) using Pylance
inject_ide_configs "VSCode" "$HOME/.config/Code/User/settings.json" "Pylance"

# Inject into VSCodium (Personal) using Pyright
inject_ide_configs "VSCodium" "$HOME/.config/VSCodium/User/settings.json" "Pyright"

echo "==> [Phase 3] Complete! Universal template and IDE toolchains are fully integrated."