#!/usr/bin/env python3
"""Automatic changelog + time snap for Video Player. Standard library only.

versionCode is date based: YYMMDD + two digit build number (example 26101151).
Every changelog file is named after the versionCode, so F-Droid matches it to the build.

  python3 scripts/changelog.py                     write both changelog files for version.txt
  python3 scripts/changelog.py --bump              next versionCode (today's date, build number +1), then write
  python3 scripts/changelog.py --new-release       bump AND start a fresh list (BASE moves to HEAD)
  python3 scripts/changelog.py --release-notes F   also write GitHub release notes to F

changelog/BASE holds the last commit already covered by released notes. Everything after it is "new".

Files written (idempotent: the same HEAD always gives the same text, so no commit churn):
  changelog/<versionCode>.txt                                   full list, every change with its own time snap
  fastlane/metadata/android/en-US/changelogs/<versionCode>.txt  short F-Droid text (500 bytes max)

Optional hand written override for the F-Droid text: changelog/highlights.txt (one bullet per line).
"""
import argparse
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FDROID_DIR = os.path.join(ROOT, "fastlane", "metadata", "android", "en-US", "changelogs")
FULL_DIR = os.path.join(ROOT, "changelog")
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


def next_code(code, today=None):
    today = today or datetime.now(timezone.utc)
    prefix = int(today.strftime("%y%m%d"))
    if code // 100 == prefix:
        return code + 1
    return prefix * 100 + 1


def utc(iso):
    return datetime.fromisoformat(iso).astimezone(timezone.utc)


def read_base():
    p = os.path.join(FULL_DIR, "BASE")
    if not os.path.exists(p):
        return None
    h = open(p).read().split()[0]
    try:
        sh("git", "merge-base", "--is-ancestor", h, "HEAD")
    except subprocess.CalledProcessError:
        print(f"note: BASE {h} is not in this history, using the last 60 commits", file=sys.stderr)
        return None
    return h


def write_base(h):
    os.makedirs(FULL_DIR, exist_ok=True)
    subj = sh("git", "log", "-1", "--format=%s", h).strip()
    open(os.path.join(FULL_DIR, "BASE"), "w").write(f"{h}  {subj}\n")


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


def write_full(name, code, head, base, items, total):
    os.makedirs(FULL_DIR, exist_ok=True)
    lines = [
        f"Video Player v{name}  (versionCode {code})",
        f"Time snap : {fmt_time(head['t'])}   (time of the newest commit)",
        f"Commit    : {head['h']}",
        f"Since     : {open(os.path.join(FULL_DIR, 'BASE')).read().strip()}" if base else "Since     : last 60 commits (no changelog/BASE)",
        "-" * 64,
        f"CHANGES, newest first ({len(items)} user facing, {total - len(items)} internal commits left out)",
        "",
    ]
    for it in items:
        lines.append(f"[{fmt_time(it['t'])}] {it['h']}  {it['kind']}: {it['text']}")
    lines.append("")
    path = os.path.join(FULL_DIR, f"{code}.txt")
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    return path


def fdroid_text(name, head, items):
    header = f"v{name} ({head['t']:%Y-%m-%d})"
    hl = os.path.join(FULL_DIR, "highlights.txt")
    bullets = None
    if os.path.exists(hl):
        lines = [l.strip() for l in open(hl, encoding="utf-8") if l.strip()]
        if lines and lines[0].lower() == f"# v{name}".lower():  # only for the version it was written for
            bullets = [l.lstrip("•-* ").strip() for l in lines[1:]]
    if bullets is None:
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
    path = os.path.join(FDROID_DIR, f"{code}.txt")
    open(path, "w", encoding="utf-8").write(text)
    assert len(text.encode("utf-8")) <= FDROID_MAX_BYTES
    return path


def write_release_notes(path, name, code, head, items):
    out = ["# Changelog", "", f"## {name}", ""]
    for title, k in (("New features", "New"), ("Fixes", "Fix"), ("Changed", "Changed")):
        sel = [i for i in items if i["kind"] == k]
        if sel:
            out += [f"{title}:"] + [f"- {i['text']}" for i in sel] + [""]
    out += [f"Time snap: {fmt_time(head['t'])}  |  versionCode {code}  |  commit {head['h']}", ""]
    open(path, "w", encoding="utf-8").write("\n".join(out))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bump", action="store_true", help="set the next date based versionCode first")
    ap.add_argument("--new-release", action="store_true", help="bump the versionCode and start a fresh change list")
    ap.add_argument("--release-notes", metavar="FILE")
    a = ap.parse_args()

    name, code = read_version()
    if a.bump or a.new_release:
        code = next_code(code)
        write_version(name, code)
        print(f"version.txt -> {name}+{code}")
    if a.new_release:
        write_base(sh("git", "rev-parse", "--short", "HEAD").strip())
        print("changelog/BASE -> HEAD (fresh change list)")

    base = read_base()
    rows = commits_since(base)
    if not rows:
        print("no new commits since BASE, nothing to write")
        return
    items = build_items(rows)
    head = rows[0]
    print("wrote", os.path.relpath(write_full(name, code, head, base, items, len(rows)), ROOT))
    text = fdroid_text(name, head, items)
    print("wrote", os.path.relpath(write_fdroid(code, text), ROOT), f"({len(text.encode('utf-8'))} bytes)")
    if a.release_notes:
        write_release_notes(a.release_notes, name, code, head, items)
        print("wrote", a.release_notes)


if __name__ == "__main__":
    main()
