"""Currency endpoints: spend coins, buy skins."""
from fastapi import APIRouter

from app.api.dependencies import CurrentPlayer, DbDep
from app.schemas.currency import BuySkinIn, BuySkinOut, CoinsOut, SpendCoinsIn
from app.services.currency import buy_skin, spend_coins

router = APIRouter(tags=["currency"])


@router.get("/players/{account_id}/coins", response_model=CoinsOut)
def get_coins(account_id: str, player: CurrentPlayer = None, db: DbDep = None) -> CoinsOut:
    return CoinsOut(coins=player.coins)


@router.post("/players/{account_id}/coins/spend", response_model=CoinsOut)
def spend_coins_endpoint(
    account_id: str, body: SpendCoinsIn, player: CurrentPlayer = None, db: DbDep = None
) -> CoinsOut:
    coins = spend_coins(db, player, body.amount, reason=body.reason)
    return CoinsOut(coins=coins)


@router.post("/players/{account_id}/skins/buy", response_model=BuySkinOut)
def buy_skin_endpoint(
    account_id: str, body: BuySkinIn, player: CurrentPlayer = None, db: DbDep = None
) -> BuySkinOut:
    updated = buy_skin(db, player, body.skin_index)
    return BuySkinOut(
        coins=updated.coins,
        current_skin=updated.current_skin,
        skins_locker=list(updated.skins_locker or []),
    )