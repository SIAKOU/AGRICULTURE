#!/usr/bin/env python3
"""
Contrôle de contrat API — frontend ↔ backend.

Objectif : garantir qu'aucun écran n'appelle une route qui n'existe pas, et
qu'aucun service du backend ne dort sans être branché.

Méthode (100 % statique, aucune base de données requise) :

1. Backend : on lit `api/routers/router.py` pour connaître le préfixe de chaque
   routeur inclus, puis on extrait les décorateurs `@router.<verbe>("chemin")`
   de chaque module. Chemin complet = préfixe d'inclusion + préfixe propre du
   routeur + chemin du décorateur.
2. Frontend : on cherche les appels `apiClient.<verbe>(...)"`, `api.<verbe>` et
   `fetch(...)` dont l'URL est un littéral ou un gabarit, puis on retire
   `/api/v1` (ajouté par `lib/api-client.ts`) et on normalise les segments
   dynamiques (`{user_id}`, `${id}`) en `*`.

Usage :
    python scripts/check-api-contract.py            # rapport + code de sortie
    python scripts/check-api-contract.py --verbose  # détail des routes inutilisées

Code de sortie : 0 si toutes les routes appelées existent, 1 sinon.
"""

from __future__ import annotations

import argparse
import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKEND = ROOT / "backend"
FRONTEND = ROOT / "frontend"

VERBS = ("get", "post", "put", "patch", "delete", "head", "options")


# ─────────────────────────────────────────────────────────────────────────────
# Backend : routes exposées
# ─────────────────────────────────────────────────────────────────────────────


def _router_prefix(tree: ast.Module) -> str:
    """Préfixe déclaré dans `router = APIRouter(prefix="/x")`, s'il existe."""
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        if not any(isinstance(t, ast.Name) and t.id in ("router", "health_router") for t in node.targets):
            continue
        if not isinstance(node.value, ast.Call):
            continue
        for kw in node.value.keywords:
            if kw.arg == "prefix" and isinstance(kw.value, ast.Constant):
                return str(kw.value.value)
    return ""


def _included_routers() -> dict[str, str]:
    """module -> préfixe d'inclusion, lu dans api/routers/router.py."""
    path = BACKEND / "api" / "routers" / "router.py"
    tree = ast.parse(path.read_text(encoding="utf-8"))
    aliases: dict[str, str] = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module and node.module.startswith("api.routers"):
            for alias in node.names:
                if alias.name in ("router", "health_router"):
                    aliases[alias.asname or alias.name] = node.module
                # `from api.routers import market_prices as market_prices_module`
                else:
                    aliases[alias.asname or alias.name] = f"{node.module}.{alias.name}"

    mapping: dict[str, str] = {}
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if not (isinstance(func, ast.Attribute) and func.attr == "include_router"):
            continue
        if not node.args:
            continue

        # Deux écritures sont acceptées :
        #   include_router(search_router, …)            → Name
        #   include_router(market_prices_module.router) → Attribute
        target = node.args[0]
        module: str | None = None
        if isinstance(target, ast.Name):
            module = aliases.get(target.id)
        elif isinstance(target, ast.Attribute) and isinstance(target.value, ast.Name):
            # `market_prices_module.router` : l'alias désigne déjà le module.
            module = aliases.get(target.value.id)
            if module and module.endswith(".router"):
                module = module[: -len(".router")]
        if not module:
            continue
        prefix = ""
        for kw in node.keywords:
            if kw.arg == "prefix" and isinstance(kw.value, ast.Constant):
                prefix = str(kw.value.value)
        mapping[module] = prefix
    return mapping


def backend_routes() -> dict[str, set[str]]:
    """verbe -> ensemble de chemins normalisés."""
    included = _included_routers()
    routes: dict[str, set[str]] = {v: set() for v in VERBS}

    for module, include_prefix in included.items():
        rel = Path(*module.split(".")).with_suffix(".py")
        path = BACKEND / rel
        if not path.exists():
            continue
        tree = ast.parse(path.read_text(encoding="utf-8"))
        own = _router_prefix(tree)
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            for deco in node.decorator_list:
                if not isinstance(deco, ast.Call) or not isinstance(deco.func, ast.Attribute):
                    continue
                verb = deco.func.attr
                if verb not in VERBS or not deco.args:
                    continue
                if not isinstance(deco.args[0], ast.Constant):
                    continue
                full = f"{include_prefix}{own}{deco.args[0].value}"
                routes[verb].add(normalise_backend(full))

    # Routes déclarées directement sur api_v1_router (racine, /ping, …).
    router_path = BACKEND / "api" / "routers" / "router.py"
    if router_path.exists():
        tree = ast.parse(router_path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            for deco in node.decorator_list:
                if not isinstance(deco, ast.Call) or not isinstance(deco.func, ast.Attribute):
                    continue
                verb = deco.func.attr
                if verb in VERBS and deco.args and isinstance(deco.args[0], ast.Constant):
                    routes[verb].add(normalise_backend(deco.args[0].value))

    routes["get"].add("/")
    return routes


def normalise_backend(path: str) -> str:
    path = re.sub(r"\{[^}]+\}", "*", path)
    path = re.sub(r"/+$", "", path) or "/"
    return path or "/"


# ─────────────────────────────────────────────────────────────────────────────
# Frontend : routes appelées
# ─────────────────────────────────────────────────────────────────────────────

CALL_RE = re.compile(
    r"""(?:\bapiClient|\bapi)\s*\.\s*(get|post|put|patch|delete)\s*(?:<[^>]*>)?\s*\(\s*
        (?:'([^']*)'|"([^"]*)"|`([^`]*)`)""",
    re.VERBOSE,
)

FETCH_RE = re.compile(
    r"""\bfetch\s*\(\s*(?:'([^']*)'|"([^"]*)"|`([^`]*)`)""",
    re.VERBOSE,
)


def normalise_frontend(raw: str) -> str:
    """
    Ramène une URL écrite dans le code à un chemin comparable au backend.

    Cas traités :
    - `${API_PREFIX}` retiré, `/api/v1` retiré (ajouté par api-client) ;
    - suffixe de requête conditionnel `` `${f ? `?type=${f}` : ''}` `` supprimé ;
    - segment dynamique `${id}` remplacé par `*` ;
    - expression ternaire finale (`` `${on ? 'activate' : 'deactivate'}` ``)
      remplacée par `*`, ce qui permet de valider les deux branches.
    """
    path = raw.replace("${API_PREFIX}", "").replace("${baseUrl}", "").replace("${apiPrefix}", "")
    path = path.split("?")[0]

    # Traitement des segments de gabarit, de gauche à droite :
    #  - `${id}` (identifiant simple)   → segment dynamique `*`
    #  - `${x ? 'a' : 'b'}` après un `/` → `*` (les deux branches sont valides)
    #  - `${x ? '-suffixe' : ''}` collé à un mot → suffixe de requête, supprimé
    rebuilt: list[str] = []
    index = 0
    while index < len(path):
        start = path.find("${", index)
        if start == -1:
            rebuilt.append(path[index:])
            break
        rebuilt.append(path[index:start])

        depth, cursor = 0, start
        while cursor < len(path):
            if path.startswith("${", cursor):
                depth += 1
                cursor += 2
                continue
            if path[cursor] == "}" and depth:
                depth -= 1
                cursor += 1
                if depth == 0:
                    break
                continue
            cursor += 1
        block = path[start:cursor]
        inner = block[2:-1]

        if re.fullmatch(r"[A-Za-z_$][\w$.]*", inner):
            rebuilt.append("*")
        elif rebuilt and rebuilt[-1].endswith("/"):
            rebuilt.append("*")
        # sinon : suffixe conditionnel, on l'ignore
        index = cursor

    path = "".join(rebuilt)
    path = re.sub(r"^https?://[^/]+", "", path)
    if path.startswith("/api/v1"):
        path = path[len("/api/v1") :]
    path = re.sub(r"/+$", "", path)
    return path or "/"


def frontend_calls() -> list[tuple[str, str, str]]:
    """Liste (verbe, chemin normalisé, fichier:ligne)."""
    calls: list[tuple[str, str, str]] = []
    roots = ["hooks", "lib", "components", "app", "stores"]
    for root in roots:
        for path in (FRONTEND / root).rglob("*"):
            if path.suffix not in (".ts", ".tsx") or not path.is_file():
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            for match in CALL_RE.finditer(text):
                verb = match.group(1)
                raw = match.group(2) or match.group(3) or match.group(4) or ""
                if not raw or raw.startswith("http"):
                    continue
                line = text[: match.start()].count("\n") + 1
                calls.append((verb, normalise_frontend(raw), f"{path.relative_to(FRONTEND)}:{line}"))
            for match in FETCH_RE.finditer(text):
                raw = match.group(1) or match.group(2) or match.group(3) or ""
                if not raw or raw.startswith("http"):
                    continue
                line = text[: match.start()].count("\n") + 1
                # Le verbe réel est dans les options : fetch(url, { method: 'POST' })
                tail = text[match.end() : match.end() + 400]
                verb_match = re.search(r"method\s*:\s*['\"]([A-Za-z]+)['\"]", tail)
                verb = verb_match.group(1).lower() if verb_match else "get"
                if verb not in VERBS:
                    verb = "get"
                normalised = normalise_frontend(raw)
                # Un chemin dont le premier segment est un joker (URL construite
                # à partir de constantes) n'est pas une route vérifiable.
                if (
                    not normalised.startswith("/")
                    or normalised.startswith("/*")
                    or normalised.strip("/") == ""
                ):
                    continue
                calls.append((verb, normalised, f"{path.relative_to(FRONTEND)}:{line}"))
    return calls


# ─────────────────────────────────────────────────────────────────────────────
# Comparaison
# ─────────────────────────────────────────────────────────────────────────────


def matches(backend_path: str, frontend_path: str) -> bool:
    """
    Compare deux chemins segment par segment.

    Un segment est compatible s'il est identique, ou si l'un des deux est un
    joker (`*`). Le frontend peut donc appeler `/admin/users/*/activate` et
    `/admin/users/*/*` (ternaire) pour une seule route backend.
    """
    backend_segments = [segment for segment in backend_path.split("/") if segment]
    frontend_segments = [segment for segment in frontend_path.split("/") if segment]
    if len(backend_segments) != len(frontend_segments):
        return False
    return all(
        back == "*" or front == "*" or back == front
        for back, front in zip(backend_segments, frontend_segments)
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Contrôle de contrat API front/back")
    parser.add_argument("--verbose", action="store_true", help="afficher aussi les routes backend non appelées")
    args = parser.parse_args()
    # Console Windows en cp1252 : on force UTF-8 pour les flèches et accents.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    routes = backend_routes()
    calls = frontend_calls()

    missing: dict[tuple[str, str], list[str]] = {}
    for verb, path, origin in calls:
        if any(matches(bp, path) for bp in routes.get(verb, set())):
            continue
        missing.setdefault((verb, path), []).append(origin)

    total_endpoints = sum(len(v) for v in routes.values())
    print(f"Backend : {total_endpoints} routes exposées (via api/routers/router.py)")
    print(f"Frontend : {len(calls)} appels détectés, {len({(v, p) for v, p, _ in calls})} routes distinctes")
    print()

    if not missing:
        print("OK — toutes les routes appelées par le frontend existent côté backend.")
    else:
        print(f"{len(missing)} route(s) appelée(s) sans équivalent backend :")
        for (verb, path), origins in sorted(missing.items()):
            print(f"  {verb.upper():6} /api/v1{path}")
            for origin in origins[:3]:
                print(f"         ← {origin}")
            if len(origins) > 3:
                print(f"         ← … {len(origins) - 3} autre(s)")

    if args.verbose:
        called = {(v, p) for v, p, _ in calls}
        print()
        print("Routes backend jamais appelées par le frontend :")
        for verb in VERBS:
            for bp in sorted(routes[verb]):
                if not any(matches(bp, cp) for cv, cp in called if cv == verb):
                    print(f"  {verb.upper():6} /api/v1{bp}")

    return 0 if not missing else 1


if __name__ == "__main__":
    sys.exit(main())
