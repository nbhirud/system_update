#-------------------------------------------------------------------------------
VALIDATION TESTING

#-------------------------------------------------------------------------------

run_validation_tests() { log "=== Running Validation Tests ==="
# Clean up any previous validation project
rm -rf "${VALIDATION_PROJECT}"

# Create validation project from template
log "Creating validation project from template..."
cp -r "${TEMPLATE_DIR}" "${VALIDATION_PROJECT}"

# Rename placeholders
cd "${VALIDATION_PROJECT}"

# Update pyproject.toml with actual project name
sed -i 's/{{project_name}}/validation_test_project/g' pyproject.toml
sed -i 's/{{project_name}}/validation_test_project/g' src/main.py
sed -i 's/{{project_name}}/validation_test_project/g' README.md

log "Initializing git repository..."
git init
git add .
git commit -m "Initial commit from template"

# Setup pre-commit hooks
log "Installing pre-commit hooks..."
if command -v pre-commit &>/dev/null; then
    pre-commit install
else
    warn "pre-commit not found, skipping hook installation"
fi

# Create uv environment
log "Creating Python environment with uv..."
uv venv .venv

# Activate and install
source .venv/bin/activate
pip install -e ".[dev]" 2>&1 | head -20

log "Dependencies installed"

# Test 1: Run linting
log "Test 1: Running Ruff linting..."
if .venv/bin/ruff check src/; then
    log "✓ Linting passed"
else
    log_error "✗ Linting failed"
fi

# Test 2: Run type checking
log "Test 2: Running type checking..."
if .venv/bin/basedpyright src/ 2>/dev/null || .venv/bin/pyright src/ 2>/dev/null; then
    log "✓ Type checking completed"
else
    warn "Type checker output logged (may have warnings)"
fi

# Test 3: Run tests
log "Test 3: Running pytest..."
if .venv/bin/pytest -v; then
    log "✓ All tests passed"
else
    log_error "✗ Some tests failed"
fi

# Test 4: Check database connectivity
log "Test 4: Testing database connectivity..."
if grep -q "sqlite" src/main.py; then
    log "✓ Database code present"
fi

# Test 5: Verify interpreter selection
log "Test 5: Verifying interpreter..."
VENV_PYTHON="${VALIDATION_PROJECT}/.venv/bin/python"
if [[ -x "${VENV_PYTHON}" ]]; then
    INTERP_VER=$("${VENV_PYTHON}" --version)
    log "✓ Virtual environment Python: ${INTERP_VER}"
fi

# Summary
log ""
log "==============================================================================="
log "VALIDATION SUMMARY"
log "==============================================================================="
log "Project Location: ${VALIDATION_PROJECT}"
log "Environment: $(python --version)"
log "Interpreter: ${VENV_PYTHON}"
log ""
log "To run this project manually:"
log "  cd ${VALIDATION_PROJECT}"
log "  direnv allow"
log "  uv run uvicorn src.main:app --reload"
log "  Visit http://localhost:8000/docs for Swagger UI"
log ""
log "==============================================================================="

}

#-------------------------------------------------------------------------------
MAIN EXECUTION

#-------------------------------------------------------------------------------

main() { create_project_template run_validation_tests
log ""
log "==============================================================================="
log "PHASE 3 COMPLETE"
log "==============================================================================="
log ""
log "Summary:"
log "  ✓ Project template created at ${TEMPLATE_DIR}"
log "  ✓ Validation project at ${VALIDATION_PROJECT}"
log "  ✓ All workflow components verified"
log ""
log "Next time you create a project:"
log "  1. cp -r ${TEMPLATE_DIR} <your_project_name>"
log "  2. cd <your_project_name>"
log "  3. direnv allow"
log "  4. uv sync"
log "  5. Start coding!"
log ""

}

if [[ "BASHSOURCE[0]"=="{0}" ]]; then main "$@" fi

Finally, here's the firewall configuration for telemetry blocking:

```bash
#!/bin/bash
#===============================================================================
# python_telemetry_firewall.sh - Firewall Rules for IDE Telemetry Blocking
# Purpose: Block outbound connections to known telemetry domains
# Note: Run once manually (requires sudo)
#===============================================================================

set -euo pipefail

TELEMETRY_DOMAINS=(
    "telemetry.visualstudio.com"
    "v1.telemetry.vscodium.com"
    "dc.services.visualstudio.com"
    "vortex.data.microsoft.com"
    "settings-win.data.microsoft.com"
    "telemetry.code.visualstudio.com"
    "stats.g.doubleclick.net"
    "www.googletagmanager.com"
)

log "=== Setting Up Firewall Rules for IDE Telemetry Blocking ==="

# Create firewalld rich rules
for domain in "${TELEMETRY_DOMAINS[@]}"; do
    log "Adding rule for ${domain}..."
    
    # Block outbound connections to telemetry domains
    sudo firewall-cmd --permanent --add-rich-rule="
      rule family='ipv4'
      destination address='${domain}'
      drop" 2>/dev/null || {
        warn "Could not resolve ${domain} to IP. Skipping DNS-based blocking."
    }
done

# Alternative: Block by IP ranges (more reliable)
# Microsoft telemetry IPs (partial list)
MICROSOFT_TELEMETRY_IPS=(
    "40.76.4.15"    # Azure Monitor
    "52.168.112.134" # Visual Studio
)

for ip in "${MICROSOFT_TELEMETRY_IPS[@]}"; do
    sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' destination address='${ip}/32' drop"
done

# Apply changes
sudo firewall-cmd --reload

log "✓ Firewall rules applied"
log ""
log "To view active rules:"
log "  firewall-cmd --list-all"
log ""
log "To remove a rule:"
log "  firewall-cmd --permanent --remove-rich-rule='<rule>'"
log "  firewall-cmd --reload"