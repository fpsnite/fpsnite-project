"""discord id link

Revision ID: 0c9e25e82463
Revises: a1148032fd6d
Create Date: 2026-08-13 11:54:15.285000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '0c9e25e82463'
down_revision: Union[str, None] = 'a1148032fd6d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # SQLite cannot ALTER TABLE to add constraints; batch mode recreates the
    # table with the new column and unique constraint in one step.
    with op.batch_alter_table('players') as batch_op:
        batch_op.add_column(sa.Column('discord_id', sa.BigInteger(), nullable=True))
        batch_op.create_unique_constraint('uq_players_discord_id', ['discord_id'])


def downgrade() -> None:
    with op.batch_alter_table('players') as batch_op:
        batch_op.drop_constraint('uq_players_discord_id', type_='unique')
        batch_op.drop_column('discord_id')