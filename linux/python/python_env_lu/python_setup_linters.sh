#!/bin/bash
#===============================================================================
# python_setup_linters.sh - Install Linters and Type Checkers
# Called from: python_setup_phase1.sh
# Purpose: Install global CLI tools for linting, formatting, and type checking
#===============================================================================

set -euo pipefail

log "=== Installing Linters and Type Checkers ==="

# These should be installed globally via uv tool for isolation
# but accessible across all projects

declare -A TOOLS=(
    ["ruff"]="ruff"
    ["basedpyright"]="basedpyright"
    ["mypy"]="mypy"
    ["ty"]="ty"
    ["pre-commit"]="pre-commit"
    ["pip-audit"]="pip-audit"
)

for tool in "${!TOOLS[@]}"; do
    if command -v "${TOOLS[${tool}]}" &>/dev/null; then
        VER=$(${TOOLS[${tool}]} --version 2>/dev/null | head -1 || echo "unknown")
        info "${TOOLS[${tool}]} already installed: ${VER}"
    else
        log "Installing ${TOOLS[${tool}]} via uv tool..."
        uv tool install "${TOOLS[${tool}]}" --quiet
        
        if command -v "${TOOLS[${tool}]}" &>/dev/null; then
            log "✓ ${TOOLS[${tool}]} installed"
        else
            warn "Failed to install ${TOOLS[${tool}]} - may need manual installation"
        fi
    fi
done

# Configure global ruff settings (can be overridden per-project)
log "Configuring global ruff settings..."
mkdir -p "${HOME}/.config/ruff"

cat > "${HOME}/.config/ruff/ruff.toml" << 'EOF'
# Global Ruff Configuration
# Per-project pyproject.toml can override these settings

target-version = "py312"

[lint]
# Enable useful rule sets
select = [
    "E",     # pycodestyle errors
    "W",     # pycodestyle warnings
    "F",     # Pyflakes
    "I",     # isort
    "B",     # flake8-bugbear
    "C4",    # flake8-comprehensions
    "UP",    # pyupgrade
    "ARG",   # flake8-unused-arguments
    "PLE",   # pylint errors
    "PLW",   # pylint warnings
    "SIM",   # flake8-simplify
    "RUF",   # Ruff-specific rules
]

# Ignore overly strict rules that may conflict with common patterns
ignore = [
    "E501",  # Line too long (let formatter handle it)
    "ANN",   # Missing type annotations (enforce selectively)
    "D",     # Docstring rules (project-dependent)
]

[lint.per-file-ignores]
# Allow more lenient rules in test files
"tests/**/*.py" = ["S101", "ARG"]
"**/test_*.py" = ["S101", "ARG"]

# Allow print statements in scripts but not libraries
"scripts/**/*.py" = ["T201"]

[format]
# Use Black-compatible formatting
quote-style = "double"
indent-style = "space"
line-ending = "auto"

# Performance tuning based on RAM
[format.preview]
enabled = true
EOF

# Configure pre-commit global settings
log "Configuring pre-commit..."

# Create sample .pre-commit-config.yaml that projects can copy
cat > "${BACKUP_ROOT}/python_setup/pre-commit-template.yaml" << 'EOF'
# Pre-commit Configuration Template
# Copy this to your project root as .pre-commit-config.yaml
# Then run: pre-commit install

repos:
  # Ruff - linting and formatting
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.9  # Pin to stable version
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
      - id: ruff-format
      
  # Type checking (basedpyright)
  - repo: https://github.com/djlint/djlint  # Alternative: pyright pre-commit
    rev: v1.34.0
    hooks:
      - id: pyright
        language: node
        additional_dependencies: []
        
  # Safety checks
  - repo: https://github.com/pycqa/bandit
    rev: 1.7.10
    hooks:
      - id: bandit
        args: [-r, -ll]
        
  # Secrets detection
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.5.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
        
  # pip-audit for dependency vulnerabilities
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

log "✓ Pre-commit template created: ${BACKUP_ROOT}/python_setup/pre-commit-template.yaml"

# Configure pip-audit globally
log "Configuring pip-audit..."
if command -v pip-audit &>/dev/null; then
    # Create default ignore file if vulnerabilities found
    mkdir -p "${HOME}/.config/pip-audit"
    cat > "${HOME}/.config/pip-audit/ignore.yaml" << 'EOF'
# pip-audit vulnerability ignores
# Add specific CVEs here that you've accepted risks for
# Format: cves: [CVE-XXXX-XXXXX, ...]
cves: []
EOF
fi

log "✓ Linters and type checkers setup complete"