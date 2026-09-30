# AGENTS.md — guided setup for the WoW Addons plugin

You are helping a user set up this Omarchy plugin. Its only setup hurdle is a
personal, free **CurseForge API key**. Walk the user through it step by step,
one step at a time, and confirm each step before moving on. Speak the user's
language.

## Ground rules

- **Never ask the user to paste the API key into the chat**, and never print,
  log, echo or commit it. The key goes straight into the plugin (panel field
  or the hidden prompt below).
- Do not create the CurseForge account or API key on the user's behalf. Log-in,
  CAPTCHAs, terms of service and any "how will you use this" questions are the
  user's to answer. Navigate and explain; let them click accept/submit.
- Do not write outside this plugin's config/state dirs and the user's WoW
  AddOns folder. No sudo.

## Step 0 — check where things stand

```bash
PLUGIN=~/.config/omarchy/plugins/io.github.babastardust.wow-addons   # or the folder this file is in
$PLUGIN/bin/wowaddons key status     # {"hasKey": true|false, ...}
$PLUGIN/bin/wowaddons config         # resolved AddOns folder, detected WoW roots
```

If `hasKey` is `true`, verify with `wowaddons key check` and skip to Step 4.

## Step 1 — open the CurseForge console

Open <https://console.curseforge.com/> for the user:

- If a browser-automation tool is available (e.g. Claude in Chrome, a
  Playwright/CDP MCP): open the URL in a **new tab** and take a screenshot to
  see the page state. Do the navigation; stop whenever a login, CAPTCHA or
  consent screen appears and ask the user to handle it, then continue.
- Otherwise: `xdg-open https://console.curseforge.com/` and describe what the
  user should see.

## Step 2 — sign in and find the key

1. User signs in (or registers) with a CurseForge account. Wait until they say
   they are in.
2. Navigate to **API keys** in the console menu. If the console asks for
   details (name, use case), tell the user to answer honestly: a personal
   addon manager for their own game folder.
3. Point at the key (long text starting with `$2a$10$`) and ask the user to
   **copy it** with the site's copy button. Do not read it off the screen into
   the chat; if you can see it in a screenshot, do not repeat it.

The console UI changes over time. If labels differ from the above, describe
what you see and find the closest match instead of guessing.

## Step 3 — hand the key to the plugin

Preferred: tell the user to click the gamepad icon in the bar, paste the key
into the **Paste your API key** field, and press Enter. The panel verifies the
key and shows "Key saved and accepted ✓".

If the panel is not an option, use a hidden terminal prompt (the user types or
pastes; nothing is echoed or stored in shell history):

```bash
read -rsp 'CurseForge API key: ' K; echo
printf '%s\n' "$K" | $PLUGIN/bin/wowaddons key set; unset K
```

Expected: `"saved": true, "valid": true`. On `key_rejected` the key was
copied incompletely or is wrong — go back to Step 2. On `bad_key_format` the
paste contained spaces or is too short. The old key is kept when a new one is
rejected.

## Step 4 — point the plugin at WoW

`wowaddons config` shows `resolved.addonsDir`. If it is empty:

- `detectedRoots` empty → ask where WoW is installed (Wine prefix path, e.g.
  `.../drive_c/Program Files (x86)/World of Warcraft`) and set it:
  `wowaddons config set wowRoot "<path>"`.
- `source: "no-flavor"` → list `flavors`, ask which one the user plays, then
  `wowaddons config set flavor <name>`.

Game version defaults to Forever (`gameVersionTypeId 88568`); change with
`wowaddons config set gameVersionTypeId 67408` (Classic) or `517` (Retail).

## Step 5 — smoke test together

```bash
$PLUGIN/bin/wowaddons search Details     # should return results
```

Then ask the user to open the panel, search an addon and click install.
Confirm the folder appears under `resolved.addonsDir`. Done.

## Troubleshooting

- `HTTP 403` right after the key was accepted: CurseForge throttles search.
  Wait a minute; project-ID lookups and the popular list still work.
- Nothing visible in the bar: `omarchy plugin enable io.github.babastardust.wow-addons` and
  `omarchy restart shell`.
- Start over: `wowaddons key clear`.
