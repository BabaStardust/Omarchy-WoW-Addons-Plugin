# Changelog

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
