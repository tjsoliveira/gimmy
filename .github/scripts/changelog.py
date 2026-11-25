#!/usr/bin/env python3
"""Adds a line to CHANGELOG.md under today's date (São Paulo time).

Newest day on top; within a day, lines stay in the order they were added.
Usage: python3 .github/scripts/changelog.py "O que mudou, em uma frase."
"""
import datetime
import pathlib
import sys
from zoneinfo import ZoneInfo


def add(text: str, entry: str, today: str) -> str:
    head = f"## {today}\n"
    bullet = f"- {entry}\n"
    first = text.find("\n## ")
    if first < 0:
        return text.rstrip("\n") + f"\n\n{head}\n{bullet}"
    start = first + 1
    if text.startswith(head, start):
        nxt = text.find("\n## ", start + len(head))
        end = len(text) if nxt < 0 else nxt + 1
        rest = text[end:]
        section = text[start:end].rstrip("\n") + "\n" + bullet
        return text[:start] + section + ("\n" + rest if rest else "")
    return text[:start] + head + "\n" + bullet + "\n" + text[start:]


def main() -> None:
    entry = " ".join(sys.argv[1:]).strip()
    if not entry:
        sys.exit("uso: changelog.py \"o que mudou\"")
    path = pathlib.Path(__file__).resolve().parents[2] / "CHANGELOG.md"
    today = datetime.datetime.now(ZoneInfo("America/Sao_Paulo")).date().isoformat()
    path.write_text(add(path.read_text(encoding="utf-8"), entry, today), encoding="utf-8")


if __name__ == "__main__":
    main()
