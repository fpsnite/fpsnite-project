"""Player API schemas (request/response contracts)."""
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class RegisterIn(BaseModel):
    name: str = Field(min_length=1, max_length=24)
    password: str = Field(min_length=4, max_length=64)

    @field_validator("name")
    @classmethod
    def name_must_be_non_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("name must not be blank")
        return v


class LoginIn(BaseModel):
    name: str = Field(min_length=1, max_length=24)
    password: str = Field(min_length=1, max_length=64)

    @field_validator("name")
    @classmethod
    def name_must_be_non_blank(cls, v: str) -> str:
        return v.strip()


class PlayerOut(BaseModel):
    """v2 player profile. account_id is the public identifier (numeric id hidden)."""

    model_config = ConfigDict(from_attributes=True)

    account_id: str
    name: str
    coins: int
    current_skin: int
    skins_locker: list[int]
    kills: int
    deaths: int
    wins: int
    playtime_seconds: int
    level: int
    xp: int
    is_online: bool
    in_lobby: bool
    in_game: bool
    created_at: datetime


class PlayerUpdate(BaseModel):
    current_skin: int | None = Field(default=None, ge=0, le=100)
    skins_locker: list[int] | None = None


class TokenOut(BaseModel):
    token: str
    player: PlayerOut


class PresenceIn(BaseModel):
    online: bool | None = None
    in_lobby: bool | None = None
    in_game: bool | None = None