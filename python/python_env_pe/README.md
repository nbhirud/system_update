# Fedora 44 Python development foundation and project starter

For Nik's Fedora KDE workstations. These scripts run locally as the normal user.
Phase 1 and phase 3 only; there is deliberately no phase 2 IDE configuration script.

## Run sequence

```sh
# Keep this bundle in a dedicated setup repository, not inside application repos.
bash python_setup_phase1.sh --audit
# Inspect the inventory. This command performs changes and uses sudo for RPMs:
bash python_setup_phase1.sh --apply
# Start a new zsh terminal before testing activation.
bash python_setup_phase3.sh --create python-workflow-smoke
```

The starter appears under ~/nb/CodeProjects/. An existing name fails rather than
being overwritten. Its generated README has commands and four-IDE acceptance tests.
The script creates a local Git repository and stages starter files, but makes no
commit, remote, push or credentials changes. It never executes direnv allow.

The inventory prints OS/hardware, interpreter/RPM/tool versions, installed uv
interpreters, pipx environments, VS Code/VSCodium extensions, Toolbox markers,
configuration presence and project manifests/venv markers. Scanning is bounded to
depth 6: this is not an exhaustive census. JetBrains product-info locations are
listed rather than assuming a Toolbox layout or launching GUI applications.
Version/extension inventory executes installed CLI binaries; no installations or
configuration edits are made, but those binaries can have their own runtime effects.
No secrets or full configuration contents are printed. If saving a report, review
paths and extension names before sharing it.

## Layout

- python_setup_phase1.sh: inventory-only by default; --apply orchestrates helpers.
- python_setup_inventory.sh: read-only configuration/inventory intent.
- python_setup_uv.sh: official installer only when uv is absent; managed Python.
- python_setup_tools.sh: reusable isolated CLI tools, skips already available commands.
- python_setup_shell.sh: one owned shell fragment and one source line in .zshrc.
- python_setup_phase3.sh: new project entry point.
- lib/create_project.py: stdlib bootstrap helper, repository templates and CLI tests.
- python_project_bootstrap.sh: conservative opt-in helper for existing projects.
- lib/common.sh: Fedora/user checks, backups and file replacement safeguards.
- PHASE2_CONTRACT.md: interpreter/privacy/integration requirements for later scripts.

## Boundaries and choices

Fedora /usr/bin/python3, alternatives, site-packages and system interpreter aliases
are untouched. uv uses its official standalone installer. Already present uv is
reused, not force-migrated, upgraded or uninstalled. The installer is downloaded
with HTTPS and then executed; this is trust in Astral's distribution endpoint,
not an independently verified supply-chain signature. Review it before execution
if required by workplace policy. No curl|sh pipeline is used.

Managed Python installation disables executable links with UV_PYTHON_INSTALL_BIN=0.
It does not install unversioned python/python3 shims. Latest stable is discovered at
run time from the installed uv catalog. An old uv may have an old interpreter
catalog: update uv deliberately with its original installation manager before
creating a new starter if needed. New projects pin the resolved exact Python
version in .python-version; their requires-python declares the compatible minimum.
Existing project interpreter requirements and locks are respected, not upgraded.

No global UV_PYTHON, UV_PROJECT_ENVIRONMENT or only-managed restriction is set.
Existing projects may legitimately require a system interpreter. uv's normal project
.venv default is used. Poetry gets POETRY_VIRTUALENVS_IN_PROJECT=true; existing external
Poetry environments are not silently migrated. pip is protected with
PIP_REQUIRE_VIRTUALENV=true in zsh. For projects that genuinely need pip:

```sh
# Inside the project, after choosing its interpreter:
uv venv --seed --python 3.x .venv  # replace 3.x with the project's actual version
.venv/bin/python -m pip install -r requirements.txt
```

Do not run this over an existing environment casually. Seeding is optional and not
required for uv-managed projects. uv pip does not require a pip executable in .venv.
Requirements installs are additive rather than destructive sync; requirements
without hashes/pins are less reproducible. The helper does not pretend otherwise.

Global ruff, basedpyright, mypy, ty, pre-commit and pip-audit are isolated conveniences.
Existing executable installations, including pipx tools, are reused. BasedPyright
is the default Pyright-family checker, avoiding duplicate Pyright installation;
a project that requires upstream Pyright can add it to that project's dev group.
Poetry remains opt-in: uv tool install poetry. No global pytest or debugpy: those
belong in project environments. A repo's tools may duplicate a global convenience
installation by design; only the locked repo version is authoritative.

The generated starter installs runtime FastAPI/Pydantic/uvicorn and development
Ruff/BasedPyright/mypy/ty/pre-commit/pip-audit/pytest/pytest-cov/debugpy/httpx. Direct
dev versions are resolved then pinned exactly in pyproject.toml; all dependencies
are locked in uv.lock. Re-running creation uses a new name, not an overwrite.
uv is a workstation prerequisite, not itself locked in the project; CI should pin
its own uv version. Keep the generated lockfile in Git. The sample is an application,
not a distributable library; add an explicit build backend/src layout for libraries.

Ruff local pre-commit hooks use uv run --locked, so they respect the repository's
exact versions rather than introducing a second independent hook dependency tree.
pip-audit exports all dependency groups with --locked and --no-emit-project, then
audits exact pins without resolving again. Its temporary export is removed even
on failure. This avoids accidentally auditing just pre-commit's own environment.
Audit requires the vulnerability service/network, discloses package/version queries,
and fails closed on vulnerabilities or service errors. It is not a malware scanner
or a complete supply-chain/security assessment. No vulnerabilities are silently ignored.

Direnv only changes PATH/VIRTUAL_ENV after explicit .envrc approval. The template
never creates an environment, installs packages, reads .env secrets or approves
itself. Automatic activation is a shell feature, not a guarantee that all IDEs
inherit terminal variables. IDEs must explicitly select .venv/bin/python in phase 2.
Do not globally whitelist ~/nb/CodeProjects for direnv. Review .envrc changes in PRs.

Hardware-aware uv build/install concurrency is conservatively bounded by CPU count
and approximately one job per 2 GiB of total RAM, capped at 8. This is a heuristic,
not an adaptive available-memory scheduler or a hard RAM limit. It does not alter
BLAS/NumPy thread counts or force pytest-xdist on projects. It adds no swap or service.

No duckdb/Valkey services, notebook stack, database server, Obsidian configuration,
Super Productivity integration, git identity, remote provider credentials, Docker
or AWS settings are installed/changed. Their Python packages are opt-in per repo.
For private indexes use environment/credential facilities; do not commit index tokens.

## Existing repositories

```sh
bash python_project_bootstrap.sh ~/nb/CodeProjects/existing-uv-project
bash python_project_bootstrap.sh ~/nb/CodeProjects/requirements-project 3.12
```

The version in the second example must match that repository, not this example.
Inspect/trust dependency manifests before installing: builds can execute code.
For uv: locked sync, no migration. For Poetry: use existing Poetry; external envs
require deliberate migration. For requirements: explicit interpreter or existing
.python-version; no guessing arbitrary dev requirement filenames. Plain pyproject
without a lock is refused to avoid choosing the wrong manager. Existing repositories
are not given Ruff settings/hooks by force. Keep Black/Flake8/isort when prescribed:
install their project-pinned versions and use their existing hooks. Do not run
both Black and Ruff formatting on the same files without deliberate policy.

## Validation and recovery

Creation checks imports, script execution, Ruff lint/format, BasedPyright, pytest,
debugpy import and all pre-commit hooks on staged files. It does not start a public
service, make a commit, run a debugger client or certify IDE completion/formatting.
Mypy and ty are available, not mandatory hook gates; opt in per project.

A dependency incompatibility with latest Python, vulnerability finding, unavailable
network service or failed hook stops creation with a nonzero exit status. The partial
project remains for diagnosis. Fix deliberately and rerun its documented commands,
or delete the reviewed partial directory and choose a fresh project name. The
scripts never delete a user's project automatically and do not auto-downgrade Python.
Latest Python can precede wheel support for data-science dependencies: choose an
explicit supported interpreter in a real project's .python-version when necessary.

These are reviewed scaffolding, not executed Fedora acceptance tests. Shell syntax
and Python parsing are checked in the delivery environment. Use the supplied manual
IDE checklist to complete acceptance on each machine after phase 2.

Existing files modified by phase 1 are backed up under
~/nb/nbscript_backups/python-setup/<timestamp-pid>/ with their home-relative paths.
Unchanged files are not repeatedly backed up. Remove the single source line from
.zshrc and the owned ~/.config/python-dev/shell.zsh to undo shell integration, or
restore a reviewed timestamped backup. Installed RPMs, tools/interpreters and generated
projects are not automatically rolled back. This is intentionally safer than guessing
which installed dependencies may now be used by other projects.

## Source notes

- Astral installation/management: https://docs.astral.sh/uv/guides/install-python/
- uv environment variables: https://docs.astral.sh/uv/reference/environment/
- uv pre-commit guidance: https://docs.astral.sh/uv/guides/integration/pre-commit/
- pip-audit: https://pypi.org/project/pip-audit/
- VS Code telemetry: https://code.visualstudio.com/docs/configure/telemetry

The source notes are documentation links, not automatic network requests by setup.
