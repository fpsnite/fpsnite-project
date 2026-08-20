"""Currency operations: atomic spend, skin purchases."""
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.player import Player
from app.services.errors import APIError, ErrorCodes


def spend_coins(db: Session, player: Player, amount: int, reason: str = "") -> int:
    if player.coins < amount:
        raise APIError(ErrorCodes.INSUFFICIENT_COINS, "Not enough coins.", status_code=400)
    player.coins -= amount
    db.commit()
    db.refresh(player)
    return player.coins


def buy_skin(db: Session, player: Player, skin_index: int) -> Player:
    """Add a skin to the locker (spending coins), then equip it."""
    price = settings.skin_prices.get(str(skin_index))
    if price is None:
        raise APIError(ErrorCodes.INVALID_SKIN, "That skin is not purchasable.", status_code=404)
    if player.coins < price:
        raise APIError(ErrorCodes.INSUFFICIENT_COINS, "Not enough coins.", status_code=400)
    locker = list(player.skins_locker or [])
    if skin_index not in locker:
        locker.append(skin_index)
    player.coins -= price
    player.skins_locker = locker
    player.current_skin = skin_index
    db.commit()
    db.refresh(player)
    return player