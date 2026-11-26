"""Add payment_methods table

Revision ID: 010
Revises: 009
Create Date: 2026-11-26

L'écran « Abonnement » appelait `GET/POST /payments/methods` sans table ni route
correspondantes. Cette migration crée le stockage des moyens de paiement.
Aucune donnée de carte en clair : type, quatre derniers chiffres, expiration et
référence du fournisseur uniquement.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "010"
down_revision = "009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if inspector.has_table("payment_methods"):
        return

    op.create_table(
        "payment_methods",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("type", sa.String(length=30), nullable=False),
        sa.Column("provider", sa.String(length=50), nullable=False, server_default="flutterwave"),
        sa.Column("label", sa.String(length=120), nullable=True),
        sa.Column("last4", sa.String(length=4), nullable=True),
        sa.Column("expires_month", sa.Integer(), nullable=True),
        sa.Column("expires_year", sa.Integer(), nullable=True),
        sa.Column("authorization_code", sa.String(length=255), nullable=True),
        sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_payment_methods_user_id", "payment_methods", ["user_id"])
    op.create_index(
        "ix_payment_methods_user_active", "payment_methods", ["user_id", "is_active"]
    )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if inspector.has_table("payment_methods"):
        op.drop_index("ix_payment_methods_user_active", table_name="payment_methods")
        op.drop_index("ix_payment_methods_user_id", table_name="payment_methods")
        op.drop_table("payment_methods")
