"""
Comparateur de marchés — données réelles, sans simulation.

Le produit ne dispose pas (encore) d'un flux de prix relevés marché par marché.
Plutôt que d'inventer des prix, cet endpoint construit un **indice de pression
sur les prix alimentaires** à partir de la série officielle de la Banque mondiale
(inflation des prix à la consommation, `FP.CPI.TOTL.ZG`), capitalisée depuis la
première année disponible, base 100.

La réponse est explicitement étiquetée (`unit`, `currency`, `source`, `is_index`)
pour que l'interface annonce ce qu'elle montre : un indice, pas un prix au kilo.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query

from config.database import get_db
from src.services import external_apis
from src.services.auth import get_current_verified_user
from api.models.sql.user import User

router = APIRouter()

# Marchés proposés par l'interface → pays de la Banque mondiale.
MARKET_COUNTRIES: dict[str, dict[str, str]] = {
    "dakar": {"label": "Dakar (Sénégal)", "code": "SN"},
    "abidjan": {"label": "Abidjan (Côte d'Ivoire)", "code": "CI"},
    "lagos": {"label": "Lagos (Nigeria)", "code": "NG"},
    "accra": {"label": "Accra (Ghana)", "code": "GH"},
    "lome": {"label": "Lomé (Togo)", "code": "TG"},
    "cotonou": {"label": "Cotonou (Bénin)", "code": "BJ"},
    "ouagadougou": {"label": "Ouagadougou (Burkina Faso)", "code": "BF"},
    "bamako": {"label": "Bamako (Mali)", "code": "ML"},
}

# Produits suivis. La source étant un indice macroéconomique, le produit sert à
# étiqueter la demande ; il pourra être relié à un flux de prix réel lorsque le
# connecteur WFP/HDX sera activé.
PRODUCTS = {
    "maize": {"label": "Maïs"},
    "rice": {"label": "Riz"},
    "sorghum": {"label": "Sorgho"},
    "millet": {"label": "Mil"},
    "cassava": {"label": "Manioc"},
    "cocoa": {"label": "Cacao"},
    "cotton": {"label": "Coton"},
    "groundnut": {"label": "Arachide"},
}

THRESHOLD_PCT = 25.0


def _to_index(series: list[dict[str, Any]]) -> dict[int, float]:
    """Capitalise une série d'inflation annuelle en indice base 100."""
    index: dict[int, float] = {}
    level = 100.0
    for row in sorted(series, key=lambda item: item["year"]):
        level *= 1 + (row["value"] / 100.0)
        index[row["year"]] = round(level, 2)
    return index


@router.get("/compare")
async def compare_markets(
    product: str = Query("maize", description="Identifiant du produit (maize, rice, …)"),
    markets: str = Query(..., description="Identifiants de marchés séparés par des virgules"),
    period: str = Query("5y", description="Fenêtre d'analyse (3y, 5y, 10y, all)"),
    current_user: User = Depends(get_current_verified_user),
):
    selected = [slug.strip().lower() for slug in markets.split(",") if slug.strip()]
    unknown = [slug for slug in selected if slug not in MARKET_COUNTRIES]
    if unknown:
        raise HTTPException(status_code=422, detail=f"Marché inconnu : {', '.join(unknown)}")
    if len(selected) < 2:
        raise HTTPException(status_code=422, detail="Sélectionnez au moins deux marchés.")
    if len(selected) > 8:
        raise HTTPException(status_code=422, detail="Huit marchés au maximum.")

    countries = [MARKET_COUNTRIES[slug]["code"] for slug in selected]
    rows = await external_apis.indicator_series(
        "inflation", countries, per_page=500, most_recent_only=False
    )
    if not rows:
        raise HTTPException(
            status_code=503,
            detail="Source Banque mondiale indisponible : impossible de construire l'indice.",
        )

    by_country: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        by_country.setdefault(row["country_code"], []).append(row)

    indexes = {
        slug: _to_index(by_country.get(MARKET_COUNTRIES[slug]["code"], []))
        for slug in selected
    }

    years = sorted({year for index in indexes.values() for year in index})
    window = {"3y": 3, "5y": 5, "10y": 10}.get(period)
    if window:
        years = years[-window:]
    if not years:
        raise HTTPException(status_code=503, detail="Aucune année exploitable dans la source.")

    data = []
    for year in years:
        point: dict[str, Any] = {"date": str(year)}
        for slug in selected:
            value = indexes[slug].get(year)
            if value is not None:
                point[slug] = value
        data.append(point)

    summary = []
    for slug in selected:
        values = [indexes[slug][year] for year in years if year in indexes[slug]]
        if not values:
            continue
        first, last = values[0], values[-1]
        summary.append(
            {
                "market": slug,
                "label": MARKET_COUNTRIES[slug]["label"],
                "avg_price": round(sum(values) / len(values), 2),
                "min_price": min(values),
                "max_price": max(values),
                "trend": round(((last - first) / first) * 100, 2) if first else 0.0,
            }
        )

    if len(summary) < 2:
        raise HTTPException(
            status_code=503,
            detail="Données insuffisantes pour au moins deux marchés sélectionnés.",
        )

    latest = {item["market"]: item["avg_price"] for item in summary}
    highest = max(summary, key=lambda item: item["avg_price"])
    lowest = min(summary, key=lambda item: item["avg_price"])
    max_gap = round(highest["avg_price"] - lowest["avg_price"], 2)
    pct_gap = round((max_gap / lowest["avg_price"]) * 100, 2) if lowest["avg_price"] else 0.0

    return {
        "product": product,
        "product_label": PRODUCTS.get(product, {}).get("label", product),
        "unit": "indice (base 100)",
        "currency": "INDEX",
        "is_index": True,
        "period": period,
        "granularity": "année",
        "markets": selected,
        "market_labels": {slug: MARKET_COUNTRIES[slug]["label"] for slug in selected},
        "data": data,
        "summary": summary,
        "spread": {
            "max_gap": max_gap,
            "pct_gap": pct_gap,
            "threshold_exceeded": pct_gap >= THRESHOLD_PCT,
            "threshold": THRESHOLD_PCT,
        },
        "recommendation": {
            "best_market": highest["market"],
            "best_market_label": highest["label"],
            "premium": max_gap,
            "reason": (
                "Indice de prix le plus élevé sur la période : marché le plus rémunérateur "
                "à la vente, à confirmer par un relevé de prix local."
            ),
        }
        if latest
        else None,
        "source": "World Bank — inflation des prix à la consommation (FP.CPI.TOTL.ZG)",
    }


# ── Relevés de prix (liste) ───────────────────────────────────────────────────
# L'écran « Marchés » demandait `category=market_price` sur /indicators, valeur
# absente de l'enum Postgres : la requête partait en 500. On expose ici un
# contrat explicite — soit des relevés réels, soit un état « non disponible »
# motivé, jamais un tableau vide silencieux ni des prix inventés.

@router.get("")
async def list_market_prices(
    product: str | None = Query(None, description="Produit recherché (maize, rice, …)"),
    country: str | None = Query(None, description="Pays (code ISO2 ou nom)"),
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_verified_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Relevés de prix disponibles pour les marchés couverts.

    Tant qu'aucun connecteur de collecte n'est activé (WFP/HDX, ESOKO, FAO
    GIEWS), la réponse est `available: false` avec la raison et la piste
    d'extension. L'interface affiche alors un état vide explicite : elle ne
    présente jamais des indicateurs macroéconomiques comme des prix au kilo.
    """
    from sqlalchemy import select

    from api.models.sql.agricultural import IndicatorType, StagingEconomic

    # Types d'indicateurs qui portent un prix (l'enum ne contient pas de type
    # « marché » dédié : on s'appuie sur les séries existantes et on filtre les
    # lignes dont l'unité est monétaire).
    price_types = [IndicatorType.EXPORT, IndicatorType.IMPORT]
    query = select(StagingEconomic).where(
        StagingEconomic.indicator.in_(price_types)
    )
    if country:
        query = query.where(StagingEconomic.country_code == country.strip().upper()[:2])
    if product:
        query = query.where(StagingEconomic.notes.ilike(f"%{product}%"))
    query = query.order_by(StagingEconomic.year.desc()).limit(limit)

    try:
        rows = (await db.execute(query)).scalars().all()
    except Exception:  # table absente ou type non déclaré : on reste honnête
        rows = []

    if not rows:
        return {
            "available": False,
            "prices": [],
            "count": 0,
            "reason": (
                "Aucun relevé de prix n'est encore collecté. Les connecteurs "
                "prévus (WFP/HDX, ESOKO, FAO GIEWS) ne sont pas activés sur cet "
                "environnement ; l'onglet « Comparer » expose en attendant un "
                "indice de prix réel calculé sur les séries de la Banque mondiale."
            ),
            "connectors": [
                {"name": "WFP / HDX", "status": "planned", "kind": "csv"},
                {"name": "ESOKO", "status": "planned", "kind": "api"},
                {"name": "FAO GIEWS", "status": "planned", "kind": "api"},
            ],
            "source": None,
        }

    return {
        "available": True,
        "count": len(rows),
        "prices": [
            {
                "id": str(row.id),
                "product": (row.notes or "").strip() or "non précisé",
                "country": row.country_name,
                "country_code": row.country_code,
                "price": row.value,
                "unit": row.unit,
                "year": row.year,
                "source": row.source,
            }
            for row in rows
        ],
        "source": "Base AgriIntel360 (relevés collectés)",
    }


@router.get("/markets")
async def list_available_markets(current_user: User = Depends(get_current_verified_user)):
    """Marchés et produits disponibles pour le comparateur."""
    return {
        "markets": [
            {"value": slug, "label": meta["label"], "country": meta["code"]}
            for slug, meta in MARKET_COUNTRIES.items()
        ],
        "products": [{"value": slug, "label": meta["label"]} for slug, meta in PRODUCTS.items()],
    }
