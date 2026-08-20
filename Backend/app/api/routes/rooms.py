"""Room registry endpoints: heartbeat + browser (TTL-filtered live rooms)."""
from fastapi import APIRouter, HTTPException

from app.api.dependencies import CurrentPlayer, DbDep
from app.crud import room as room_crud
from app.schemas.room import RoomHeartbeatIn, RoomOut

router = APIRouter(prefix="/rooms", tags=["rooms"])


@router.post("/heartbeat", response_model=RoomOut)
def heartbeat(body: RoomHeartbeatIn, player: CurrentPlayer = None, db: DbDep = None) -> RoomOut:
    room = room_crud.upsert_heartbeat(
        db,
        code=body.code.upper(),
        mode=body.mode,
        host_account_id=body.host_account_id or player.account_id,
        players=[p.model_dump() for p in body.players],
    )
    return RoomOut.model_validate(room)


@router.get("", response_model=list[RoomOut])
def list_rooms(limit: int = 50, db: DbDep = None) -> list[RoomOut]:
    return [RoomOut.model_validate(r) for r in room_crud.list_active(db, limit=limit)]


@router.get("/{code}", response_model=RoomOut)
def get_room(code: str, db: DbDep = None) -> RoomOut:
    room = room_crud.get(db, code.upper())
    if room is None or room_crud.is_stale(db, room):
        raise HTTPException(status_code=404, detail={"code": "NOT_FOUND", "message": "Room not found or stale."})
    return RoomOut.model_validate(room)