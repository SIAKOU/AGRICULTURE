"""
Formulaire de contact public.

Le message est envoyé par le service e-mail du projet (`src/services/email.py`).
Si aucun transport n'est configuré (SMTP absent), le message est journalisé et la
réponse l'indique explicitement (`delivered: false`) : le formulaire ne prétend
jamais avoir envoyé un e-mail qui n'est pas parti.
"""

from __future__ import annotations

import logging
import re

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

from src.services.email import send_email

logger = logging.getLogger(__name__)
router = APIRouter()

# Boîte de réception du produit (configurable par variable d'environnement).
import os

CONTACT_INBOX = os.getenv("CONTACT_INBOX", "contact@agriintel360.lsgrouptogo.com")


class ContactRequest(BaseModel):
    name: str = Field(..., min_length=2, max_length=120)
    # Validation par motif volontaire : `EmailStr` exigerait `email-validator`,
    # une dépendance supplémentaire non présente dans requirements.txt.
    email: str = Field(
        ...,
        max_length=254,
        pattern=r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$",
        description="Adresse e-mail du demandeur",
    )
    subject: str = Field(..., min_length=3, max_length=160)
    message: str = Field(..., min_length=20, max_length=4000)
    # Piège à robots : un champ caché rempli ⇒ on ignore silencieusement.
    honeypot: str | None = None


def _looks_like_spam(payload: ContactRequest) -> bool:
    if payload.honeypot:
        return True
    links = len(re.findall(r"https?://", payload.message))
    return links > 3


@router.post("", status_code=status.HTTP_202_ACCEPTED)
async def submit_contact(payload: ContactRequest):
    """Enregistre et transmet une demande de contact."""
    if _looks_like_spam(payload):
        # On répond 202 sans rien envoyer : le robot n'apprend rien.
        return {"accepted": True, "delivered": False, "reason": "ignored"}

    body = (
        f"Nouveau message depuis le site\n\n"
        f"Nom : {payload.name}\n"
        f"E-mail : {payload.email}\n"
        f"Sujet : {payload.subject}\n\n"
        f"{payload.message}\n"
    )

    delivered = False
    try:
        # `send_email` lève une exception si aucun transport n'est configuré :
        # on renvoie alors `delivered: false` plutôt que de mentir à l'utilisateur.
        await send_email([CONTACT_INBOX], f"[Contact] {payload.subject}", body)
        delivered = True
    except Exception as exc:  # transport absent ou en erreur
        logger.warning("Envoi du message de contact impossible : %s", exc)

    if not delivered:
        logger.info(
            "Message de contact conservé dans les journaux (aucun transport e-mail configuré) : %s / %s",
            payload.email,
            payload.subject,
        )

    return {
        "accepted": True,
        "delivered": delivered,
        "message": (
            "Message envoyé, nous répondons sous 48 h ouvrées."
            if delivered
            else "Message enregistré. L'envoi automatique n'est pas configuré sur cet environnement."
        ),
    }
