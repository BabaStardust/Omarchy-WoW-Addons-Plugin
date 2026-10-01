# Marketplace submission

## Republish 1.1.1

Existing submission: https://github.com/omacom/omarchy-plugin-marketplace/issues/9401

The latest reviewer reassessment withdrew the previous key-file concern and
reported no concrete security blocker in the reviewed scope. Version 1.1.1
nevertheless hardens key storage with exclusive private temporary files,
descriptor mode enforcement and atomic replacement; see CHANGELOG.md.

Before approval, the marketplace's structural/Quattro and automated security
reports must be rerun on the exact updated repository HEAD. Editing the
existing submission issue requests a retry; posting a comment alone does not.
The reviewer also reported a marketplace capacity blocker, which this plugin
update cannot resolve. Do not describe this release as approved or listed until
the marketplace confirms it.

Local checks: `omarchy plugin validate .` and
`python3 -B -m unittest discover -s tests -v`.

## Submission answers

Pre-filled answers for the submission issue at
https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml

Only file this after a fresh `omarchy plugin add <repo-url> --enable` on a real
machine worked end to end (key setup, search, install, remove).

**Repository URL**
```
https://github.com/BabaStardust/Omarchy-WoW-Addons-Plugin
```

**Category**
```
Widgets
```

**Tags** (max 3)
```
Games, Bar
```

**Maintainer notes**
```
Bar widget that manages World of Warcraft addons from CurseForge (search,
install, update, remove; default game version WoW: Forever).

Needs a free personal CurseForge API key. The panel asks for it on first run
with a built-in "?" guide; the key is verified against api.curseforge.com,
stored in ~/.config/io.github.babastardust.wow-addons/curseforge-key (mode 600) and never
shown again. An AGENTS.md lets a coding agent walk users through getting it.

Network: api.curseforge.com and CurseForge's download CDN only. Writes only to
the user's WoW AddOns folder (on click), ~/.config/io.github.babastardust.wow-addons and
~/.local/state/io.github.babastardust.wow-addons. Downloads are checksum-verified, ZIP paths
are validated, and authors who disable third-party downloads are respected
(manual download + import). No sudo, no install hooks, no bundled key.

MIT licensed.
```

**Submission checklist**
- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
