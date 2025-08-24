# TRACKTOOL

## Quick usage examples

From inside a project (or pass `--project-root`):

```bash
# After saving/exporting in Ableton (WAV lands in ABLETON/Bounces):
tracktool savepoint --als "ABLETON/Sets/CurrentSet.als"

# Stamp Ableton stems you exported to a temp folder:
tracktool stamp-stems-from-live --suffix 1200A --src "/path/to/ableton/stems"

# Stamp PT stems:
tracktool stamp-stems-from-pt --from 1200A --to 1230A --src "/path/to/pt/stems"

# Name the unmastered print:
tracktool unmastered --from 1200A --to 1255A --wav "PRO_TOOLS/Bounced Files/print.wav"

# Create masters and mark FINAL:
tracktool master-version --from 1200A --to 1255A --src "path/to/master.wav" --n 3
tracktool master-final   --from 1200A --to 1255A --n 3
```

---

## Optional: bind a hotkey to export + savepoint

* Use Automator (“Quick Action” → “Run AppleScript”) or Keyboard Maestro/Alfred to execute:

  * `osascript ~/bin/ableton_quick_export.applescript` (optionally pass ALS path + project root)
* This clicks **File → Export Audio/Video… → Return → Return**, then calls `tracktool savepoint` to copy `.als`, normalize your mix into **BOUNCES/WAV** and **BOUNCES/MP3** with proper names.

---

If you want this folded even tighter (e.g., scaffolder auto-drops a **project-local** `bin/` with a preconfigured `tracktool` wrapper pointing at that project’s `.project/project.yml`), say the word and I’ll extend it.

