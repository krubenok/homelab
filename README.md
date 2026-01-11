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

## CI: TrueNAS app sync
GitHub Actions syncs TrueNAS custom apps on every push to `main`.

### Required GitHub secret
- `OP_SERVICE_ACCOUNT_TOKEN`: 1Password service account token with access to the referenced items.

### 1Password secret references
The workflow declares `op://` references directly in `.github/workflows/truenas-sync.yml`. Update those values to match your vault/item fields.

### Workflow
See `.github/workflows/truenas-sync.yml`. It runs:

```bash
uv sync
uv run scripts/truenas_sync_apps.py
```
