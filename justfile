# Project task runner. Run `just --list` for available recipes.

# List available automation recipes.
default:
    @just --list --unsorted

# Run Python lint checks.
lint:
    @uv run ruff check

# Run Python type checks.
typecheck:
    @uv run mypy scripts/

# Verify Python formatting without changing files.
format-check:
    @uv run ruff format --check

# Apply safe automated Python lint and formatting fixes.
fix:
    @uv run ruff check --select I --fix
    @uv run ruff format

# Run full Python test suite.
test:
    @uv run pytest

# Run the isolated host-platform lifecycle test.
integration:
    @uv run pytest tests/test_cross_platform_lifecycle.py

# Enforce the Python coverage floor.
coverage:
    @uv run pytest --cov=scripts --cov-report=term --cov-fail-under=65

# Parse or smoke-check tracked structured configuration.
formats:
    @uv run python scripts/validation/validate_tracked_formats.py

# Run cross-platform checks.
check: lint format-check typecheck formats test
    @echo Cross-platform checks passed.

# Run Unix shell syntax and smoke tests. Requires Bash.
[unix]
unix:
    @bash tests/test_shell.sh

# Run PowerShell smoke tests.
[windows]
test-ps1:
    @pwsh -NoProfile -File tests/test_powershell.ps1

# Parse all active PowerShell scripts for syntax errors.
[windows]
parse-ps1:
    @pwsh -NoProfile -Command 'Get-ChildItem scripts/setup -Recurse -File -Filter *.ps1 | ForEach-Object { $e = $null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e) | Out-Null; if ($e.Count) { $e | ForEach-Object { Write-Error $_.Message }; exit 1 } }; Get-ChildItem home/.config/ooodnakov/bin,tests -File -Filter *.ps1 | ForEach-Object { $e = $null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e) | Out-Null; if ($e.Count) { $e | ForEach-Object { Write-Error $_.Message }; exit 1 } }'

# Run static security analysis and supply-chain policy checks.
security:
    @uv run --with bandit==1.9.4 bandit -q -ll -r scripts/ home/.config/ooodnakov/bin/ home/.config/ooodnakov/bin/herdr-task home/.config/ooodnakov/bin/herdr-artifact
    @uv run pytest tests/test_supply_chain.py

# Regenerate tracked oooconf shell completions and command reference.
completions:
    @uv run python scripts/cli/generate_oooconf_completions.py
    @uv run python scripts/cli/generate_cli_reference.py

# Regenerate dependency lock artifacts.
lock:
    @uv run python scripts/generate/generate_dependency_lock.py

# Build the static GitHub Pages site into _site/.
site:
    @uv run python scripts/site/build_site.py --output _site

# Build and serve the static GitHub Pages site locally.
site-serve:
    @uv run python scripts/site/build_site.py --output _site --serve

# Scan tracked files and full git history for secrets with gitleaks.
secrets:
    @if command -v gitleaks >/dev/null 2>&1; then \
        gitleaks git . --no-banner --redact --log-opts="--all"; \
    else \
        docker run --rm -v "{{justfile_directory()}}:/repo" zricethezav/gitleaks:v8.30.1 \
            git /repo --no-banner --redact --log-opts="--all"; \
    fi
