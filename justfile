# The Python project lives in src/dicmerge; its recipes run there.
dir := "src/dicmerge"

# Verify the repo: lint, format check and tests.
default: check

# Lint, format check and tests.
check: lint format-check test

# Ruff lint and mypy types.
lint:
    cd {{dir}} && uv run --locked ruff check src tests
    cd {{dir}} && uv run --locked mypy src/

# Fail if anything needs formatting.
format-check:
    cd {{dir}} && uv run --locked ruff format --check src tests

# Rewrite formatting.
format:
    cd {{dir}} && uv run ruff format src tests

# Run the dicmerge test suite.
test:
    cd {{dir}} && uv run --locked pytest

# Refresh the dicmerge lockfile to the latest allowed versions.
update:
    cd {{dir}} && uv lock --upgrade

# Wheel and sdist into src/dicmerge/dist.
build:
    cd {{dir}} && uv build

# Bump the version from conventional commits and tag it.
release:
    cog bump --auto

# Run dicmerge from source.
run:
    cd {{dir}} && uv run dicmerge

# Create or refresh the dicmerge environment.
init:
    cd {{dir}} && uv sync

# Syntax-check every shell and fish script.
shell:
    bash -n src/*.sh
    fish -n src/*.fish

# Print the changelog for a tag (`just changelog v1.2.3`).
changelog at:
    cog changelog --at {{at}}
