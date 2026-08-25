# Global Agent Instructions

## General

- Inspect the repository and its local instructions before making changes.
- Keep changes focused on the user's request; avoid unrelated refactors.
- Prefer small, targeted edits and preserve existing project conventions.
- Do not add authentication, backend services, or external integrations unless explicitly requested.
- Never commit secrets, generated credentials, or local environment files.

## Validation

- Run the most relevant formatter, type checker, linter, and tests after changes when available.
- Report what was changed and which validation commands were run.
- If validation cannot be completed, explain why rather than claiming it passed.

## Package installation

- Always try to use `mise` as the system's package manager when a tool or package needs to be installed.
- Before installing anything, ask the user to approve the exact installation command that will be run.
- Do not run package-installation commands until the user approves that exact command.

## Files and configuration

- Read files before editing them.
- Treat dotfiles and editor configuration as user-level configuration; change them only when the request calls for it.
- Prefer documented, reversible configuration changes.
