"""Build the release zips in dist/:

  ForeverLoot-<version>.zip                    CurseForge / any platform: only the ForeverLoot
                                               folder at the top level, as CurseForge requires
  ForeverLoot-<version>-Windows-installer.zip  for sharing by hand: the addon folder plus a
                                               double-click installer and a README
"""
import os
import re
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "ForeverLoot")
WIN = os.path.join(ROOT, "packaging", "windows")
DIST = os.path.join(ROOT, "dist")


def crlf(path, **fill):
    text = open(path, encoding="ascii").read()
    for k, v in fill.items():
        text = text.replace("{" + k + "}", v)
    return text.replace("\r\n", "\n").replace("\n", "\r\n").encode("ascii")


def add_addon_folder(z, stamp):
    folder = zipfile.ZipInfo("ForeverLoot/", stamp)
    folder.external_attr = (0o40755 << 16) | 0x10   # directory entry
    z.writestr(folder, b"")
    for name in sorted(os.listdir(ADDON)):
        if name.endswith((".toc", ".lua")):
            z.write(os.path.join(ADDON, name), f"ForeverLoot/{name}")


def main():
    toc = open(os.path.join(ADDON, "ForeverLoot.toc")).read()
    version = re.search(r"^## Version: (\S+)", toc, re.M).group(1)
    date = re.search(r'ns\.DATA_DATE = "([^"]+)"', open(os.path.join(ADDON, "Data.lua")).read()).group(1)
    os.makedirs(DIST, exist_ok=True)
    stamp = time.localtime()[:6]

    curse = os.path.join(DIST, f"ForeverLoot-{version}.zip")
    with zipfile.ZipFile(curse, "w", zipfile.ZIP_DEFLATED) as z:
        add_addon_folder(z, stamp)

    windows = os.path.join(DIST, f"ForeverLoot-{version}-Windows-installer.zip")
    with zipfile.ZipFile(windows, "w", zipfile.ZIP_DEFLATED) as z:
        add_addon_folder(z, stamp)
        z.writestr(zipfile.ZipInfo("Install-ForeverLoot.bat", stamp),
                   crlf(os.path.join(WIN, "Install-ForeverLoot.bat")), zipfile.ZIP_DEFLATED)
        z.writestr(zipfile.ZipInfo("README.txt", stamp),
                   crlf(os.path.join(WIN, "README.txt"), VERSION=version, DATE=date), zipfile.ZIP_DEFLATED)

    print(curse)
    print(windows)


if __name__ == "__main__":
    main()
