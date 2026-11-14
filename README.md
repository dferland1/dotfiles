# dotfiles

```
stow --no-folding .
```

## Shared agent skills

`issue-plan` investigates the issue referenced by the current branch and returns
a short fix plan without changing code or the tracker. It detects the tracker
from project evidence and uses existing authenticated integrations.

The source is `.agents/skills/issue-plan/SKILL.md`. Pi discovers it through
`~/.agents/skills/`; `.claude/skills/issue-plan` links to the same skill for
Claude Code. The `stow` command above installs both globally.

- Pi: `/skill:issue-plan`
- Claude Code: `/issue-plan`

Restart Pi after installation. In Claude Code, run `/reload-skills` if the
personal skills directory was created during the session.

## Pi adversarial review

Run `/review` to review staged, unstaged, and untracked changes, or `/review main`
to include branch changes since the merge base with a local base ref. No fetch is
performed. Run checks yourself before reviewing: the reviewer cannot execute tests.

Choose a reviewer from your scoped models (or all available authenticated models
when no scope is configured). The last selection appears first and is saved in
`~/.pi/agent/review-model.json`, which is ignored by Git. Your coding model stays
unchanged. Reviews use medium reasoning, a fresh context, repository instructions,
and only read/search tools. Extensions, MCP, skills, and prompt templates are disabled
in the review process; models supplied solely by extensions are therefore unsupported.
No implementation conversation is sent. Findings appear in the current conversation
without starting an automatic fix. Escape cancels; reviews stop after ten minutes.
The tool allowlist prevents code execution and edits, but is not a filesystem sandbox.
Avoid changing files during a review: the diff is captured once, while file reads are live.

The source is `.pi/agent/extensions/review.ts`. Install with `stow --no-folding .`,
then run `/reload` in Pi. Tests: `bun test ./.pi/agent/tests/review.test.ts`.

## Prerequisites

Most config is managed via [mise](https://mise.jdx.dev) (`mise install`), but a
few things aren't installable that way:

- **Fonts**: install `Monaspace Argon NF` (ghostty) and a Nerd Font for the
  icon glyphs used by eza/starship/lualine.
- **Linux clipboard**: nvim uses `clipboard = unnamedplus`. For system-clipboard
  yank/paste you need a provider - `wl-clipboard` (Wayland) or `xclip`/`xsel`
  (X11). Built in on macOS, so nothing to install there.
