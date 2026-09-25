"""Refresh every data source and rebuild the addon in one go.

    python3 tools/refresh.py                  sites -> Data.lua -> tests -> release zips
    python3 tools/refresh.py --skip-wowhead   rebuild from the Wowhead scrape already in tools/raw
    python3 tools/refresh.py --install        also copy the addon into the WoW: Forever beta

Steps
  1. wowtbc.gg loot tables and dungeon quests (fetched directly).
  2. Wowhead pages: zone loot and quests, raid boss pages, new items. Wowhead blocks
     scripted clients, so this step runs in your browser: the script is written to
     tools/scrape_console.js and copied to the clipboard, Wowhead opens, and you paste the
     script into the developer console (F12, or Cmd+Option+J on a Mac) and press Enter.
     It takes about 15 minutes, then downloads forever-loot-wowhead.json. As soon as that
     lands in your Downloads folder the refresh carries on by itself.
     (Or run the script yourself and pass the file with --wowhead PATH.)
  3. build_data.py: item tooltips from Wowhead's tooltip API (cached in tools/cache), Data.lua.
  4. The tests (npm test in tools/), when Node is installed.
  5. package.py: the release zips in dist/.
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
import webbrowser

from dungeons import DUNGEONS
from raids import RAIDS

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RAW = os.path.join(HERE, "raw")
WOWTBC_URL = "https://wowtbc.gg/page-data/warcraftforever/loot-tables/dungeons/{slug}/page-data.json"
WOWHEAD_FILE = os.path.join(RAW, "wowhead.json")
DOWNLOAD_NAME = "forever-loot-wowhead"
NEW_ITEM_IDS = (270000, 300000)   # Forever's own items; scanned in blocks for rare and epic loot
WAIT_MINUTES = 45


def step(title):
    print(f"\n== {title}", flush=True)


def wowtbc_slugs():
    return [slug for d in DUNGEONS for slug in (d.get("tbc") or {})]


def fetch_wowtbc():
    os.makedirs(os.path.join(RAW, "wowtbc"), exist_ok=True)
    for slug in wowtbc_slugs():
        req = urllib.request.Request(WOWTBC_URL.format(slug=slug), headers={"User-Agent": "ForeverLoot-databuilder/1.6"})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read().decode("utf-8"))
        with open(os.path.join(RAW, "wowtbc", f"{slug}.json"), "w") as f:
            json.dump(data, f)
        time.sleep(0.5)
    print(f"{len(wowtbc_slugs())} wowtbc.gg pages")


def wowtbc_quest_names():
    names = set()
    for slug in wowtbc_slugs():
        path = os.path.join(RAW, "wowtbc", f"{slug}.json")
        if not os.path.exists(path):
            continue
        with open(path) as f:
            loot = json.load(f)["result"]["pageContext"].get("loot") or []
        for q in (loot[0].get("quests") or []) if loot else []:
            names.add(q["name"])
    return sorted(names)


def scrape_config():
    forever, classic = [], []
    for d in DUNGEONS:
        for z in d["zones"]:
            forever.append(z)
            if not d.get("new") and z < 10000:   # higher ids are Forever's own zones
                classic.append(z)
    for r in RAIDS:
        for z in r["zones"]:
            forever.append(z)
            if r["status"] != "new":
                classic.append(z)
    bosses = []
    for r in RAIDS:
        if not r["zones"]:
            continue
        for b in r["bosses"]:
            b = dict(name=b) if isinstance(b, str) else b
            bosses.append(dict(env="forever" if r["status"] == "forever" else "classic", zones=r["zones"],
                               names=[b["name"]] + b.get("aliases", []), npc=b.get("npc", []),
                               objects=b.get("objects", [])))
    lo, hi = NEW_ITEM_IDS
    return dict(
        foreverZones=list(dict.fromkeys(forever)),
        classicZones=list(dict.fromkeys(classic)),
        bosses=bosses,
        questNames=wowtbc_quest_names(),
        newItemRanges=[[a, a + 2000, q] for q in (3, 4) for a in range(lo, hi, 2000)],
    )


def write_console_script():
    with open(os.path.join(HERE, "scrape_template.js")) as f:
        template = f.read()
    config = json.dumps(scrape_config(), separators=(",", ":"))
    script = template.replace("/*CONFIG*/ {}", config)
    out = os.path.join(HERE, "scrape_console.js")
    with open(out, "w") as f:
        f.write(script)
    return out, script


def copy_to_clipboard(text):
    for cmd in (["pbcopy"], ["clip"], ["xclip", "-selection", "clipboard"], ["wl-copy"]):
        if shutil.which(cmd[0]):
            try:
                subprocess.run(cmd, input=text.encode("utf-8"), check=True)
                return True
            except (OSError, subprocess.CalledProcessError):
                pass
    return False


def check_scrape(path):
    with open(path) as f:
        data = json.load(f)
    if data.get("version") != 2 or not data.get("pages"):
        raise SystemExit(f"{path} isn't a Forever Loot Wowhead scrape (version 2)")
    zones = [k for k in data["pages"] if k.startswith("forever_zone_")]
    print(f"{len(data['pages'])} Wowhead pages ({len(zones)} Forever zones), {len(data['errors'])} errors, "
          f"scraped {data['scraped']}")
    for key, err in data["errors"][:10]:
        print(f"   {key}: {err}")
    if not zones:
        raise SystemExit("the scrape has no zone pages; Wowhead may have blocked it. Try again later.")
    return data


def newest_download(since):
    folder = os.path.expanduser("~/Downloads")
    found = [p for p in glob.glob(os.path.join(folder, DOWNLOAD_NAME + "*.json")) if os.path.getmtime(p) > since]
    return max(found, key=os.path.getmtime) if found else None


def wowhead_step(args):
    if args.wowhead:
        check_scrape(args.wowhead)
        shutil.copyfile(args.wowhead, WOWHEAD_FILE)
        return
    path, script = write_console_script()
    started = time.time()
    copied = copy_to_clipboard(script)
    print(f"Wrote {os.path.relpath(path, ROOT)}{' and copied it to the clipboard' if copied else ''}.")
    print("1. In the browser tab that opens (any https://www.wowhead.com/forever/ page), open the developer")
    print("   console: F12, or Cmd+Option+J on a Mac.")
    print(f"2. Paste the script{'' if copied else ' (open tools/scrape_console.js and copy all of it)'} and press Enter.")
    print("   Chrome may ask you to type 'allow pasting' first.")
    print("3. Leave the tab open for about 15 minutes. It downloads forever-loot-wowhead.json when done.")
    print(f"Waiting for ~/Downloads/{DOWNLOAD_NAME}.json (Ctrl+C to stop)...", flush=True)
    if not args.no_browser:
        webbrowser.open("https://www.wowhead.com/forever/")
    deadline = started + WAIT_MINUTES * 60
    while time.time() < deadline:
        found = newest_download(started)
        if found:
            time.sleep(2)  # let the browser finish writing it
            check_scrape(found)
            shutil.copyfile(found, WOWHEAD_FILE)
            print(f"Saved {os.path.relpath(WOWHEAD_FILE, ROOT)}")
            return
        time.sleep(5)
    raise SystemExit("no download showed up. Run the refresh again, or pass the file with --wowhead PATH.")


def run(cmd, cwd, env=None):
    print("$ " + " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, check=True, env=env)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--skip-wowtbc", action="store_true", help="use the wowtbc.gg pages already in tools/raw")
    p.add_argument("--skip-wowhead", action="store_true", help="use the Wowhead scrape already in tools/raw")
    p.add_argument("--wowhead", metavar="PATH", help="a forever-loot-wowhead.json you downloaded already")
    p.add_argument("--no-browser", action="store_true", help="don't open Wowhead in the browser")
    p.add_argument("--item-age", type=int, default=14, metavar="DAYS",
                   help="re-check item tooltips older than this many days (default 14)")
    p.add_argument("--script-only", action="store_true", help="just write tools/scrape_console.js")
    p.add_argument("--install", action="store_true", help="copy the addon into the WoW: Forever beta when done")
    args = p.parse_args()

    if args.script_only:
        print(write_console_script()[0])
        return

    step("1/5 wowtbc.gg")
    if args.skip_wowtbc:
        print("skipped")
    else:
        fetch_wowtbc()

    step("2/5 Wowhead")
    if args.skip_wowhead:
        if not os.path.exists(WOWHEAD_FILE):
            raise SystemExit("tools/raw/wowhead.json is missing; run without --skip-wowhead")
        check_scrape(WOWHEAD_FILE)
    else:
        wowhead_step(args)

    step("3/5 Data.lua")
    env = dict(os.environ, FL_DATE=time.strftime("%Y-%m-%d"), FL_ITEM_AGE=str(args.item_age))
    run([sys.executable, "build_data.py"], HERE, env)

    step("4/5 tests")
    if shutil.which("npm"):
        if not os.path.isdir(os.path.join(HERE, "node_modules")):
            run(["npm", "install", "--no-audit", "--no-fund"], HERE)
        run(["npm", "test", "--silent"], HERE)
    else:
        print("skipped: Node isn't installed")

    step("5/5 release zips")
    run([sys.executable, "package.py"], HERE)
    if args.install:
        run(["sh", "install.sh"], HERE)
    print("\nDone. Review the changes with `git diff --stat`, then commit and tag a release (see README).")


if __name__ == "__main__":
    main()
