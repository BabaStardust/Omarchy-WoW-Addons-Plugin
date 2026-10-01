# Changelog

## 1.1.1

- Save API keys through an exclusively created, unpredictable temporary file
  in the key directory. Enforce mode `0600` on the opened descriptor before
  writing, flush to disk, and atomically replace the destination without
  following an existing destination link. Clean up temporary files on failure.
- Add offline regression tests for permissive files, temporary/destination
  symlinks, failure cleanup and restoration after CurseForge rejects a key.

## 1.1.0

- Initial marketplace submission of the CurseForge addon manager.
