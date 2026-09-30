# Marketplace submission

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
Games
```

**Tags** (max 3)
```
WoW, CurseForge, Addons
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
- [ ] The repository is public and contains installation and removal instructions.
- [ ] I have documented the plugin license and any external dependencies.
- [ ] I confirm that I own or have permission to submit this plugin and its preview assets.
- [ ] The plugin does not overwrite user configuration without explicit consent.
- [ ] I understand that approval is for listing and is not a security review.
