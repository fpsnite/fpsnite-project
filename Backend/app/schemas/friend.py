"""Friend API schemas."""
from datetime import datetime

from pydantic import BaseModel


class FriendOut(BaseModel):
    account_id: str
    name: str
    is_online: bool
    in_lobby: bool
    in_game: bool


class FriendRequestOut(BaseModel):
    requester_account_id: str
    requester_name: str
    created_at: datetime