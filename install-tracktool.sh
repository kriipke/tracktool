#!/usr/bin/env bash
set -euo pipefail

# -------- SETTINGS --------
USER_HOME="${HOME}"
BIN_DIR="${USER_HOME}/bin"
TRACKS_DIR="${USER_HOME}/Dropbox/Tracks"
LAUNCH_PLIST="${USER_HOME}/Library/LaunchAgents/com.user.tracks-scaffold.plist"

mkdir -p "${BIN_DIR}"
mkdir -p "${TRACKS_DIR}"

# -------- WRITE SCRIPTS --------
cat > "${BIN_DIR}/tracks_scaffold.py" <<"PYEOF"
#!/usr/bin/env python3
import os, sys, textwrap
from pathlib import Path
import yaml  # pip install --user pyyaml

TRACKS_DIR = Path(os.path.expanduser("~/Dropbox/Tracks"))

STRUCTURE = {
    "ABLETON": ["Sets", "User Library (per project)", "Bounces"],
    "PRO_TOOLS": ["Session Files", "Audio Files", "Bounced Files"],
    "RECORDINGS": ["Vocals", "Instruments", "Takes"],
    "SAMPLES": ["Imported", "Rendered", "One-Shots"],
    "STEMS": ["From_Ableton", "From_ProTools"],
    "MIXES": ["Rough", "Client"],
    "BOUNCES": ["WAV", "MP3"],
    "MASTERS": [],
    "REFERENCES": [],
    "ARTWORK": ["Cover", "Social"],
    "DOCS": ["Notes", "Lyrics", "Tech"],
    "DISTRIBUTION": [],
    "EXPORTS": [],
    "RENDERS": [],
    "COLLAB": [],
    ".project": []  # holds metadata
}

README_TEMPLATE = """# {project_title}

This project was scaffolded automatically.

## Folders (key)
- **ABLETON/** – Ableton Live sets, per-project user library, and raw exports in **ABLETON/Bounces/**
- **PRO_TOOLS/** – PT session files and bounces
- **STEMS/** – **From_Ableton/** and **From_ProTools/** (time-stamped per your scheme)
- **BOUNCES/** – Mix bounces normalized and split into **WAV/** and **MP3/** (320 kbps)
- **MASTERS/** – Numbered masters and FINAL
- **MIXES/** – Rough/Client references
- **REFERENCES/** – Reference tracks
- **ARTWORK/** – Cover & Social assets
- **DOCS/** – Notes, lyrics, tech docs
- **DISTRIBUTION/** – Release deliverables
- **EXPORTS/**, **RENDERS/** – Misc/intermediate exports
- **COLLAB/** – Shared assets

## Naming Workflow
See `tracktool --help` for commands that implement:
- Savepoints: `TRACK_TITLE-HHMMA|P.als/.wav/.mp3`
- Stems (Ableton): `TRACK_TITLE-HHMMA|P-PART.wav`
- Stems (PT): `TRACK_TITLE-HHMMA|P-HHMMA|P-PART.wav`
- Unmastered: `TRACK_TITLE-FROM-TO-[unmastered].wav`
- Masters: `TRACK_TITLE-FROM-TO-<n>.wav` and `...-FINAL.wav`
"""

GITIGNORE_CONTENT = """# Heavy audio/intermediates
PRO_TOOLS/Audio Files/
PRO_TOOLS/Bounced Files/
ABLETON/Bounces/
BOUNCES/WAV/
BOUNCES/MP3/
RENDERS/
EXPORTS/
STEMS/
MASTERS/
MIXES/
# DAW temp/cache
**/.DS_Store
**/Icon?
"""

def titleize_from_dirname(dirname: str) -> str:
    name = dirname.replace("_", " ").strip()
    return " ".join(w.capitalize() if w.islower() else w.title() for w in name.split())

def ensure_dir(path: Path):
    path.mkdir(parents=True, exist_ok=True)

def write_if_missing(path: Path, content: str):
    if not path.exists():
        path.write_text(content, encoding="utf-8")

def scaffold_project(project_dir: Path):
    if not project_dir.is_dir() or project_dir.name.startswith("."):
        return False
    marker = project_dir / ".project" / ".scaffolded"
    project_title = titleize_from_dirname(project_dir.name)

    # Create structure
    for top, subs in STRUCTURE.items():
        top_path = project_dir / top
        ensure_dir(top_path)
        for sub in subs:
            ensure_dir(top_path / sub)

    # README
    write_if_missing(project_dir / "README.md", README_TEMPLATE.format(project_title=project_title))

    # .gitignore (append if exists)
    gi = project_dir / ".gitignore"
    if not gi.exists():
        gi.write_text(GITIGNORE_CONTENT, encoding="utf-8")
    else:
        # Ensure core entries present
        cur = gi.read_text(encoding="utf-8")
        add = []
        for line in GITIGNORE_CONTENT.splitlines():
            if line and line not in cur:
                add.append(line)
        if add:
            gi.write_text(cur.rstrip() + "\n" + "\n".join(add) + "\n", encoding="utf-8")

    # Metadata
    meta_dir = project_dir / ".project"
    ensure_dir(meta_dir)
    project_yaml = {
        "name": project_title,
        "slug": project_dir.name,
        "created_by": "tracks_scaffold.py",
        "version": 2,
        "paths": {k: str((project_dir / k)) for k in STRUCTURE.keys()},
        "conventions": {
            "time_suffix": "HHMMA|P (e.g., 1200A, 0345P)",
            "savepoint": "<SLUG>-<TIME>.als/.wav/.mp3",
            "stems_live": "<SLUG>-<TIME>-<PART>.wav",
            "stems_pt": "<SLUG>-<TIME_FROM>-<TIME_TO>-<PART>.wav",
            "unmastered": "<SLUG>-<TIME_FROM>-<TIME_TO>-[unmastered].wav",
            "master": "<SLUG>-<TIME_FROM>-<TIME_TO>-<N>.wav",
            "final": "<SLUG>-<TIME_FROM>-<TIME_TO>-FINAL.wav"
        }
    }
    (meta_dir / "project.yml").write_text(yaml.safe_dump(project_yaml, sort_keys=False), encoding="utf-8")

    # Marker (so we can detect "already scaffolded" later)
    if not marker.exists():
        marker.write_text("ok\n", encoding="utf-8")
        return True
    return False

def main():
    base = TRACKS_DIR
    if not base.exists():
        print(f"[tracks-scaffold] Base directory does not exist: {base}", file=sys.stderr)
        sys.exit(0)

    created = 0
    for child in base.iterdir():
        try:
            if scaffold_project(child):
                created += 1
                print(f"[tracks-scaffold] Scaffolded: {child}")
        except Exception as e:
            print(f"[tracks-scaffold] ERROR on {child}: {e}", file=sys.stderr)

    if created == 0:
        print("[tracks-scaffold] No new projects to scaffold (structure/metadata refreshed if needed).")
    else:
        print(f"[tracks-scaffold] Done. Created {created} project(s).")

if __name__ == "__main__":
    main()
PYEOF
chmod +x "${BIN_DIR}/tracks_scaffold.py"

cat > "${BIN_DIR}/tracktool" <<"PYEOF"
#!/usr/bin/env python3
import argparse, os, re, shutil, subprocess, sys
from datetime import datetime
from pathlib import Path

DEFAULT_TRACKS_DIR = Path(os.path.expanduser("~/Dropbox/Tracks"))
FFMPEG = shutil.which("ffmpeg") or "/usr/local/bin/ffmpeg"

ABLETON_SETS = Path("ABLETON/Sets")
ABLETON_BOUNCES = Path("ABLETON/Bounces")
BOUNCES_WAV = Path("BOUNCES/WAV")
BOUNCES_MP3 = Path("BOUNCES/MP3")
STEMS_FROM_LIVE = Path("STEMS/From_Ableton")
STEMS_FROM_PT = Path("STEMS/From_ProTools")
PT_BOUNCED = Path("PRO_TOOLS/Bounced Files")
MASTERS_DIR = Path("MASTERS")

TIME_SUFFIX_RE = re.compile(r"^\d{4}[AP]$")  # e.g. 1200A, 0345P

def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr); sys.exit(1)

def find_project_root(start: Path) -> Path:
    p = start.resolve()
    if p.is_file(): p = p.parent
    while True:
        if (p / "ABLETON").exists(): return p
        if p.parent == p: break
        p = p.parent
    die("Could not locate project root (no ABLETON/ found). Use --project-root.")

def slug_to_title(slug: str) -> str:
    return " ".join(w.capitalize() for w in slug.replace("_", " ").split())

def now_suffix() -> str:
    t = datetime.now()
    hhmm = t.strftime("%I%M")  # 12-hour with leading zero
    ampm = "A" if t.strftime("%p") == "AM" else "P"
    return f"{hhmm}{ampm}"

def ensure_dirs(root: Path, *rels: Path):
    for r in rels: (root / r).mkdir(parents=True, exist_ok=True)

def convert_to_mp3(src_wav: Path, dst_mp3: Path):
    if not FFMPEG or not Path(FFMPEG).exists():
        die("ffmpeg not found—install with Homebrew: brew install ffmpeg")
    dst_mp3.parent.mkdir(parents=True, exist_ok=True)
    cmd = [FFMPEG, "-y", "-i", str(src_wav), "-codec:a", "libmp3lame", "-b:a", "320k", str(dst_mp3)]
    subprocess.run(cmd, check=True)

def copy_if_missing(src: Path, dst: Path):
    dst.parent.mkdir(parents=True, exist_ok=True)
    if not dst.exists(): shutil.copy2(src, dst)

def cmd_savepoint(args):
    als = Path(args.als).resolve()
    if not als.exists(): die(f".als not found: {als}")
    root = Path(args.project_root).resolve() if args.project_root else find_project_root(als)
    slug = root.name.upper()
    suffix = args.suffix or now_suffix()
    if not TIME_SUFFIX_RE.match(suffix): die("Invalid --suffix (HHMMA|P)")
    ensure_dirs(root, ABLETON_SETS, ABLETON_BOUNCES, BOUNCES_WAV, BOUNCES_MP3)
    base = f"{slug}-{suffix}"

    als_dst = root / ABLETON_SETS / f"{base}.als"
    copy_if_missing(als, als_dst)

    wav_path = Path(args.wav).resolve() if args.wav else None
    if not wav_path:
        bdir = root / ABLETON_BOUNCES
        candidates = sorted(bdir.glob("*.wav"), key=lambda p: p.stat().st_mtime, reverse=True)
        if candidates: wav_path = candidates[0]
    if wav_path and wav_path.exists():
        wav_dst = root / BOUNCES_WAV / f"{base}.wav"
        copy_if_missing(wav_path, wav_dst)
        mp3_dst = root / BOUNCES_MP3 / f"{base}.mp3"
        if not mp3_dst.exists(): convert_to_mp3(wav_dst, mp3_dst)
        print(f"[savepoint] .als → {als_dst.name} ; WAV → {wav_dst.name} ; MP3 → {mp3_dst.name}")
    else:
        print("[savepoint] Note: No WAV provided/found; only .als was recorded.")

def cmd_stamp_stems_from_live(args):
    root = Path(args.project_root).resolve() if args.project_root else find_project_root(Path(args.src))
    slug = root.name.upper()
    sfx = args.suffix
    if not TIME_SUFFIX_RE.match(sfx): die("Invalid --suffix (HHMMA|P)")
    ensure_dirs(root, STEMS_FROM_LIVE)
    src = Path(args.src).resolve()
    if not src.is_dir(): die(f"--src not a directory: {src}")

    moved = 0
    for p in src.glob("*.wav"):
        upper = p.stem.upper()
        part = None
        for token in re.split(r"[-_\s]+", upper):
            if token in ("BASS", "DRUMS", "VOCALS", "FX", "SYNTHS", "PERC", "GUITAR", "PIANO"):
                part = token
        part = part or "STEM"
        dst = root / STEMS_FROM_LIVE / f"{slug}-{sfx}-{part}.wav"
        shutil.move(str(p), str(dst)); moved += 1
    print(f"[stems-live] Stamped {moved} stem(s).")

def cmd_stamp_stems_from_pt(args):
    root = Path(args.project_root).resolve() if args.project_root else find_project_root(Path(args.src))
    slug = root.name.upper()
    t_from, t_to = args.from_time, args.to_time
    if not TIME_SUFFIX_RE.match(t_from) or not TIME_SUFFIX_RE.match(t_to):
        die("Invalid --from/--to (HHMMA|P)")
    ensure_dirs(root, STEMS_FROM_PT)
    src = Path(args.src).resolve()
    if not src.is_dir(): die(f"--src not a directory: {src}")

    moved = 0
    for p in src.glob("*.wav"):
        upper = p.stem.upper()
        part = None
        for token in re.split(r"[-_\s]+", upper):
            if token in ("BASS", "DRUMS", "VOCALS", "FX", "SYNTHS", "PERC", "GUITAR", "PIANO"):
                part = token
        part = part or "STEM"
        dst = root / STEMS_FROM_PT / f"{slug}-{t_from}-{t_to}-{part}.wav"
        shutil.move(str(p), str(dst)); moved += 1
    print(f"[stems-pt] Stamped {moved} stem(s).")

def cmd_unmastered(args):
    root = Path(args.project_root).resolve() if args.project_root else find_project_root(Path(args.wav))
    slug = root.name.upper()
    f, t = args.from_time, args.to_time
    if not TIME_SUFFIX_RE.match(f) or not TIME_SUFFIX_RE.match(t): die("Invalid --from/--to (HHMMA|P)")
    wav = Path(args.wav).resolve()
    if not wav.exists(): die(f"WAV not found: {wav}")
    ensure_dirs(root, BOUNCES_WAV)
    dst = root / BOUNCES_WAV / f"{slug}-{f}-{t}-[unmastered].wav"
    shutil.copy2(wav, dst); print(f"[unmastered] → {dst.name}")

def cmd_master_version(args):
    root = Path(args.project_root).resolve() if args.project_root else find_project_root(Path(args.src))
    slug = root.name.upper()
    f, t = args.from_time, args.to_time
    if not TIME_SUFFIX_RE.match(f) or not TIME_SUFFIX_RE.match(t): die("Invalid --from/--to (HHMMA|P)")
    ensure_dirs(root, MASTERS_DIR)
    n = args.number
    src = Path(args.src).resolve()
    if not src.exists(): die(f"Master WAV not found: {src}")
    dst = root / MASTERS_DIR / f"{slug}-{f}-{t}-{n}.wav"
    shutil.copy2(src, dst); print(f"[master] → {dst.name}")

def cmd_master_final(args):
    root = Path(args.project_root).resolve() if args.project_root else find_project_root(Path.cwd())
    slug = root.name.upper()
    f, t, n = args.from_time, args.to_time, args.number
    if not TIME_SUFFIX_RE.match(f) or not TIME_SUFFIX_RE.match(t): die("Invalid --from/--to (HHMMA|P)")
    src = root / MASTERS_DIR / f"{slug}-{f}-{t}-{n}.wav"
    if not src.exists(): die(f"Source master not found: {src.name}")
    dst = root / MASTERS_DIR / f"{slug}-{f}-{t}-FINAL.wav"
    shutil.copy2(src, dst); print(f"[master] FINAL → {dst.name}")

def main():
    ap = argparse.ArgumentParser(prog="tracktool", description="Ableton → Pro Tools → Masters file ops & naming")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("savepoint", help="Record an Ableton savepoint: copy .als, place WAV, make MP3")
    sp.add_argument("--als", required=True, help="Path to the Ableton .als you just saved")
    sp.add_argument("--wav", help="Path to the exported .wav (optional; will auto-pick newest in ABLETON/Bounces)")
    sp.add_argument("--suffix", help="Override time suffix (HHMMA|P), e.g. 1200A")
    sp.add_argument("--project-root", help="Override inferred project root")
    sp.set_defaults(func=cmd_savepoint)

    s1 = sub.add_parser("stamp-stems-from-live", help="Rename Ableton stems to TRACK-<time>-PART.wav")
    s1.add_argument("--suffix", required=True, dest="suffix", help="Ableton time (HHMMA|P)")
    s1.add_argument("--src", required=True, help="Directory of freshly exported stems")
    s1.add_argument("--project-root", help="Override inferred project root")
    s1.set_defaults(func=cmd_stamp_stems_from_live)

    s2 = sub.add_parser("stamp-stems-from-pt", help="Append PT time: TRACK-<from>-<to>-PART.wav")
    s2.add_argument("--from", required=True, dest="from_time", help="Original Ableton time (HHMMA|P)")
    s2.add_argument("--to", required=True, dest="to_time", help="PT bounce time (HHMMA|P)")
    s2.add_argument("--src", required=True, help="Directory of PT stems")
    s2.add_argument("--project-root", help="Override inferred project root")
    s2.set_defaults(func=cmd_stamp_stems_from_pt)

    u = sub.add_parser("unmastered", help="Name the unmastered PT print")
    u.add_argument("--from", required=True, dest="from_time", help="Ableton time (HHMMA|P)")
    u.add_argument("--to", required=True, dest="to_time", help="PT time (HHMMA|P)")
    u.add_argument("--wav", required=True, help="Path to the unmastered print WAV")
    u.add_argument("--project-root", help="Override inferred project root")
    u.set_defaults(func=cmd_unmastered)

    m = sub.add_parser("master-version", help="Create a numbered master")
    m.add_argument("--from", required=True, dest="from_time", help="Ableton time (HHMMA|P)")
    m.add_argument("--to", required=True, dest="to_time", help="PT time (HHMMA|P)")
    m.add_argument("--src", required=True, help="Path to the master WAV")
    m.add_argument("--n", required=True, dest="number", type=int, help="Master index (1,2,3,...)")
    m.add_argument("--project-root", help="Override inferred project root")
    m.set_defaults(func=cmd_master_version)

    mf = sub.add_parser("master-final", help="Duplicate chosen master as FINAL")
    mf.add_argument("--from", required=True, dest="from_time", help="Ableton time (HHMMA|P)")
    mf.add_argument("--to", required=True, dest="to_time", help="PT time (HHMMA|P)")
    mf.add_argument("--n", required=True, dest="number", type=int, help="Chosen master index")
    mf.add_argument("--project-root", help="Override inferred project root")
    mf.set_defaults(func=cmd_master_final)

    args = ap.parse_args(); args.func(args)

if __name__ == "__main__":
    main()
PYEOF
chmod +x "${BIN_DIR}/tracktool"

cat > "${BIN_DIR}/ableton_quick_export.applescript" <<"APPL"

on run argv
    set alsPath to ""
    set projectRoot to ""
    if (count of argv) ≥ 1 then set alsPath to item 1 of argv
    if (count of argv) ≥ 2 then set projectRoot to item 2 of argv

    tell application "System Events"
        tell application process "Live"
            if not (exists menu bar 1) then error "Ableton Live must be running."
            click menu item "Export Audio/Video…" of menu "File" of menu bar 1
            delay 0.2
            key code 36
            delay 0.4
            key code 36
        end tell
    end tell

    delay 1.0
    set sh to "PATH=$PATH:/usr/local/bin:/opt/homebrew/bin; tracktool savepoint"
    if alsPath is not "" then set sh to sh & " --als " & quoted form of alsPath
    if projectRoot is not "" then set sh to sh & " --project-root " & quoted form of projectRoot
    do shell script sh
end run
APPL

# -------- LaunchAgent (watch Tracks dir) --------
cat > "${LAUNCH_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.user.tracks-scaffold</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/env</string>
    <string>python3</string>
    <string>${BIN_DIR}/tracks_scaffold.py</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>${TRACKS_DIR}</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/tmp/tracks-scaffold.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/tracks-scaffold.err.log</string>
</dict>
</plist>
PLIST

# -------- Enable agent --------
launchctl unload "${LAUNCH_PLIST}" 2>/dev/null || true
launchctl load -w "${LAUNCH_PLIST}"

# -------- First pass scaffold --------
python3 "${BIN_DIR}/tracks_scaffold.py" || true

echo
echo "✅ Installed:"
echo "  - ${BIN_DIR}/tracks_scaffold.py"
echo "  - ${BIN_DIR}/tracktool"
echo "  - ${BIN_DIR}/ableton_quick_export.applescript"
echo "  - LaunchAgent watching ${TRACKS_DIR}"
echo
echo "Next steps:"
echo "  • Ensure Python has PyYAML:  python3 -m pip install --user pyyaml"
echo "  • Install ffmpeg for MP3 conversion:  brew install ffmpeg"
echo "  • Try: mkdir -p \"${TRACKS_DIR}/MY_TRACK\" ; sleep 1 ; python3 ${BIN_DIR}/tracks_scaffold.py"
echo "  • See 'tracktool --help' for operations."

