


#############################################################################
# Intro:

# A dev container lets you define your entire development environment (tools, runtimes, extensions, settings) in code using Docker. When you open a project in VSCodium/VS Code with a dev container, it automatically builds and uses a consistent containerized environment.

# # Benefits for Your Workflow
# Identical setup on any machine (laptop, desktop, CI).
# Perfect isolation for Python (uv + Ruff) and Rust (rust-analyzer + Clippy).
# No more "it works on my machine" issues.
# Great with your multi-forge Git workflow.





#############################################################################
# Create this folder/file structure in your project root:
# .devcontainer/
# ├── devcontainer.json
# ├── Dockerfile          # Optional but recommended for full control
# └── postCreateCommand.sh  # Optional setup script





#############################################################################
# devcontainer.json (Combined Python + Rust)

{
    "name": "Python + Rust Dev Environment",
    "build": {
        "dockerfile": "Dockerfile"
    },
    "features": {
        // Python + uv + Ruff
        "ghcr.io/devcontainers/features/python:1": {
            "version": "3.12"
        },
        "ghcr.io/jsburckhardt/devcontainer-features/uv:1": {},
        "ghcr.io/jsburckhardt/devcontainer-features/ruff:1": {},
        
        // Rust
        "ghcr.io/devcontainers/features/rust:1": {
            "version": "stable",
            "targets": "x86_64-unknown-linux-gnu"
        }
    },
    "customizations": {
        "vscode": {
            "extensions": [
                "ms-python.python",
                "charliermarsh.ruff",
                "rust-lang.rust-analyzer",
                "eamodio.gitlens",
                "mhutchie.git-graph",
                "yzhang.markdown-all-in-one",
                "tamasfe.even-better-toml",
                "timonwong.shellcheck",
                "usernamehw.errorlens"
            ],
            "settings": {
                "python.defaultInterpreterPath": "/usr/local/bin/uv",
                "python.terminal.activateEnvironment": true,
                "[python]": {
                    "editor.defaultFormatter": "charliermarsh.ruff",
                    "editor.formatOnSave": true
                },
                "[rust]": {
                    "editor.defaultFormatter": "rust-lang.rust-analyzer"
                },
                "rust-analyzer.check.command": "clippy",
                "terminal.integrated.defaultProfile.linux": "bash",
                "editor.fontFamily": "'JetBrainsMono Nerd Font', monospace"
            }
        }
    },
    "postCreateCommand": "bash .devcontainer/postCreateCommand.sh",
    "remoteUser": "vscode",
    "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached",
    "workspaceFolder": "/workspace"
}




#############################################################################
# Dockerfile (Base)
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*


#############################################################################
# postCreateCommand.sh (Setup uv + Rust + pre-commit)
#!/bin/bash
set -e

# Make the script executable: chmod +x .devcontainer/postCreateCommand.sh

echo "=== Setting up Python + Rust environment ==="

# uv setup
uv python install 3.12
uv venv
uv pip install --upgrade pip

# Install project dependencies if pyproject.toml exists
if [ -f pyproject.toml ]; then
    uv sync --dev
fi

# Rust setup
rustup component add rustfmt clippy

# pre-commit
if [ -f .pre-commit-config.yaml ]; then
    uv tool install pre-commit
    pre-commit install
fi

echo "=== Dev Container ready! ==="


#############################################################################
# How to Use

# In VSCodium, install the Dev Containers extension (if not already).
# Open your project folder.
# Press Ctrl+Shift+P → Dev Containers: Reopen in Container.
# First build may take a few minutes; subsequent ones are fast.

# Separate Templates Option

# Python-only: Use the official Python template + uv feature.
# Rust-only: Use the official Rust template.
# Combined: Use the one above.

# Would you like me to:

# Provide a pure Python + uv version?
# Provide a pure Rust version?
# Add GitHub Codespaces / GitLab support?
# Include common services (PostgreSQL, Redis, etc.)?

# This integrates perfectly with your existing VSCodium + pre-commit + uv setup.

#############################################################################
# 



#############################################################################
# 



#############################################################################
# 
