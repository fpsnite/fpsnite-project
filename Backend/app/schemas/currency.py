"""Currency API schemas."""
from pydantic import BaseModel, Field


class SpendCoinsIn(BaseModel):
    amount: int = Field(ge=1)
    reason: str = Field(default="", max_length=64)


class BuySkinIn(BaseModel):
    skin_index: int = Field(ge=0, le=100)


class CoinsOut(BaseModel):
    coins: int


class BuySkinOut(BaseModel):
    coins: int
    current_skin: int
    skins_locker: list[int]