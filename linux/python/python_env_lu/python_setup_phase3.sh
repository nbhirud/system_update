#!/bin/bash
#===============================================================================
# python_setup_phase3.sh - Project Templates and Validation
# Called after Phase 1 and Phase 2 complete
# Purpose: Create universal project template and validate complete workflow
#===============================================================================

set -euo pipefail

TEMPLATE_DIR="${BACKUP_ROOT}/python_setup/project_template"
VALIDATION_PROJECT="${CODE_ROOT}/_validation_test_project"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log "==============================================================================="
log "PYTHON SETUP PHASE 3 - Project Templates and Validation"
log "==============================================================================="

#-------------------------------------------------------------------------------
# CREATE PROJECT TEMPLATE STRUCTURE
#-------------------------------------------------------------------------------

create_project_template() {
    log "=== Creating Universal Project Template ==="
    
    rm -rf "${TEMPLATE_DIR}"
    mkdir -p "${TEMPLATE_DIR}/{src,tests,scripts}"
    
    # Main pyproject.toml with all tool configurations
    cat > "${TEMPLATE_DIR}/pyproject.toml" << 'EOF'
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "{{project_name}}"
version = "0.1.0"
description = "Auto-generated FastAPI project"
readme = "README.md"
requires-python = ">=3.12"
license = {text = "MIT"}
authors = [
    {name = "Your Name", email = "your.email@example.com"}
]
dependencies = [
    "fastapi>=0.115.0",
    "uvicorn[standard]>=0.32.0",
    "pydantic>=2.9.0",
    "sqlalchemy>=2.0.0",
    "aiosqlite>=0.20.0",
    "httpx>=0.27.0",  # For async HTTP client
]

[project.optional-dependencies]
dev = [
    "pytest>=8.3.0",
    "pytest-asyncio>=0.24.0",
    "pytest-cov>=5.0.0",
    "ruff>=0.6.0",
    "basedpyright>=1.17.0",
    "mypy>=1.11.0",
    "pre-commit>=3.8.0",
    "pip-audit>=2.7.0",
]

[tool.ruff]
target-version = "py312"
line-length = 100

[tool.ruff.lint]
select = ["E", "W", "F", "I", "B", "C4", "UP", "ARG", "SIM", "RUF"]
ignore = ["E501", "ANN", "D"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"

[tool.pyright]
typeCheckingMode = "basic"
pythonVersion = "3.12"
reportMissingImports = true
reportUndefinedVariable = true

[tool.mypy]
python_version = "3.12"
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-v --cov=src --cov-report=term-missing"
asyncio_mode = "auto"

[tool.hatch.build.targets.wheel]
packages = ["src/{{project_name}}"]
EOF

    # .envrc for direnv (auto-loads uv environment)
    cat > "${TEMPLATE_DIR}/.envrc" << 'EOF'
# direnv configuration for Python project
# Run: direnv allow

# Use uv to manage Python environment
use uv

# Export environment variables for the project
export APP_ENV="${APP_ENV:-development}"
export DATABASE_URL="${DATABASE_URL:-sqlite:///./test.db}"
EOF

    # Pre-commit configuration
    cat > "${TEMPLATE_DIR}/.pre-commit-config.yaml" << 'EOF'
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.9
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
      - id: ruff-format
      
  - repo: local
    hooks:
      - id: pip-audit
        name: pip-audit
        entry: pip-audit
        language: python
        types: [python]
        require_serial: true
        additional_dependencies: [pip-audit]
        pass_filenames: false
        always_run: true
EOF

    # Source directory structure
    cat > "${TEMPLATE_DIR}/src/__init__.py" << 'EOF'
# {{project_name}} package
EOF

    # Main application file
    cat > "${TEMPLATE_DIR}/src/main.py" << 'EOF'
"""FastAPI Application Entry Point"""
from fastapi import FastAPI
from pydantic import BaseModel
from typing import Optional
import sqlite3
import os

app = FastAPI(
    title="{{project_name}}",
    description="Auto-generated FastAPI project",
    version="0.1.0"
)


class HealthResponse(BaseModel):
    status: str
    version: str
    database_status: str


class MessageResponse(BaseModel):
    message: str
    timestamp: str


class CreateUserRequest(BaseModel):
    username: str
    email: str
    age: Optional[int] = None


@app.get("/", response_model=MessageResponse)
async def root():
    """Root endpoint - returns welcome message"""
    from datetime import datetime
    return MessageResponse(
        message=f"Welcome to {{project_name}}!",
        timestamp=datetime.utcnow().isoformat()
    )


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint with database status"""
    db_status = "connected"
    try:
        db_url = os.getenv("DATABASE_URL", "sqlite:///./test.db")
        conn = sqlite3.connect(db_url.replace("sqlite:///", ""))
        conn.close()
    except Exception as e:
        db_status = f"error: {str(e)}"
    
    return HealthResponse(
        status="healthy",
        version="0.1.0",
        database_status=db_status
    )


@app.post("/users/", response_model=dict)
async def create_user(user: CreateUserRequest):
    """Create a new user - demonstrates Pydantic validation"""
    return {
        "success": True,
        "user_id": 1,  # Mock ID
        "username": user.username,
        "email": user.email,
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

    # Test file
    cat > "${TEMPLATE_DIR}/tests/test_main.py" << 'EOF'
"""Tests for main application endpoints"""
import pytest
from fastapi.testclient import TestClient
from src.main import app

client = TestClient(app)


def test_root_endpoint():
    """Test root endpoint returns correct message"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "message" in data
    assert "timestamp" in data


def test_health_endpoint():
    """Test health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "database_status" in data


def test_create_user():
    """Test user creation with Pydantic validation"""
    test_user = {
        "username": "testuser",
        "email": "test@example.com",
        "age": 25
    }
    response = client.post("/users/", json=test_user)
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["username"] == "testuser"


def test_create_user_missing_field():
    """Test Pydantic validation catches missing fields"""
    invalid_user = {"username": "testuser"}  # Missing email
    response = client.post("/users/", json=invalid_user)
    assert response.status_code == 422  # Validation error
EOF

    # Gitignore
    cat > "${TEMPLATE_DIR}/.gitignore" << 'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
.venv/
venv/
ENV/
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# IDE
.idea/
.vscode/
*.swp
*.swo

# Testing
.pytest_cache/
.coverage
htmlcov/
.tox/

# Security
.secrets
.env
*.pem

# Database
*.db
*.sqlite
*.sqlite3

# Logs
*.log
logs/
EOF

    # README template
    cat > "${TEMPLATE_DIR}/README.md" << 'EOF'
# {{project_name}}

Auto-generated FastAPI project with full development tooling.

## Quick Start

```bash
# Activate environment (direnv auto-loads it)
direnv allow

# Install dependencies
uv sync

# Run tests
uv run pytest

# Start development server
uv run uvicorn src.main:app --reload