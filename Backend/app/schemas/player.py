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
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    skin_index: int
    created_at: datetime


class PlayerUpdate(BaseModel):
    skin_index: int = Field(ge=0, le=100)


class TokenOut(BaseModel):
    token: str
    player: PlayerOut