"""Economics / Indicateurs économiques API endpoints"""

from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc

from config.database import get_db
from src.services import external_apis
from src.services.auth import get_current_verified_user
from api.models.sql.user import User
from api.models.sql.agricultural import StagingEconomic, IndicatorType

router = APIRouter()


@router.get("/indicators")
async def get_economic_indicators(
    country: Optional[str] = Query(None),
    indicator: Optional[str] = Query(None, description="gdp, inflation, agricultural_gdp, employment, export, import, investment"),
    year: Optional[int] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    current_user: User = Depends(get_current_verified_user),
    db: AsyncSession = Depends(get_db),
):
    """Liste des indicateurs économiques agricoles"""
    query = select(StagingEconomic).order_by(desc(StagingEconomic.year))
    if country:
        query = query.where(StagingEconomic.country_name.ilike(f"%{country}%"))
    if indicator:
        query = query.where(StagingEconomic.indicator == indicator)
    if year:
        query = query.where(StagingEconomic.year == year)
    query = query.limit(limit)

    try:
        result = await db.execute(query)
        rows = result.scalars().all()
        if rows:
            return {
                "data": [
                    {
                        "country_code": r.country_code,
                        "country_name": r.country_name,
                        "indicator": r.indicator,
                        "year": r.year,
                        "value": r.value,
                        "unit": r.unit,
                        "source": r.source,
                        "is_estimated": bool(r.is_estimated),
                        "notes": r.notes,
                    }
                    for r in rows
                ],
                "count": len(rows),
            }
    except Exception:
        pass

    # Aucune donnée en base : on interroge la source publique réelle.
    series = await external_apis.indicator_series(
        indicator or "agricultural_gdp", [country] if country else None, per_page=limit
    )
    if year:
        series = [item for item in series if item["year"] == year]
    return {
        "data": series[:limit],
        "count": len(series[:limit]),
        "source": "World Bank",
        "stored_locally": False,
    }


@router.get("/gdp")
async def get_gdp_data(
    country: Optional[str] = Query(None),
    start_year: Optional[int] = Query(None),
    end_year: Optional[int] = Query(None),
    current_user: User = Depends(get_current_verified_user),
    db: AsyncSession = Depends(get_db),
):
    """PIB agricole par pays et par année"""
    query = (
        select(StagingEconomic)
        .where(StagingEconomic.indicator == IndicatorType.AGRICULTURAL_GDP)
        .order_by(StagingEconomic.country_name, StagingEconomic.year)
    )
    if country:
        query = query.where(StagingEconomic.country_name.ilike(f"%{country}%"))
    if start_year:
        query = query.where(StagingEconomic.year >= start_year)
    if end_year:
        query = query.where(StagingEconomic.year <= end_year)

    try:
        result = await db.execute(query)
        rows = result.scalars().all()
        if rows:
            return {
                "gdp_data": [
                    {
                        "country": r.country_name,
                        "country_code": r.country_code,
                        "year": r.year,
                        "value": r.value,
                        "unit": r.unit,
                    }
                    for r in rows
                ],
                "count": len(rows),
            }
    except Exception:
        pass

    # Aucune donnée en base : série réelle de la Banque mondiale.
    series = await external_apis.agricultural_gdp(
        [country] if country else None, most_recent_only=not (start_year or end_year)
    )
    if start_year:
        series = [item for item in series if item["year"] >= start_year]
    if end_year:
        series = [item for item in series if item["year"] <= end_year]
    return {
        "gdp_data": [
            {
                "country": item["country_name"],
                "country_code": item["country_code"],
                "year": item["year"],
                "value": round(item["value"] / 1e9, 3),
                "unit": "billion USD",
            }
            for item in series
        ],
        "count": len(series),
        "source": "World Bank",
    }


@router.get("/summary")
async def get_economics_summary(
    current_user: User = Depends(get_current_verified_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Résumé économique réel, calculé à partir des séries de la Banque mondiale.

    Aucune valeur n'est inventée : les champs dont la source manque sont `null`
    et `source_missing` indique lesquels.
    """
    gdp_rows, inflation_rows, employment_rows = await external_apis.get_many(
        external_apis.indicator_series("agricultural_gdp", most_recent_only=True),
        external_apis.indicator_series("inflation", most_recent_only=True),
        external_apis.indicator_series("agricultural_employment", most_recent_only=True),
    )

    gdp_rows = gdp_rows if isinstance(gdp_rows, list) else []
    inflation_rows = inflation_rows if isinstance(inflation_rows, list) else []
    employment_rows = employment_rows if isinstance(employment_rows, list) else []

    total_gdp = sum(row["value"] for row in gdp_rows) or None
    top_exporters = sorted(
        ({"country": row["country_name"], "agricultural_gdp_usd": row["value"], "year": row["year"]}
         for row in gdp_rows),
        key=lambda item: item["agricultural_gdp_usd"],
        reverse=True,
    )[:3]

    def average(rows: list[dict]) -> float | None:
        values = [row["value"] for row in rows]
        return round(sum(values) / len(values), 2) if values else None

    missing = [
        name
        for name, rows in (
            ("agricultural_gdp", gdp_rows),
            ("inflation", inflation_rows),
            ("agricultural_employment", employment_rows),
        )
        if not rows
    ]

    return {
        "total_agricultural_gdp_usd": total_gdp,
        "top_agricultural_economies": top_exporters,
        "inflation_avg_percent": average(inflation_rows),
        "employment_in_agriculture_percent": average(employment_rows),
        "countries_covered": len({row["country_code"] for row in gdp_rows}),
        "year": max((row["year"] for row in gdp_rows), default=None),
        "source": "World Bank",
        "source_missing": missing,
    }


@router.get("/exchange-rates")
async def get_exchange_rates(
    countries: Optional[str] = Query(None, description="Codes ISO2 séparés par des virgules"),
    current_user: User = Depends(get_current_verified_user),
):
    """Taux de change officiels (devise locale pour 1 USD), source Banque mondiale."""
    codes = [code for code in (countries or "").split(",") if code.strip()] or None
    rows = await external_apis.exchange_rates(codes)
    return {"rates": rows, "count": len(rows), "source": "World Bank"}


@router.get("/countries/live")
async def get_country_profiles(
    countries: Optional[str] = Query(None, description="Codes ISO2 séparés par des virgules"),
    current_user: User = Depends(get_current_verified_user),
):
    """Fiches pays réelles : capitale, région, niveau de revenu (Banque mondiale)."""
    codes = [code for code in (countries or "").split(",") if code.strip()] or None
    profiles = await external_apis.country_profiles(codes)
    return {"countries": profiles, "count": len(profiles), "source": "World Bank"}
