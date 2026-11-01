#!/usr/bin/env bash
# =============================================================================
# python_setup_phase3.sh
# =============================================================================
# Phase 3 — Project templates + end-to-end validation
#
# Prerequisites:
#   - Phase 1 completed (uv, ruff, pre-commit, basedpyright, direnv, …)
#   - IDEs may or may not be configured (Phase 2 is separate)
#
# What this does:
#   1. Install reusable project templates under this repo
#   2. Create a small FastAPI validation project
#   3. Create a simple script validation project
#   4. Exercise: interpreter selection, imports, ruff, type check, pytest,
#      pre-commit, direnv activation, uv sync
#
# Projects are created under:  $CODE_PROJECTS/python-setup-validation/
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/hardware.sh"

VALIDATION_ROOT="${CODE_PROJECTS}/python-setup-validation"
FASTAPI_DIR="$VALIDATION_ROOT/fastapi-demo"
SCRIPT_DIR_PROJ="$VALIDATION_ROOT/simple-script"

require_phase1() {
  log_step "Verify Phase 1 tools are available"
  local missing=0
  for t in uv ruff pre-commit; do
    if ! have_cmd "$t"; then
      log_error "$t not found — run Phase 1 first"
      missing=1
    else
      log_ok "$t → $(command -v "$t")"
    fi
  done
  (( missing == 0 )) || die "Phase 1 incomplete"
  export PATH="$HOME/.local/bin:$PATH"
}

install_templates() {
  log_step "Project templates are already in $SCRIPT_DIR/templates/"
  ls -la "$SCRIPT_DIR/templates/" | sed 's/^/  /'
}

# ---------------------------------------------------------------------------
# Helper: drop template files into a new project
# ---------------------------------------------------------------------------
seed_project_files() {
  local dest="$1"
  local name="$2"

  mkdir -p "$dest"

  # pyproject.toml
  sed "s/{{PROJECT_NAME}}/$name/g" \
    "$SCRIPT_DIR/templates/pyproject.toml.tmpl" > "$dest/pyproject.toml"

  # .envrc (opt-in)
  cp "$SCRIPT_DIR/templates/envrc.tmpl" "$dest/.envrc"

  # pre-commit
  cp "$SCRIPT_DIR/templates/pre-commit-config.yaml.tmpl" "$dest/.pre-commit-config.yaml"

  # .python-version — prefer latest stable managed by uv
  echo "3.14" > "$dest/.python-version"

  # Basic gitignore
  cat > "$dest/.gitignore" <<'EOF'
.venv/
__pycache__/
*.py[cod]
.mypy_cache/
.ruff_cache/
.pytest_cache/
.coverage
htmlcov/
dist/
build/
*.egg-info/
.env
.direnv/
EOF

  log_ok "Seeded templates into $dest"
}

# ---------------------------------------------------------------------------
# FastAPI validation project
# ---------------------------------------------------------------------------
create_fastapi_demo() {
  log_step "Create FastAPI validation project"

  if [[ -d "$FASTAPI_DIR" ]]; then
    log_warn "Exists: $FASTAPI_DIR — removing for clean validation"
    rm -rf "$FASTAPI_DIR"
  fi

  mkdir -p "$FASTAPI_DIR"
  cd "$FASTAPI_DIR"

  # Use uv init for structure, then overlay our templates
  uv init --name fastapi-demo --package
  # uv init may create its own pyproject; we replace with our richer template
  seed_project_files "$FASTAPI_DIR" "fastapi-demo"

  # Add runtime deps
  uv add fastapi "uvicorn[standard]" pydantic
  uv add --group dev pytest httpx ruff basedpyright mypy

  # Minimal app
  mkdir -p src/fastapi_demo
  cat > src/fastapi_demo/main.py <<'PY'
"""Minimal FastAPI app for environment validation."""

from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="fastapi-demo", version="0.1.0")


class Health(BaseModel):
    status: str


@app.get("/health", response_model=Health)
def health() -> Health:
    return Health(status="ok")


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "python-setup-validation"}
PY

  # Test
  mkdir -p tests
  cat > tests/test_health.py <<'PY'
from fastapi.testclient import TestClient

from fastapi_demo.main import app

client = TestClient(app)


def test_health() -> None:
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
PY

  # Sync + pin
  uv python pin 3.14
  uv sync

  log_ok "FastAPI demo ready at $FASTAPI_DIR"
}

# ---------------------------------------------------------------------------
# Simple script project (requirements.txt style support check)
# ---------------------------------------------------------------------------
create_simple_script() {
  log_step "Create simple script validation project"

  if [[ -d "$SCRIPT_DIR_PROJ" ]]; then
    log_warn "Exists: $SCRIPT_DIR_PROJ — removing for clean validation"
    rm -rf "$SCRIPT_DIR_PROJ"
  fi

  mkdir -p "$SCRIPT_DIR_PROJ"
  seed_project_files "$SCRIPT_DIR_PROJ" "simple-script"
  cd "$SCRIPT_DIR_PROJ"

  # Also demonstrate requirements.txt interop
  cat > requirements.txt <<'EOF'
# Example legacy-style requirements (uv can consume these)
rich>=13.0
EOF

  mkdir -p src
  cat > src/hello.py <<'PY'
"""Simple script for validation."""

from rich.console import Console

console = Console()


def main() -> None:
    console.print("[bold green]Hello from simple-script validation[/]")


if __name__ == "__main__":
    main()
PY

  uv python pin 3.14
  uv venv
  uv pip install -r requirements.txt
  # Also keep pyproject in sync for modern workflow
  uv add rich
  uv add --group dev ruff pytest

  log_ok "Simple script ready at $SCRIPT_DIR_PROJ"
}

# ---------------------------------------------------------------------------
# Run validation suite
# ---------------------------------------------------------------------------
run_validation() {
  log_step "Validation suite"

  # --- FastAPI project ---
  cd "$FASTAPI_DIR"
  log_info "Working in $FASTAPI_DIR"

  log_info "1) Interpreter"
  uv run python -c "import sys; print(sys.version)"

  log_info "2) Imports"
  uv run python -c "import fastapi, pydantic; print('fastapi', fastapi.__version__)"

  log_info "3) Ruff check + format"
  uv run ruff check .
  uv run ruff format --check . || uv run ruff format .

  log_info "4) Type check (basedpyright if available, else skip)"
  if have_cmd basedpyright; then
    uv run basedpyright src/ || log_warn "basedpyright reported issues (non-fatal for demo)"
  else
    log_warn "basedpyright not on PATH"
  fi

  log_info "5) Pytest"
  uv run pytest -q

  log_info "6) pre-commit (install + run once)"
  uv run pre-commit install || true
  uv run pre-commit run --all-files || log_warn "pre-commit had findings (review)"

  # direnv — only if user has allowed it
  if have_cmd direnv; then
    log_info "7) direnv — .envrc present. Run 'direnv allow' inside the project to activate."
  fi

  # --- Simple script ---
  cd "$SCRIPT_DIR_PROJ"
  log_info "Working in $SCRIPT_DIR_PROJ"
  uv run python src/hello.py
  uv run ruff check src/

  log_ok "Validation suite finished"
}

print_summary() {
  cat <<EOF

══════════════════════════════════════════════════════════════════
Phase 3 complete

Validation projects:
  FastAPI : $FASTAPI_DIR
  Script  : $SCRIPT_DIR_PROJ

Manual IDE checks (after Phase 2 configs):
  • Open each project in VSCodium / VSCode / PyCharm / NeoVim
  • Confirm interpreter = .venv/bin/python
  • Run / debug the FastAPI app or hello.py
  • Confirm Ruff + type diagnostics appear

direnv (opt-in):
  cd $FASTAPI_DIR && direnv allow

Useful commands:
  uv run uvicorn fastapi_demo.main:app --reload   # from fastapi-demo
  uv run python src/hello.py                      # from simple-script
  uv run pytest
  uv run ruff check --fix .
  uv run basedpyright src/

Templates live in:
  $SCRIPT_DIR/templates/

EOF
}

main() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  Python development foundation — Phase 3 (templates + test)  ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  ensure_dirs
  detect_hardware
  require_phase1
  install_templates

  create_fastapi_demo
  create_simple_script
  run_validation
  print_summary
}

main "$@"
