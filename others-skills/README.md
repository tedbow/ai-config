# others-skills

Local Claude Code marketplace for skills borrowed from other developers.
Only the marketplace/plugin scaffold is tracked in git — the borrowed skill
folders themselves are gitignored (`plugins/borrowed/skills/*`), since
they're someone else's code, not ours to redistribute through this repo.

## Setup (once per machine)

```
/plugin marketplace add /Users/ted.bowman/projects/ai-config/others-skills
/plugin install borrowed@others-skills
```

## Adding a borrowed skill

1. Copy the skill folder (must contain `SKILL.md`) into
   `plugins/borrowed/skills/<skill-name>/`.
2. `/plugin update borrowed@others-skills`
3. `/reload-plugins`

Plugin install is a pinned copy, not a live symlink — edits to a skill's
`SKILL.md` also need steps 2–3 to take effect, not just a reload.

## Layout

```
others-skills/
  .claude-plugin/marketplace.json   marketplace manifest
  plugins/borrowed/
    plugin.json                     points "skills" at ./skills
    skills/                         gitignored contents, .gitkeep only
```
