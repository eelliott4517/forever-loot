"""Upload a release zip to CurseForge. The release workflow runs this; it also works by hand.

    python3 tools/upload_curseforge.py dist/ForeverLoot-1.6.0.zip dist/notes.md
    python3 tools/upload_curseforge.py --check     test the token and game version, upload nothing

Settings come from the environment. The workflows fill them in from the repository's
Settings > Secrets and variables > Actions:
  CF_API_TOKEN      from the secret CURSEFORGE: a CurseForge API token
  CF_PROJECT_ID     from the variable PROJECTID: the project id ("About Project" on its CurseForge page)
  CF_GAME_VERSIONS  from the variable CF_GAME_VERSIONS, optional: game versions to tag the file with,
                    as CurseForge names or ids, comma separated. By default the TOC's Interface number
                    as a version (16001 -> 1.60.1). If CurseForge doesn't have it, the error lists
                    the versions it does have.
  CF_RELEASE_TYPE   from the variable CF_RELEASE_TYPE, optional: release (default), beta or alpha
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
        # CurseForge's errors can quote the token back; never print it
        detail = e.read().decode("utf-8", "replace")[:500].replace(token, "***")
        if e.code in (401, 403) or "token" in detail.lower():
            raise SystemExit(f"CurseForge rejected the API token ({e.code}). Make a new token and save it "
                             "as the CURSEFORGE secret.")
        raise SystemExit(f"CurseForge said {e.code} for {path}: {detail}")


def interface_version():
    toc = open(os.path.join(ROOT, "ForeverLoot", "ForeverLoot.toc"), encoding="utf-8").read()
    n = re.search(r"^## Interface: (\d+)", toc, re.M).group(1)
    major, minor, patch = int(n[:-4]), int(n[-4:-2]), int(n[-2:])
    return f"{major}.{minor}.{patch}"


def game_versions(token, wanted):
    """The CurseForge game version entries the names (or ids) in `wanted` mean."""
    versions = call("/game/versions", token)
    found = []
    for w in wanted:
        match = [v for v in versions if (w.isdigit() and v["id"] == int(w)) or v["name"] == w]
        if not match:
            near = sorted({v["name"] for v in versions if v["name"].startswith(w.split(".")[0] + ".")})
            raise SystemExit(f"CurseForge has no game version called {w}. Set the CF_GAME_VERSIONS variable "
                             "to one of: " + ", ".join(near[-30:]))
        found.append(match[0])
    return found


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
    token, project = os.environ.get("CF_API_TOKEN"), os.environ.get("CF_PROJECT_ID")
    if not token:
        raise SystemExit("no CurseForge API token: add it as the CURSEFORGE secret")
    if not project:
        raise SystemExit("no CurseForge project id: add it as the PROJECTID variable")
    wanted = [v.strip() for v in (os.environ.get("CF_GAME_VERSIONS") or interface_version()).split(",") if v.strip()]
    versions = game_versions(token, wanted)

    if sys.argv[1] == "--check":
        print("CurseForge accepted the API token.")
        for v in versions:
            print(f"Files will be tagged with game version {v['name']} (id {v['id']}, type {v['gameVersionTypeID']}).")
        print(f"Project id: {project}. Release type: {os.environ.get('CF_RELEASE_TYPE') or 'release'}.")
        return

    zip_path = sys.argv[1]
    notes = open(sys.argv[2], encoding="utf-8").read() if len(sys.argv) > 2 else ""
    version = re.search(r"ForeverLoot-([^/]+)\.zip$", zip_path).group(1)
    metadata = {
        "changelog": notes or f"Forever Loot {version}",
        "changelogType": "markdown",
        "displayName": f"Forever Loot {version}",
        "gameVersions": [v["id"] for v in versions],
        "releaseType": os.environ.get("CF_RELEASE_TYPE") or "release",
    }
    with open(zip_path, "rb") as f:
        body, content_type = multipart({"metadata": json.dumps(metadata)}, {"file": (os.path.basename(zip_path), f.read())})
    result = call(f"/projects/{project}/upload-file", token, body, content_type)
    print(f"uploaded {os.path.basename(zip_path)} to CurseForge project {project} as file {result.get('id')}")


if __name__ == "__main__":
    main()
