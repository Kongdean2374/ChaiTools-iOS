#!/usr/bin/env python3
"""Bump the user-visible version explicitly: python3 scripts/bump-version.py 1.1.1"""
import pathlib
import re
import sys
root = pathlib.Path(__file__).resolve().parents[1]
old = (root / 'VERSION').read_text().strip()
new = sys.argv[1] if len(sys.argv) == 2 else ''
if not re.fullmatch(r'\d+\.\d+\.\d+', new):
    raise SystemExit('Usage: python3 scripts/bump-version.py MAJOR.MINOR.PATCH')
if tuple(map(int, new.split('.'))) <= tuple(map(int, old.split('.'))):
    raise SystemExit('New version must be greater than ' + old)
project = root / 'project.yml'
updated, count = re.subn(r"MARKETING_VERSION: '[^']+'", "MARKETING_VERSION: '" + new + "'", project.read_text())
if count != 1:
    raise SystemExit('Expected exactly one MARKETING_VERSION')
project.write_text(updated)
(root / 'VERSION').write_text(new + '\n')
print(old + ' -> ' + new)
