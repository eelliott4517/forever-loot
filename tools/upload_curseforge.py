"""Upload a release zip to CurseForge. The release workflow runs this; it also works by hand.

    python3 tools/upload_curseforge.py dist/ForeverLoot-1.6.0.zip dist/notes.md

Settings come from the environment (in GitHub: Settings > Secrets and variables > Actions):
  CF_API_TOKEN      secret: a CurseForge API token (CurseForge > Account > API tokens)
  CF_PROJECT_ID     variable: the project id (shown in "About Project" on its CurseForge page)
  CF_GAME_VERSIONS  variable, optional: game versions to tag the file with, as CurseForge names or
                    ids, comma separated (e.g. "1.15.8"). By default the TOC's Interface number
                    as a version (16001 -> 1.60.1). If CurseForge doesn't have it, the error
                    lists the versions it does have.
  CF_RELEASE_TYPE   variable, optional: release (default), beta or alpha
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid

API = "https://wow.curseforge.com/api"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def call(path, token, body=None, content_type=None):
    headers = {"X-Api-Token": token, "User-Agent": "ForeverLoot-release/1.6"}
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(API + path, data=body, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise SystemExit(f"CurseForge said {e.code} for {path}: {e.read().decode('utf-8', 'replace')[:500]}")


def interface_version():
    toc = open(os.path.join(ROOT, "ForeverLoot", "ForeverLoot.toc"), encoding="utf-8").read()
    n = re.search(r"^## Interface: (\d+)", toc, re.M).group(1)
    major, minor, patch = int(n[:-4]), int(n[-4:-2]), int(n[-2:])
    return f"{major}.{minor}.{patch}"


def game_version_ids(token, wanted):
    versions = call("/game/versions", token)
    ids = []
    for w in wanted:
        if w.isdigit() and any(v["id"] == int(w) for v in versions):
            ids.append(int(w))
            continue
        match = [v for v in versions if v["name"] == w]
        if not match:
            near = sorted({v["name"] for v in versions if v["name"].startswith(w.split(".")[0] + ".")})
            raise SystemExit(f"CurseForge has no game version called {w}. Set CF_GAME_VERSIONS to one of: "
                             + ", ".join(near[-30:]))
        ids.append(match[0]["id"])
    return ids


def multipart(fields, files):
    boundary = uuid.uuid4().hex
    out = []
    for name, value in fields.items():
        out.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode("utf-8"))
    for name, (filename, data) in files.items():
        out.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'
                   f"Content-Type: application/zip\r\n\r\n".encode("utf-8") + data + b"\r\n")
    out.append(f"--{boundary}--\r\n".encode("utf-8"))
    return b"".join(out), f"multipart/form-data; boundary={boundary}"


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    zip_path = sys.argv[1]
    notes = open(sys.argv[2], encoding="utf-8").read() if len(sys.argv) > 2 else ""
    token, project = os.environ.get("CF_API_TOKEN"), os.environ.get("CF_PROJECT_ID")
    if not token or not project:
        raise SystemExit("set CF_API_TOKEN and CF_PROJECT_ID")
    wanted = [v.strip() for v in (os.environ.get("CF_GAME_VERSIONS") or interface_version()).split(",") if v.strip()]
    version = re.search(r"ForeverLoot-([^/]+)\.zip$", zip_path).group(1)
    metadata = {
        "changelog": notes or f"Forever Loot {version}",
        "changelogType": "markdown",
        "displayName": f"Forever Loot {version}",
        "gameVersions": game_version_ids(token, wanted),
        "releaseType": os.environ.get("CF_RELEASE_TYPE") or "release",
    }
    with open(zip_path, "rb") as f:
        body, content_type = multipart({"metadata": json.dumps(metadata)}, {"file": (os.path.basename(zip_path), f.read())})
    result = call(f"/projects/{project}/upload-file", token, body, content_type)
    print(f"uploaded {os.path.basename(zip_path)} to CurseForge project {project} as file {result.get('id')}")


if __name__ == "__main__":
    main()
