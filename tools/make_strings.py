#!/usr/bin/env python3
"""Maakt WijkHub/Resources/Localizable.xcstrings en InfoPlist.xcstrings uit tools/translations.py,
en controleert dat elke tekst uit de Swift-code een vertaling heeft."""
import json, os, re, glob, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from translations import LANGS, T, INFOPLIST  # noqa: E402


def catalog(entries):
    strings = {}
    for key, values in sorted(entries.items()):
        locs = {"en": {"stringUnit": {"state": "translated", "value": values[0]}}} if values[0] != key else {}
        for lang, val in zip(LANGS, values[1]):
            locs[lang] = {"stringUnit": {"state": "translated", "value": val}}
        strings[key] = {"extractionState": "manual", "localizations": locs}
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


for k, v in T.items():
    assert len(v) == len(LANGS), f"{k}: {len(v)} vertalingen"

out = os.path.join(ROOT, "WijkHub", "Resources")
with open(os.path.join(out, "Localizable.xcstrings"), "w", encoding="utf-8") as f:
    json.dump(catalog({k: (k, v) for k, v in T.items()}), f, ensure_ascii=False, indent=2)
with open(os.path.join(out, "InfoPlist.xcstrings"), "w", encoding="utf-8") as f:
    json.dump(catalog(INFOPLIST), f, ensure_ascii=False, indent=2)

# Controle: alle teksten uit de code moeten in T staan
pats = [
    r'(?:Text|Button|Label|Toggle|Section|NavigationLink|LabeledContent|TextField|Picker|ContentUnavailableView|Link|StepHeader|RuleRow|ProgressLabel)\(\s*"((?:[^"\\]|\\.)*)"',
    r'LocalizedStringKey\("((?:[^"\\]|\\.)*)"\)', r'String\(localized:\s*"((?:[^"\\]|\\.)*)"',
    r'\.(?:navigationTitle|confirmationDialog|alert)\(\s*"((?:[^"\\]|\\.)*)"',
    r'(?:title|text):\s*"((?:[^"\\]|\\.)*)"', r'case \.\w+: "((?:[^"\\]|\\.)*)"', r'default: "((?:[^"\\]|\\.)*)"',
    r'\? "((?:[^"\\]|\\.)*)" : "((?:[^"\\]|\\.)*)"',
]
ignore = {"spam", "beledigend", "persoonsgegevens", "bedreigend", "anders", "31"}
missing = set()
for f in glob.glob(os.path.join(ROOT, "WijkHub", "**", "*.swift"), recursive=True):
    if f.endswith(("MoreAppsCard.swift", "AppInfoFooter.swift", "Typography.swift")):
        continue
    s = open(f, encoding="utf-8").read()
    for p in pats:
        for m in re.finditer(p, s):
            for g in m.groups():
                if not g or g in ignore or re.fullmatch(r"[a-z0-9.]+", g) or g.startswith("\\("):
                    continue
                key = re.sub(r"\\\((?:step|Step)[^)]*\)\)?", "%lld", g)
                key = re.sub(r"\\\((?:[^()]|\([^()]*\))*\)", "%@", key)
                if key not in T:
                    missing.add(key)
if missing:
    print("Ontbrekende vertalingen:", *sorted(missing), sep="\n  ")
    sys.exit(1)
print(f"OK: {len(T)} teksten in {len(LANGS) + 1} talen")
