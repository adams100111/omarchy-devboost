# Dev-Boost for Omarchy

An [Omarchy](https://omarchy.org/) shell plugin: browse, search and install
[dev-boost](https://github.com/adams100111/dev-boost) stacks and modules without leaving
the desktop.

```
Search stacks and modules…                        19 stacks · 84 modules

  ▸  .NET + Aspire                                                    0/3
     .NET SDK, Aspire CLI and C# language servers
  ▸  Base system                                                     10/18
     compilers, docker, mise and credentials
  ▸  CLI                                                             11/21
     the everyday command-line tools
  ▸  Laravel                                                           1/3
     ddev-based PHP/Laravel stack

type to search   → expand   enter install   tab select   ^u update   ^r reload
```

## Why it is organised this way

By **profile**, not by module — because that is the unit people think in ("set up
Laravel", not "install ddev, then ddev-remote, then laravel-lsp"), and it is the unit
dev-boost installs in, so the grouping and the action agree. Stacks start collapsed
(19 rows instead of 84); expand one to pick individual modules out of it.

Each stack carries a roll-up (`1/3`, `installed`, `provided`) so you can see how much of it
is already on the box before you commit to anything.

## Install

```bash
omarchy plugin add https://github.com/adams100111/omarchy-devboost.git --enable
```

Then bind it to a key in `~/.config/hypr/bindings.lua`, or add a menu row in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"devboost": {
  "icon": "",
  "label": "Dev-Boost",
  "aliases": ["dev", "install", "modules"],
  "action": "omarchy-shell shell summon adams100111.devboost '{}'"
}
```

Requires `devboost` on `PATH`. If it is missing, the panel says so rather than sitting on
a spinner.

## Keys

| Key | Action |
|---|---|
| type | filter stacks and modules |
| `→` / `←` | expand or collapse a stack |
| `enter` | install the highlighted stack or module (or everything selected) |
| `tab` | add to the selection and move on |
| `^u` | update dev-boost's own tooling (`devboost install --update`) |
| `^g` | system update (`omarchy update`) |
| `^l` | verify |
| `^r` | reload the catalogue |
| `esc` | clear the filter, then close |

Click a stack to expand it; double-click any row to install it.

## What the markers mean

| Marker | Meaning |
|---|---|
| `✓` | already installed |
| `·` | available to install |
| `+` | selected for this run |
| `–` | supplied by Omarchy itself — dev-boost deliberately leaves it alone |

That last one matters on Omarchy: the distro already ships herdr, foot, the nerd fonts,
thermald and more, so dev-boost reports them as `provided-by-omarchy` instead of
reinstalling (or downgrading) what the platform owns.

## How it works

The catalogue comes from `devboost list --json --status`, which reports the **plan** for
this host: modules scoped to another OS are absent, and platform-provided ones carry a
skip reason. So the panel only ever offers what is actually installable here.

Installs are not run inside the shell. They need sudo, take minutes, and print things
worth reading, so `enter` hands the work to a terminal via `omarchy-launch-tui` and closes
the panel. A progress bar in a popup would hide a password prompt and give you nowhere to
answer it.

## Licence

MIT
