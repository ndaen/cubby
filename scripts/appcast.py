#!/usr/bin/env python3
"""Ajoute une version au flux Sparkle (docs/appcast.xml).

Usage : scripts/appcast.py <version> <chemin-du-zip>

Le fichier est toujours reconstruit depuis le gabarit ci-dessous + la liste des
items : pas de rustine textuelle sur du XML existant. Les anciens items sont
conservés tels quels — leur signature porte sur un artefact déjà publié, on n'y
touche jamais.

Clé de signature : $SPARKLE_PRIVATE_KEY si présent (CI), sinon le trousseau du
mainteneur (poste local).
"""
import os
import re
import subprocess
import sys
from email.utils import formatdate
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPCAST = ROOT / "docs" / "appcast.xml"
REPO = "https://github.com/ndaen/cubby"
FEED = "https://raw.githubusercontent.com/ndaen/cubby/main/docs/appcast.xml"
KEEP = 10

TEMPLATE = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Cubby</title>
    <link>{feed}</link>
    <description>Updates for Cubby</description>
    <language>en</language>
{items}  </channel>
</rss>
"""

ITEM = """    <item>
      <title>{version}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>{repo}/releases/tag/v{version}</sparkle:releaseNotesLink>
      <enclosure url="{repo}/releases/download/v{version}/{zipname}"
                 sparkle:edSignature="{signature}" length="{length}"
                 type="application/octet-stream"/>
    </item>
"""


def sign(zip_path: Path) -> tuple[str, str]:
    tool = next(iter(sorted(ROOT.glob(".build/artifacts/**/bin/sign_update"))), None)
    if tool is None:
        sys.exit("✗ sign_update introuvable — lancer 'swift build' d'abord.")
    key = os.environ.get("SPARKLE_PRIVATE_KEY")
    cmd = [str(tool)] + (["--ed-key-file", "-"] if key else []) + [str(zip_path)]
    # sign_update lit la clé sur stdin comme le ferait `echo "$KEY" |`
    out = subprocess.run(cmd, input=(key.strip() + "\n") if key else None,
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"✗ sign_update a échoué : {out.stderr.strip()}")
    sig = re.search(r'sparkle:edSignature="([^"]+)"', out.stdout)
    length = re.search(r'length="(\d+)"', out.stdout)
    if not (sig and length):
        sys.exit(f"✗ sortie de sign_update inattendue : {out.stdout.strip()}")
    return sig.group(1), length.group(1)


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    version, zip_path = sys.argv[1], Path(sys.argv[2])
    if not zip_path.is_file():
        sys.exit(f"✗ archive introuvable : {zip_path}")

    signature, length = sign(zip_path)
    fresh = ITEM.format(version=version, date=formatdate(localtime=False, usegmt=True),
                        repo=REPO, zipname=zip_path.name,
                        signature=signature, length=length)

    previous = re.findall(r"    <item>.*?</item>\n",
                          APPCAST.read_text() if APPCAST.exists() else "", re.S)
    # une version republiée remplace la précédente au lieu de s'y ajouter
    previous = [i for i in previous
                if f"<sparkle:version>{version}</sparkle:version>" not in i]

    APPCAST.parent.mkdir(parents=True, exist_ok=True)
    APPCAST.write_text(TEMPLATE.format(feed=FEED, items="".join([fresh] + previous[:KEEP - 1])))
    print(f"✅ {APPCAST.relative_to(ROOT)} ← v{version} ({length} octets)")


if __name__ == "__main__":
    main()
