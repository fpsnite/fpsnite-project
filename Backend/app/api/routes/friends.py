"""Friends endpoints: request, accept, decline, list, remove."""
from fastapi import APIRouter, status

from app.api.dependencies import CurrentPlayer, DbDep, resolve_player_or_404
from app.crud import friend as friend_crud
from app.crud import player as player_crud
from app.models.friend import STATUS_ACCEPTED, STATUS_DECLINED, STATUS_REQUESTED, Friendship
from app.schemas.friend import FriendOut, FriendRequestOut
from app.services.errors import APIError, ErrorCodes

router = APIRouter(prefix="/friends", tags=["friends"])


def _friend_out(db, account_id: str) -> FriendOut:
    friend = resolve_player_or_404(db, account_id)
    return FriendOut(
        account_id=friend.account_id,
        name=friend.name,
        is_online=friend.is_online,
        in_lobby=friend.in_lobby,
        in_game=friend.in_game,
    )


@router.get("", response_model=list[FriendOut])
def list_friends(player: CurrentPlayer = None, db: DbDep = None) -> list[FriendOut]:
    return [_friend_out(db, fid) for fid in friend_crud.list_accepted_ids(db, player.account_id)]


@router.get("/requests", response_model=list[FriendRequestOut])
def list_incoming(player: CurrentPlayer = None, db: DbDep = None) -> list[FriendRequestOut]:
    out: list[FriendRequestOut] = []
    for requester_id in friend_crud.list_incoming_ids(db, player.account_id):
        requester = resolve_player_or_404(db, requester_id)
        out.append(
            FriendRequestOut(
                requester_account_id=requester.account_id,
                requester_name=requester.name,
                created_at=friend_crud.get_incoming_request(db, player.account_id, requester_id).created_at,
            )
        )
    return out


@router.post("/{account_id}/request", status_code=status.HTTP_201_CREATED)
def send_request(account_id: str, player: CurrentPlayer = None, db: DbDep = None) -> dict:
    if player.account_id == account_id:
        raise APIError(ErrorCodes.INVALID_USERNAME, "You cannot befriend yourself.", status_code=400)
    resolve_player_or_404(db, account_id)

    existing = friend_crud.get_pair(db, player.account_id, account_id)
    if existing is not None:
        if existing.status == STATUS_ACCEPTED:
            raise APIError(ErrorCodes.ALREADY_FRIENDS, "Already friends.", status_code=409)
        if existing.status == STATUS_REQUESTED:
            if existing.requester_account_id == player.account_id:
                raise APIError(ErrorCodes.ALREADY_FRIENDS, "Request already sent.", status_code=409)
            # Reverse request exists -> auto-accept the pending one.
            existing.status = STATUS_ACCEPTED
            db.commit()
            return {"status": "accepted"}
        raise APIError(ErrorCodes.ALREADY_FRIENDS, "Friendship already exists.", status_code=409)

    friend_crud.create_request(db, player.account_id, account_id)
    return {"status": "requested"}


@router.post("/{account_id}/accept", response_model=FriendOut)
def accept_request(account_id: str, player: CurrentPlayer = None, db: DbDep = None) -> FriendOut:
    friendship = friend_crud.get_incoming_request(db, player.account_id, account_id)
    if friendship is None:
        raise APIError(ErrorCodes.FRIEND_NOT_FOUND, "No pending request from that player.", status_code=404)
    friendship.status = STATUS_ACCEPTED
    db.commit()
    return _friend_out(db, account_id)


@router.post("/{account_id}/decline")
def decline_request(account_id: str, player: CurrentPlayer = None, db: DbDep = None) -> dict:
    friendship = friend_crud.get_incoming_request(db, player.account_id, account_id)
    if friendship is None:
        raise APIError(ErrorCodes.FRIEND_NOT_FOUND, "No pending request from that player.", status_code=404)
    friendship.status = STATUS_DECLINED
    db.commit()
    return {"status": "declined"}


@router.delete("/{account_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_friend(account_id: str, player: CurrentPlayer = None, db: DbDep = None) -> None:
    friendship = friend_crud.get_pair(db, player.account_id, account_id)
    if friendship is None or friendship.status != STATUS_ACCEPTED:
        raise APIError(ErrorCodes.FRIEND_NOT_FOUND, "Not friends.", status_code=404)
    db.delete(friendship)
    db.commit()