"""
Accès aux sources de données publiques externes.

Toutes les APIs utilisées ici sont **gratuites et sans clé** (vérifiées le
2026-11-26) :

| Source | Usage | Endpoint |
| --- | --- | --- |
| Banque mondiale | PIB agricole, inflation des prix alimentaires, taux de change officiel, profils pays | `api.worldbank.org/v2` |
| Open-Meteo | météo et géocodage (branché dans `api/routers/weather.py`) | `api.open-meteo.com` |

Principes :

1. **Aucune donnée inventée.** Si la source ne répond pas, on renvoie `None`
   ou une liste vide ; les routeurs décident alors d'un code 503 explicite
   plutôt que de fabriquer des chiffres de démonstration.
2. **Cache mémoire à TTL** : les indicateurs Banque mondiale changent une fois
   par an, inutile de les redemander à chaque requête. TTL de 6 h par défaut.
3. **Délais courts** (8 s) : un écran ne doit jamais attendre une source
   externe plus longtemps que son propre timeout.
"""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any, Iterable

import httpx

logger = logging.getLogger(__name__)

WORLD_BANK_BASE = "https://api.worldbank.org/v2"

# Indicateurs Banque mondiale utilisés par le produit.
INDICATORS = {
    # Valeur ajoutée de l'agriculture, sylviculture et pêche (US$ courants)
    "agricultural_gdp": "NV.AGR.TOTL.CD",
    # PIB total (US$ courants)
    "gdp": "NY.GDP.MKTP.CD",
    # Inflation des prix à la consommation (% annuel)
    "inflation": "FP.CPI.TOTL.ZG",
    # Taux de change officiel (devise locale pour 1 US$)
    "exchange_rate": "PA.NUS.FCRF",
    # Population rurale (% du total)
    "rural_population": "SP.RUR.TOTL.ZS",
    # Emploi agricole (% de l'emploi total)
    "agricultural_employment": "SL.AGR.EMPL.ZS",
    # Production alimentaire (indice 2014-2016 = 100)
    "food_production_index": "AG.PRD.FOOD.XD",
    # Terres arables (hectares par personne)
    "arable_land_per_capita": "AG.LND.ARBL.HA.PC",
}

COUNTRY_CODES = ["TG", "SN", "GH", "NG", "CI", "BF", "ML", "CM", "GN", "BJ"]

_CACHE: dict[str, tuple[float, Any]] = {}
_CACHE_TTL_SECONDS = 6 * 60 * 60


def _cache_get(key: str) -> Any | None:
    entry = _CACHE.get(key)
    if not entry:
        return None
    stored_at, value = entry
    if time.time() - stored_at > _CACHE_TTL_SECONDS:
        _CACHE.pop(key, None)
        return None
    return value


def _cache_set(key: str, value: Any) -> None:
    _CACHE[key] = (time.time(), value)


def cache_clear() -> None:
    """Utilisé par les tests et par un éventuel rechargement à chaud."""
    _CACHE.clear()


async def _worldbank(path: str, params: dict[str, Any], cache_key: str) -> Any | None:
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    url = f"{WORLD_BANK_BASE}/{path}"
    try:
        async with httpx.AsyncClient(timeout=8.0, headers={"User-Agent": "AgriIntel360/1.0"}) as client:
            response = await client.get(url, params={"format": "json", **params})
            response.raise_for_status()
            payload = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning("Banque mondiale indisponible (%s) : %s", cache_key, exc)
        return None

    # L'API renvoie [métadonnées, [observations]]
    if not isinstance(payload, list) or len(payload) < 2 or payload[1] is None:
        return None
    _cache_set(cache_key, payload)
    return payload


def _normalise_iso2(code: str) -> str:
    return code.strip().upper()[:2]


async def indicator_series(
    indicator_key: str,
    countries: Iterable[str] | None = None,
    *,
    per_page: int = 200,
    most_recent_only: bool = False,
) -> list[dict[str, Any]]:
    """
    Série d'un indicateur pour plusieurs pays.

    Retourne une liste normalisée :
    `{country_code, country_name, year, value, indicator, unit}`.
    Liste vide si la source ne répond pas — jamais de valeurs inventées.
    """
    indicator = INDICATORS.get(indicator_key, indicator_key)
    codes = [_normalise_iso2(c) for c in (countries or COUNTRY_CODES)]
    joined = ";".join(codes)
    params: dict[str, Any] = {"per_page": per_page}
    if most_recent_only:
        params["mrnev"] = 1
    else:
        params["date"] = "2015:2026"

    cache_key = f"wb:{indicator}:{joined}:{per_page}:{most_recent_only}"
    payload = await _worldbank(f"country/{joined}/indicator/{indicator}", params, cache_key)
    if not payload:
        return []

    series: list[dict[str, Any]] = []
    for row in payload[1] or []:
        value = row.get("value")
        if value is None:
            continue
        series.append(
            {
                "country_code": row.get("countryiso3code", "")[:2] or row.get("country", {}).get("id", ""),
                "country_name": row.get("country", {}).get("value", ""),
                "year": int(row.get("date", 0) or 0),
                "value": float(value),
                "indicator": indicator,
                "indicator_key": indicator_key,
                "unit": _unit_for(indicator_key),
                "source": "World Bank",
            }
        )
    series.sort(key=lambda item: (item["country_name"], item["year"]))
    return series


def _unit_for(indicator_key: str) -> str:
    return {
        "agricultural_gdp": "USD",
        "gdp": "USD",
        "inflation": "%",
        "exchange_rate": "LCU/USD",
        "rural_population": "%",
        "agricultural_employment": "%",
        "food_production_index": "index",
        "arable_land_per_capita": "ha/personne",
    }.get(indicator_key, "unité")


async def country_profiles(countries: Iterable[str] | None = None) -> list[dict[str, Any]]:
    """Fiche pays réelle : région, niveau de revenu, capitale (Banque mondiale)."""
    codes = [_normalise_iso2(c) for c in (countries or COUNTRY_CODES)]
    cache_key = f"wb:countries:{';'.join(codes)}"
    payload = await _worldbank("country/" + ";".join(codes), {"per_page": 100}, cache_key)
    if not payload:
        return []

    profiles = []
    for row in payload[1] or []:
        profiles.append(
            {
                "code": row.get("iso2Code", ""),
                "name": row.get("name", ""),
                "capital": row.get("capitalCity", ""),
                "region": (row.get("region") or {}).get("value", "").strip(),
                "income_level": (row.get("incomeLevel") or {}).get("value", ""),
                "longitude": row.get("longitude"),
                "latitude": row.get("latitude"),
                "source": "World Bank",
            }
        )
    profiles.sort(key=lambda item: item["name"])
    return profiles


async def agricultural_gdp(countries: Iterable[str] | None = None, most_recent_only: bool = False):
    return await indicator_series("agricultural_gdp", countries, most_recent_only=most_recent_only)


async def exchange_rates(countries: Iterable[str] | None = None) -> list[dict[str, Any]]:
    return await indicator_series("exchange_rate", countries, most_recent_only=True)


async def food_price_inflation(countries: Iterable[str] | None = None) -> list[dict[str, Any]]:
    return await indicator_series("inflation", countries, most_recent_only=False)


async def get_many(*coroutines) -> list[Any]:
    """Exécute plusieurs appels externes en parallèle (une requête HTTP chacun)."""
    return list(await asyncio.gather(*coroutines, return_exceptions=True))
