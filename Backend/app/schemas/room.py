"""Room registry API schemas."""
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class RoomPlayerIn(BaseModel):
    account_id: str
    name: str


class RoomHeartbeatIn(BaseModel):
    code: str = Field(min_length=1, max_length=5)
    mode: str = Field(default="ffa", max_length=16)
    host_account_id: str | None = None
    players: list[RoomPlayerIn] = Field(default_factory=list)


class RoomOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    code: str
    mode: str
    host_account_id: str | None
    players: list[dict]
    player_count: int
    updated_at: datetime