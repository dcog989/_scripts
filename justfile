# The Python project lives in src/dicmerge; its recipes run there.
dir := "src/dicmerge"

# Verify the repo: lint, format check and tests.
default: check

# Lint, format check and tests.
check: lint format-check test

# Ruff lint and mypy types.
lint:
    cd {{dir}} && uv run ruff check src tests
    cd {{dir}} && uv run mypy src/

# Fail if anything needs formatting.
format-check:
    cd {{dir}} && uv run ruff format --check src tests

# Rewrite formatting.
format:
    cd {{dir}} && uv run ruff format src tests

test:
    cd {{dir}} && uv run pytest

# Refresh the dicmerge lockfile to the latest allowed versions.
update:
    cd {{dir}} && uv lock --upgrade

# Bump the version from conventional commits and tag it.
release:
    cog bump --auto
