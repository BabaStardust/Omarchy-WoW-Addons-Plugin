# Changelog

## 1.3.0

- Installs and updates run as parallel background jobs (up to 4 downloads at
  once) with a job list in the panel; "Update all" starts every pending update
  at once and nothing blocks the rest of the panel any more.
- Addons whose authors block third-party downloads no longer stop at a manual
  step: the job opens the CurseForge download page (`/download/<fileId>`, which
  starts the download by itself), waits up to 15 min in the background for the
  ZIP in `~/Downloads` and installs it once size and SHA-1 match. A matching
  ZIP that is already there is used without opening the browser. Waiting jobs
  can be cancelled, re-opened, or imported by hand after a timeout.
- Helper: `install`/`update`/`update-all` accept `--browser` and `--wait=S`
  (`update-all` also `--jobs=N`) and report progress as JSON lines on stderr.
  State and AddOns changes are serialized with a file lock so parallel
  helper processes cannot lose each other's writes; JSON files are written
  through unique temp files.

## 1.2.1

- WoW Forever left beta: auto-detect and the Flavor placeholder now prefer the
  live `_forever_` folder over the retired `_classic_beta_` beta folder.
- On a fresh client without `Interface/`, create `Interface/AddOns` below the
  flavor folder instead of failing.
- Header: show the flavor ("forever") in the hero pill instead of the full
  AddOns path, which never elided and covered the title and buttons.
- Manual import: the hint names the addon and version instead of the raw
  CurseForge file name, and import also accepts a zip in ~/Downloads whose
  name contains the addon name and version (some uploads carry odd names
  like "CUsersJaliborcDesktopBagnon-12.1.7.zip").

## 1.2.0

- Add a labelled "Update all (N)" button to the Installed tab, shown while
  updates are pending. The header icon, the new `u` shortcut and the new IPC
  method `updateAll` share the same action.

## 1.1.1

- Save API keys through an exclusively created, unpredictable temporary file
  in the key directory. Enforce mode `0600` on the opened descriptor before
  writing, flush to disk, and atomically replace the destination without
  following an existing destination link. Clean up temporary files on failure.
- Add offline regression tests for permissive files, temporary/destination
  symlinks, failure cleanup and restoration after CurseForge rejects a key.

## 1.1.0

- Initial marketplace submission of the CurseForge addon manager.
