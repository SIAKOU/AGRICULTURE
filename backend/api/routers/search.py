"""
Recherche globale (palette de commandes, barre de recherche).

Un seul point d'entrée `GET /api/v1/search?q=…` qui interroge les entités que
l'utilisateur peut réellement voir : acteurs, publications communautaires et
fichiers (les siens ou publics). Aucun résultat simulé : chaque groupe renvoie
soit des lignes issues de la base, soit un tableau vide.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from api.models.sql.actors import Actor
from api.models.sql.community import Post
from api.models.sql.files import FileShare
from api.models.sql.user import User
from config.database import get_db
from src.services.auth import get_current_active_user

router = APIRouter()

MAX_RESULTS_PER_GROUP = 5


@router.get("")
async def global_search(
    q: str = Query(..., min_length=2, max_length=120, description="Terme recherché"),
    limit: int = Query(MAX_RESULTS_PER_GROUP, ge=1, le=20),
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Recherche multi-entités.

    Réponse :
    ```
    {
      "query": "maïs",
      "total": 3,
      "groups": [ {"entity": "actors", "label": "Acteurs", "items": [...]}, … ]
    }
    ```
    """
    term = f"%{q.strip()}%"
    groups: list[dict[str, Any]] = []

    # ── Acteurs ──────────────────────────────────────────────────────────────
    actors = (
        await db.execute(
            select(Actor)
            .where(
                or_(
                    Actor.nom.ilike(term),
                    Actor.prenom.ilike(term),
                    Actor.nom_organisation.ilike(term),
                    Actor.email.ilike(term),
                    Actor.region.ilike(term),
                    Actor.pays.ilike(term),
                )
            )
            .limit(limit)
        )
    ).scalars().all()

    if actors:
        groups.append(
            {
                "entity": "actors",
                "label": "Acteurs",
                "items": [
                    {
                        "id": str(actor.id),
                        "title": " ".join(
                            part for part in (actor.prenom, actor.nom) if part
                        ) or actor.nom_organisation or "Acteur",
                        "subtitle": actor.nom_organisation or actor.region or actor.pays,
                        "href": f"/actors/{actor.id}",
                        "sector": getattr(actor.sous_secteur, "value", actor.sous_secteur),
                    }
                    for actor in actors
                ],
            }
        )

    # ── Publications ─────────────────────────────────────────────────────────
    posts = (
        await db.execute(
            select(Post)
            .where(
                Post.is_published.is_(True),
                or_(Post.title.ilike(term), Post.content.ilike(term)),
            )
            .limit(limit)
        )
    ).scalars().all()

    if posts:
        groups.append(
            {
                "entity": "posts",
                "label": "Communauté",
                "items": [
                    {
                        "id": str(post.id),
                        "title": post.title or (post.content[:70] + "…" if post.content else "Publication"),
                        "subtitle": "Publication communautaire",
                        "href": f"/community?post={post.id}",
                    }
                    for post in posts
                ],
            }
        )

    # ── Fichiers (les siens ou publics) ──────────────────────────────────────
    files = (
        await db.execute(
            select(FileShare)
            .where(
                or_(
                    FileShare.uploaded_by == current_user.id,
                    FileShare.is_public.is_(True),
                ),
                or_(FileShare.original_name.ilike(term), FileShare.description.ilike(term)),
            )
            .limit(limit)
        )
    ).scalars().all()

    if files:
        groups.append(
            {
                "entity": "files",
                "label": "Fichiers",
                "items": [
                    {
                        "id": str(item.id),
                        "title": item.original_name,
                        "subtitle": f"{(item.file_size or 0) / 1024:.0f} Ko",
                        "href": "/files",
                        "mime_type": item.mime_type,
                    }
                    for item in files
                ],
            }
        )

    total = sum(len(group["items"]) for group in groups)

    # Deux présentations du même résultat :
    #  - `groups`  : groupée par entité (palette de commandes avec en-têtes) ;
    #  - `results` : liste plate normalisée, consommée par `hooks/use-search.ts`.
    entity_to_type = {"actors": "actor", "posts": "post", "files": "file"}
    results = [
        {
            "id": item["id"],
            "type": entity_to_type.get(group["entity"], group["entity"]),
            "label": item["title"],
            "description": item.get("subtitle"),
            "href": item["href"],
        }
        for group in groups
        for item in group["items"]
    ]
    return {"query": q, "total": total, "results": results, "groups": groups}
