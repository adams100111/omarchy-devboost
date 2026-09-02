# Dev Boost for Omarchy

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

### Give it a way to open

**A plugin cannot register a keybinding** — the manifest schema has no such concept, so
installing this does not put a key on your keyboard. Wire up whichever of these you want.

A keybinding, in `~/.config/hypr/bindings.lua`. Every modifier needs its own `+`:

```lua
o.bind("SUPER + CTRL + U", "Dev Boost", "omarchy-shell shell toggle adams100111.devboost '{}'")
```

Check the key is free first with `omarchy menu keybindings --print`, and `hl.unbind(...)`
before rebinding if it is not. Validate with `hyprctl reload && hyprctl configerrors`.
The description (`"Dev Boost"`) is what Omarchy lists under **SUPER + K**, so the binding
shows up alongside the built-in ones.

A row in the Omarchy menu (SUPER + SPACE), in
`~/.config/omarchy/extensions/omarchy-menu.jsonc` — this one is searchable, so you can
just type "dev":

```jsonc
"devboost": {
  "icon": "",
  "label": "Dev Boost",
  "aliases": ["dev", "devboost", "modules", "stacks", "install"],
  "description": "Browse, search and install dev-boost stacks and modules",
  "action": "omarchy-shell shell toggle adams100111.devboost '{}'"
}
```

Or open it directly, with no setup at all:

```bash
omarchy-shell shell toggle adams100111.devboost '{}'
```

### The dev-boost dependency

This plugin is a front end for [dev-boost](https://github.com/adams100111/dev-boost). It
has nothing to show and nothing to do without it, so `devboost` must be on `PATH`.

**`omarchy plugin add` cannot install it for you.** Plugin install only clones, validates
and enables — it never executes anything from the plugin, and the manifest schema has no
install hook (`omarchy plugin validate` even refuses symlinks). That is a security
property, not an oversight: a plugin you add from a URL should not be able to run
arbitrary code on your machine.

So the panel offers it instead. Open it without dev-boost installed and it says so, and
**enter** runs the official installer in a terminal — where you can watch it and answer
for sudo — rather than leaving you at a dead end. Press `^r` afterwards to re-check.

The probe runs through a login shell, so a `devboost` in `~/.local/bin` or a uv tool
directory is found even though the Omarchy shell is started by your session rather than
from a terminal.

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
