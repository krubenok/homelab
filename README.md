# homelab
config and other files for my homelab

## Python tooling (uv, ruff, ty)
This repo uses `uv` for Python tooling and script execution, `ruff` for linting/formatting, and `ty` for type checking.

### Install uv
Use the official installer:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Sync dependencies
Install project and dev tooling dependencies:

```bash
uv sync
```

### Run tools
Run tools from the project environment:

```bash
uv run ruff check
uv run ty check
```

### Run scripts
Scripts use project dependencies declared in `pyproject.toml`:

```bash
uv run scripts/truenas_sync_apps.py --help
```

### VS Code
Workspace settings in `.vscode/settings.json` are set up for Ruff. Install the Ruff VS Code extension to get formatting and linting on save.
