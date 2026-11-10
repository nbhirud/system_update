# Phase 2 contract (not implemented here)

Phase 1/3 do not modify IDE settings or install extensions. The later IDE-specific
scripts must back up each tool's actual existing configuration under
~/nb/nbscript_backups/<toolname>/ before modifying it, parse JSONC/XML/Lua safely,
preserve unrelated values, and avoid blanket hostname/firewall/hosts blocks.
Do not overwrite VS Code settings.json with a fresh JSON object.

## Interpreter/tool agreement

- All IDEs select the open repository's .venv/bin/python.
- VS Code: Python/debugger/Ruff/Pylance, native RPM executable.
- VSCodium: Python/debugger/Ruff/BasedPyright, Open VSX-compatible extensions.
  Do not assume Pylance licensing/distribution applies to VSCodium.
- PyCharm from Toolbox: .venv interpreter, pytest, native debugger/type inspections;
  repository Ruff integration where the installed plugin supports it. Toolbox
  paths and PyCharm edition capabilities must be detected rather than assumed.
- LazyVim: project interpreter, basedpyright language server, Ruff formatting/linting;
  Python DAP/pytest integration only if its specific installed plugins support it.
  Avoid Mason auto-installing duplicate servers when using the chosen uv tools.
- Prefer repository-pinned Ruff/checkers over global/bundled extension tools where
  supported. Configure actual extension capabilities/paths, not invented keys.
- Respect existing Black/Flake8/isort and repository checker configs. Avoid two
  simultaneous type-checking language servers giving duplicate diagnostics.
- Notebook extensions/kernels remain opt-in and project-specific.
- Workspaces remain untrusted until reviewed; do not disable Workspace Trust.

## Privacy baseline, without breaking Copilot

Supported VS Code setting: telemetry.telemetryLevel = "off". Microsoft documents
that this disables editor usage/error/crash telemetry and experimentation. It is
not a guarantee that every third-party extension obeys it. Inspect installed
extension manifests/docs for supported individual telemetry controls. Inventory
before/after and verify with Developer: Show Telemetry where appropriate.

Keep Copilot enabled when work requires it, together with authentication, extension
updates, TLS certificate verification, Marketplace and required network endpoints.
No DNS/hosts/firewall blocklists, marketplace replacement or Copilot-disabling flags.
Copilot service requests containing code/context are distinct from editor telemetry;
account/organization data policies must be reviewed separately. No claim of zero
network traffic or complete data confidentiality while using cloud AI assistance.

VSCodium: verify existing build privacy defaults and extension-specific controls.
JetBrains: disable supported usage/data-sharing options in both PyCharm and Toolbox
through their actual version-specific settings; do not invent JVM properties or
hand-edit unknown XML schemas. Inspect plugins separately. Neovim/LazyVim: inventory
plugins and their documented behavior; do not claim one global switch covers all
plugins. Leave updates available; privacy is not achieved by breaking TLS or security.

Shell foundation deliberately exports no speculative DO_NOT_TRACK/NO_TELEMETRY
variable claiming all tools honor it. Apply documented opt-outs only for software
actually installed and within the phase 2 scope. No configuration syncing is added.
