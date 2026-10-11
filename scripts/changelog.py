#!/usr/bin/env python3
"""Automatic changelog + time snap for Video Player. Standard library only.

versionCode is a plain counter (5, 6, 11, 12 ...): every new build is the previous number + 1.
The F-Droid changelog is named after the versionCode, so F-Droid matches it to the build.
Everything lives under fastlane/ (F-Droid). Nothing is written to the repo root.

  python3 scripts/changelog.py                     make the F-Droid file for version.txt if it is missing
  python3 scripts/changelog.py --regen             rebuild it from the commits since the last release tag
  python3 scripts/changelog.py --bump              next versionCode (previous + 1), then write
  python3 scripts/changelog.py --new-release       same as --bump and rebuild from the commits
  python3 scripts/changelog.py --release-notes F   also write GitHub release notes to F (from the F-Droid file)

File written (idempotent):
  fastlane/metadata/android/en-US/changelogs/<versionCode>.txt   short F-Droid text (500 bytes max)

The F-Droid file IS the hand written changelog: if it already exists for this versionCode it is kept as it is
(and used for the GitHub release notes) unless --regen / --new-release is given.
"""
import argparse
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FDROID_DIR = os.path.join(ROOT, "fastlane", "metadata", "android", "en-US", "changelogs")
FDROID_MAX_BYTES = 500
ICT = timezone(timedelta(hours=7))

# Commits that are not something a user would notice.
NOISE = re.compile(
    r"^(Merge |Revert|Undo |Delete |Rename |Add files via upload|i looked |changelog:|Changelog|"
    r"Sync |CI|Dev Test|Analyzer|analyzer|Fix typos|Fix my ai|Remove (broken|unused|dead)|"
    r"Update (README|LICENSE|pubspec|analysis_options|build-apk|\S+\.(ya?ml|txt|md|lock))|"
    r"Add (GPL|license|Fastlane|short description|full description|changelog)|Single-source|"
    r"Set Android versionName|Update version|Cleanup|Publish tested|Remove (code comments|unused)|Restore |"
    r"Fix (DeveloperLog|Kotlin build)|Version[: ]|licenses_page|F-Droid changelog|Move app signing|sign-apk|Dev repo|"
    r"Add hidden)"
    r"|\[skip ci\]|build-apk|workflow|Play Core|R8 drop|i did this by mistake|changelog|CI \(",
    re.I,
)


def sh(*args):
    return subprocess.run(args, cwd=ROOT, check=True, capture_output=True, text=True).stdout


def read_version():
    raw = open(os.path.join(ROOT, "version.txt")).read().strip()
    name, code = raw.split("+")
    return name.strip(), int(code)


def write_version(name, code):
    open(os.path.join(ROOT, "version.txt"), "w").write(f"{name}+{code}\n")
    p = os.path.join(ROOT, "pubspec.yaml")
    s = open(p).read()
    semver = ".".join(name.split(".")[:3])  # pubspec wants three parts; the real name lives in version.txt
    s = re.sub(r"(?m)^version: .*$", f"version: {semver}+{code}", s, count=1)
    open(p, "w").write(s)


def next_code(code):
    return code + 1


def utc(iso):
    return datetime.fromisoformat(iso).astimezone(timezone.utc)


def read_base():
    """Newest release tag (v*) in this history; everything after it is new. None = no tag yet."""
    try:
        return sh("git", "describe", "--tags", "--abbrev=0", "--match", "v*", "HEAD").strip() or None
    except subprocess.CalledProcessError:
        print("note: no release tag in this history, using the last 60 commits", file=sys.stderr)
        return None


def commits_since(base):
    rng = f"{base}..HEAD" if base else "HEAD"
    out = sh("git", "log", "--no-merges", "--format=%h%x1f%aI%x1f%an%x1f%s", rng)
    rows = []
    for line in out.splitlines():
        h, iso, an, subj = line.split("\x1f", 3)
        rows.append({"h": h, "t": utc(iso), "an": an, "subj": subj})
    if base:
        # The dev and public histories run side by side, so BASE..HEAD also pulls in older copies of
        # commits that were already released. Keep only commits made after BASE itself.
        cut = utc(sh("git", "log", "-1", "--format=%aI", base).strip())
        rows = [r for r in rows if r["t"] > cut]
    return rows if base else rows[:60]


def tidy(subj):
    s = subj.strip()
    s = re.sub(r"\[skip ci\]", "", s, flags=re.I)
    s = re.sub(r"^\d+(\.\d+){2,3}:\s*", "", s)            # leading "1.0.2.4: "
    s = re.sub(r"[;,]?\s*v\d+(\.\d+)+(\+\d+)?\s*$", "", s)  # trailing "; v1.0.3.4"
    s = re.split(r"\s+\(|;\s", s, maxsplit=1)[0]          # keep the first clause
    s = s.strip(" .;:-")
    if len(s) > 90:
        s = s[:90].rsplit(" ", 1)[0].rstrip(",;: ") + "..."
    return s[:1].upper() + s[1:] if s else s


def kind(text):
    low = text.lower()
    if re.search(r"\bfix(es|ed)?\b|\bbug\b|crash|no longer|stuck|flicker", low):
        return "Fix"
    if re.search(r"^(add|added|new|live caption)\b|\bsupport\b", low):
        return "New"
    return "Changed"


def build_items(rows):
    items, seen = [], set()
    for r in rows:
        if NOISE.search(r["subj"]):
            continue
        text = tidy(r["subj"])
        if not text or text.lower() in seen:
            continue
        seen.add(text.lower())
        items.append({**r, "text": text, "kind": kind(text)})
    return items


def fmt_time(t):
    return f"{t:%Y-%m-%d %H:%M} UTC | {t.astimezone(ICT):%H:%M} ICT"


def fdroid_path(code):
    return os.path.join(FDROID_DIR, f"{code}.txt")


def read_fdroid(code):
    """(header, bullets) of the existing F-Droid changelog for this versionCode, or None."""
    p = fdroid_path(code)
    if not os.path.exists(p):
        return None
    lines = [l.strip() for l in open(p, encoding="utf-8") if l.strip()]
    if not lines:
        return None
    return lines[0], [l.lstrip("•-* \t").strip() for l in lines[1:]]


def fdroid_text(name, head, items):
    header = f"v{name} ({head['t']:%Y-%m-%d})"
    order = {"New": 0, "Fix": 1, "Changed": 2}
    bullets = [i["text"] for i in sorted(items, key=lambda i: order[i["kind"]]) if not i["text"].endswith("...")]
    out = header
    for b in bullets:
        line = f"\n• {b}"
        if len((out + line + "\n").encode("utf-8")) > FDROID_MAX_BYTES:
            continue
        out += line
    return out + "\n"


def write_fdroid(code, text):
    os.makedirs(FDROID_DIR, exist_ok=True)
    path = fdroid_path(code)
    open(path, "w", encoding="utf-8").write(text)
    assert len(text.encode("utf-8")) <= FDROID_MAX_BYTES
    return path


def write_release_notes(path, name, code, head, bullets):
    out = ["# Changelog", "", f"## {name}", ""] + [f"- {b}" for b in bullets] + [""]
    out += [f"Time snap: {fmt_time(head['t'])}  |  versionCode {code}  |  commit {head['h']}", ""]
    open(path, "w", encoding="utf-8").write("\n".join(out))


def newest_commit():
    h, iso = sh("git", "log", "-1", "--format=%h%x1f%aI").strip().split("\x1f")
    return {"h": h, "t": utc(iso)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bump", action="store_true", help="set the next versionCode (previous + 1) first")
    ap.add_argument("--new-release", action="store_true", help="bump the versionCode and rebuild the text from the commits")
    ap.add_argument("--regen", action="store_true", help="rebuild the F-Droid text from the commits even if it exists")
    ap.add_argument("--release-notes", metavar="FILE")
    a = ap.parse_args()

    name, code = read_version()
    if a.bump or a.new_release:
        code = next_code(code)
        write_version(name, code)
        print(f"version.txt -> {name}+{code}")

    existing = read_fdroid(code)
    if existing is None or a.regen or a.new_release:
        rows = commits_since(read_base())
        if not rows:
            print("no new commits since the last release tag, nothing to write")
        else:
            text = fdroid_text(name, rows[0], build_items(rows))
            print("wrote", os.path.relpath(write_fdroid(code, text), ROOT), f"({len(text.encode('utf-8'))} bytes)")
        existing = read_fdroid(code)
    else:
        print("kept", os.path.relpath(fdroid_path(code), ROOT), "(already written for this versionCode)")

    if a.release_notes:
        if existing is None:
            sys.exit("no F-Droid changelog for this versionCode, cannot write release notes")
        write_release_notes(a.release_notes, name, code, newest_commit(), existing[1])
        print("wrote", a.release_notes)


if __name__ == "__main__":
    main()
