"""Writes data/version.json: version 0.<session> from the git branch (session-NNN), and the
time now. Run at the end of a session, and before sending a build to playtesters, so
everyone is looking at the same copy (shown on the title screen).

    python tools/stamp_version.py [session]
"""
import datetime
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
if len(sys.argv) > 1:
    session = int(sys.argv[1])
else:
    branch = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=root,
                            capture_output=True, text=True).stdout.strip()
    old = json.loads((root / "data/version.json").read_text(encoding="utf-8"))
    session = int(branch.split("-")[1]) if branch.startswith("session-") else int(old["session"])
stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
out = {"session": session, "version": "0.%d" % session, "stamp": stamp,
       "_note": "Written by tools/stamp_version.py; shown on the title screen."}
(root / "data/version.json").write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8", newline="\n")
print(out["version"], stamp)
