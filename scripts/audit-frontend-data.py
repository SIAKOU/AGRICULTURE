#!/usr/bin/env python3
"""
Audit d'intégrité des données du frontend.

Objectif : empêcher qu'un écran affiche une valeur qui ne vient pas de l'API.
Trois familles de défauts sont détectées :

1. **Repli inventé** — `donnee?.champ ?? 60` : quand l'API est muette, la valeur
   de repli est un chiffre plausible et l'utilisateur croit à une mesure.
   Les replis neutres (`?? 0`, `?? ''`, `?? []`, `?? null`) sont acceptés.
2. **Série synthétique** — `Math.random()` ou `Math.sin(i)` dans un calcul de
   données de graphique.
3. **Écran orphelin** — `page.tsx` qui ne rend ni composant client ni hook : il
   n'a alors aucune source de données.

Usage :
    python scripts/audit-frontend-data.py            # rapport + code de sortie
    python scripts/audit-frontend-data.py --strict   # échoue aussi sur les avis

Code de sortie : 0 si aucun défaut bloquant, 1 sinon.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FRONTEND = ROOT / "frontend"
SCAN_DIRS = ["app", "components", "hooks", "lib"]

# `?? 60`, `|| 12` : repli non neutre sur une valeur numérique.
NUMERIC_FALLBACK = re.compile(r"(\?\?|\|\|)\s*(-?[1-9][0-9]*(\.[0-9]+)?)\b")

# Un repli n'est **bloquant** que s'il porte sur une valeur d'API affichée : on
# regarde l'expression située juste avant l'opérateur.
DATA_VALUE = re.compile(
    r"(\bd\?*\.|\bdata\?*\.|\bstats\?*\.|\bsummary\?*\.|\buser\?*\.|\bactor\?*\.|"
    r"\bprofile\?*\.|\bres(?:ult)?\?*\.|\brow\?*\.|\bitem\?*\.|\bdetail\?*\.)"
)

# Replis de confort, jamais affichés comme mesure : pagination, temporisation,
# progression audio, densité d'écran, zoom de carte, bornes de calcul.
SAFE_CONTEXT = re.compile(
    r"(length|index|idx|tabIndex|Math\.max|Math\.min|\bpage\b|\bpages\b|\btotal_pages\b|\bper_page\b|"
    r"\blimit\b|refetchInterval|staleTime|\bduration\b|progress|devicePixelRatio|"
    r"\bzoom\b|\brange\b)"
)

SYNTHETIC = re.compile(r"Math\.random\(\)|Math\.sin\(")
# Un repli numérique est acceptable dans un état de formulaire (valeur initiale).
FORM_CONTEXT = re.compile(r"useState\(|setForm|defaultValue|initial|placeholder")
DATA_HOOK = re.compile(r"\buse[A-Z][A-Za-z0-9]*\(")
# Un écran est alimenté s'il rend un composant local (chemin absolu ou relatif).
RENDERS_COMPONENT = re.compile(r"from '(?:@/components/|\.\.?/)[^']+'")


def iter_files() -> list[Path]:
    files: list[Path] = []
    for directory in SCAN_DIRS:
        for path in (FRONTEND / directory).rglob("*"):
            if path.suffix in (".ts", ".tsx") and path.is_file():
                files.append(path)
    return files


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"^\s*//.*$", "", text, flags=re.M)


def audit() -> tuple[list[dict], list[dict]]:
    blocking: list[dict] = []
    advisories: list[dict] = []

    for path in iter_files():
        rel = path.relative_to(FRONTEND).as_posix()
        raw = path.read_text(encoding="utf-8", errors="ignore")
        text = strip_comments(raw)

        for line_no, line in enumerate(text.split("\n"), start=1):
            stripped = line.strip()

            # 1. Repli inventé — bloquant seulement sur une valeur d'API affichée
            for match in NUMERIC_FALLBACK.finditer(line):
                if SAFE_CONTEXT.search(line) or FORM_CONTEXT.search(line):
                    continue
                before = line[: match.start()]
                entry = {
                    "file": rel,
                    "line": line_no,
                    "kind": "repli inventé",
                    "detail": f"{match.group(1)} {match.group(2)} → {stripped[:110]}",
                }
                (blocking if DATA_VALUE.search(before) else advisories).append(entry)

            # 2. Série synthétique
            if SYNTHETIC.search(line) and "Array.from" in line:
                blocking.append(
                    {
                        "file": rel,
                        "line": line_no,
                        "kind": "série synthétique",
                        "detail": stripped[:110],
                    }
                )

        # 3. Écran orphelin
        if rel.startswith("app/") and rel.endswith("page.tsx"):
            has_hook = bool(DATA_HOOK.search(text))
            renders = bool(RENDERS_COMPONENT.search(text)) or "'use client'" in text
            if not has_hook and not renders:
                advisories.append(
                    {
                        "file": rel,
                        "line": 0,
                        "kind": "écran orphelin",
                        "detail": "aucun hook de données ni composant client rendu",
                    }
                )

    return blocking, advisories


HEX = re.compile(r"#[0-9A-Fa-f]{6}")


def audit_palette() -> list[dict]:
    """Repère une couleur identitaire recopiée dans un composant.

    La palette (`lib/palette.ts`) est la seule source des couleurs de données :
    secteur, série de graphique, type d'événement, halo d'état. Un composant qui
    réécrit une de ces valeurs en propre rompt la règle et dérive silencieusement
    dès qu'on ajuste la palette. Avis, non bloquant : les couleurs propres à un
    écran (dégradé décoratif) restent légitimes.
    """
    palette_file = Path("lib/palette.ts")
    if not palette_file.exists():
        return []
    declared = {h.upper() for h in HEX.findall(palette_file.read_text(encoding="utf-8", errors="replace"))}
    if not declared:
        return []
    duplicated = []
    for path in iter_files():
        rel = path.relative_to(ROOT).as_posix()
        if rel.endswith("lib/palette.ts"):
            continue
        for line_no, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            for found in HEX.findall(line):
                if found.upper() in declared:
                    duplicated.append(
                        {
                            "file": rel,
                            "line": line_no,
                            "kind": "couleur de la palette recopiée",
                            "detail": f"{found} — utiliser lib/palette.ts ({line.strip()[:70]})",
                        }
                    )
    return duplicated


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit d'intégrité des données frontend")
    parser.add_argument("--strict", action="store_true", help="traiter les avis comme bloquants")
    args = parser.parse_args()

    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    blocking, advisories = audit()

    print(f"Fichiers analysés : {len(iter_files())}")
    print()

    if blocking:
        print(f"{len(blocking)} défaut(s) bloquant(s) — une valeur affichée ne peut pas venir d'ailleurs que de l'API :")
        for item in blocking:
            print(f"  [{item['kind']}] {item['file']}:{item['line']}")
            print(f"      {item['detail']}")
    else:
        print("OK — aucun repli inventé, aucune série synthétique détectée.")

    duplicated = audit_palette()
    if duplicated:
        print()
        print(f"{len(duplicated)} couleur(s) identitaire(s) recopiée(s) hors de lib/palette.ts :")
        for item in duplicated:
            print(f"  {item['file']}:{item['line']} — {item['detail']}")

    if advisories:
        print()
        print(f"{len(advisories)} écran(s) sans source de données apparente :")
        for item in advisories:
            print(f"  {item['file']} — {item['detail']}")

    if blocking or (args.strict and advisories):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
