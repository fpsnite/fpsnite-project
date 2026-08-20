"""v2: player fields, friendships, rooms, account_id backfill

Revision ID: a1b2c3d4e5f6
Revises: a08242453b38
Create Date: 2026-08-19 12:00:00.000000

"""
import secrets
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = 'a08242453b38'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _random_account_id() -> str:
    return secrets.token_hex(8)


def upgrade() -> None:
    bind = op.get_bind()

    # 1. New columns on players (nullable first so backfill can run).
    op.add_column('players', sa.Column('account_id', sa.String(length=16), nullable=True))
    op.add_column('players', sa.Column('coins', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('players', sa.Column('current_skin', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('players', sa.Column('skins_locker', sa.JSON(), nullable=True))
    op.add_column('players', sa.Column('kills', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('players', sa.Column('deaths', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('players', sa.Column('wins', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('players', sa.Column('playtime_seconds', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('players', sa.Column('level', sa.Integer(), nullable=False, server_default='1'))
    op.add_column('players', sa.Column('xp', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('players', sa.Column('is_online', sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column('players', sa.Column('in_lobby', sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column('players', sa.Column('in_game', sa.Boolean(), nullable=False, server_default=sa.false()))

    # 2. Backfill account_id for existing rows (token_hex(8) = 16 hex chars).
    players = sa.table(
        'players',
        sa.column('id', sa.Integer),
        sa.column('account_id', sa.String(16)),
    )
    rows = bind.execute(sa.select(players.c.id)).fetchall()
    for (row_id,) in rows:
        bind.execute(
            players.update().where(players.c.id == row_id).values(account_id=_random_account_id())
        )

    # 3. account_id is now mandatory + unique.
    op.alter_column('players', 'account_id', nullable=False)
    op.create_index('ix_players_account_id', 'players', ['account_id'], unique=True)

    # 3b. Migrate legacy skin_index -> current_skin, then drop the old column.
    bind.execute(sa.text('UPDATE players SET current_skin = skin_index'))
    op.drop_column('players', 'skin_index')

    # 4. New tables.
    op.create_table(
        'friendships',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('requester_account_id', sa.String(length=16), nullable=False),
        sa.Column('addressee_account_id', sa.String(length=16), nullable=False),
        sa.Column('status', sa.String(length=16), nullable=False),
        sa.Column('created_at', sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('requester_account_id', 'addressee_account_id', name='uq_friendship_pair'),
    )
    op.create_index(op.f('ix_friendships_requester_account_id'), 'friendships', ['requester_account_id'], unique=False)
    op.create_index(op.f('ix_friendships_addressee_account_id'), 'friendships', ['addressee_account_id'], unique=False)

    op.create_table(
        'rooms',
        sa.Column('code', sa.String(length=5), nullable=False),
        sa.Column('mode', sa.String(length=16), nullable=False),
        sa.Column('host_account_id', sa.String(length=16), nullable=True),
        sa.Column('players', sa.JSON(), nullable=True),
        sa.Column('player_count', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint('code'),
    )


def downgrade() -> None:
    op.add_column('players', sa.Column('skin_index', sa.Integer(), nullable=False, server_default='0'))
    op.execute(sa.text('UPDATE players SET skin_index = current_skin'))
    op.drop_table('rooms')
    op.drop_index(op.f('ix_friendships_addressee_account_id'), table_name='friendships')
    op.drop_index(op.f('ix_friendships_requester_account_id'), table_name='friendships')
    op.drop_table('friendships')
    op.drop_index(op.f('ix_players_account_id'), table_name='players')
    for col in (
        'in_game', 'in_lobby', 'is_online', 'xp', 'level', 'playtime_seconds', 'wins',
        'deaths', 'kills', 'skins_locker', 'current_skin', 'coins', 'account_id',
    ):
        op.drop_column('players', col)