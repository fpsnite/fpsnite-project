"""auth token hash

Revision ID: a08242453b38
Revises: 0c9e25e82463
Create Date: 2026-08-13 12:45:21.288841

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a08242453b38'
down_revision: Union[str, None] = '0c9e25e82463'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # SQLite cannot ALTER TABLE to add constraints; batch mode recreates the
    # table with the new column and unique constraint in one step.
    with op.batch_alter_table('players') as batch_op:
        batch_op.add_column(sa.Column('auth_token_hash', sa.String(length=64), nullable=True))
        batch_op.create_unique_constraint('uq_players_auth_token_hash', ['auth_token_hash'])


def downgrade() -> None:
    with op.batch_alter_table('players') as batch_op:
        batch_op.drop_constraint('uq_players_auth_token_hash', type_='unique')
        batch_op.drop_column('auth_token_hash')