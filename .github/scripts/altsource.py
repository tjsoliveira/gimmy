#!/usr/bin/env python3
"""Writes the SideStore / AltStore source (format version 2) for this build's Gimmy.ipa.

SideStore reads it from https://github.com/<repo>/releases/latest/download/source.json, so the newest
release always carries the newest version. Run by .github/workflows/build.yml.
"""
import argparse
import json
import sys


def source(a):
    raw = f"https://raw.githubusercontent.com/{a.repo}/main"
    version = {
        "version": a.version,
        "buildVersion": a.build,
        "date": a.date,
        "localizedDescription": a.notes or f"Gimmy {a.version}",
        "downloadURL": a.download_url,
        "size": a.size,
        "sha256": a.sha256,
        "minOSVersion": "17.0",
    }
    app = {
        "name": "Gimmy",
        "bundleIdentifier": a.bundle_id,
        "developerName": a.repo.split("/")[0],
        "subtitle": "Registro de treinos",
        "localizedDescription": "Registro de treinos numa planilha do Google. Projeto pessoal.",
        "iconURL": f"{raw}/Gimmy/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        "tintColor": "5E6AD2",
        "screenshotURLs": [f"{raw}/docs/screenshots/{n}.png" for n in ("1-treino", "2-serie", "3-historico", "4-treinos")],
        # Older readers take these from the app itself.
        "version": version["version"],
        "date": version["date"],
        "downloadURL": version["downloadURL"],
        "size": version["size"],
        "versions": [version],
        # Gimmy asks for no special entitlements and no privacy-protected data.
        "appPermissions": {"entitlements": [], "privacy": []},
    }
    return {
        "version": 2,
        "name": "Gimmy",
        "identifier": f"io.github.{a.repo.replace('/', '.').lower()}.source",
        "sourceURL": f"https://github.com/{a.repo}/releases/latest/download/source.json",
        "website": f"https://github.com/{a.repo}",
        "apps": [app],
        "news": [],
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", required=True, help="owner/name")
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--date", required=True, help="ISO 8601, UTC")
    p.add_argument("--download-url", required=True)
    p.add_argument("--size", type=int, required=True)
    p.add_argument("--sha256", required=True)
    p.add_argument("--notes", default="")
    json.dump(source(p.parse_args()), sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
