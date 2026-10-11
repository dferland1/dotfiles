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

## Prerequisites

Most config is managed via [mise](https://mise.jdx.dev) (`mise install`), but a
few things aren't installable that way:

- **Fonts**: install `Monaspace Argon NF` (ghostty) and a Nerd Font for the
  icon glyphs used by eza/starship/lualine.
- **Linux clipboard**: nvim uses `clipboard = unnamedplus`. For system-clipboard
  yank/paste you need a provider - `wl-clipboard` (Wayland) or `xclip`/`xsel`
  (X11). Built in on macOS, so nothing to install there.
