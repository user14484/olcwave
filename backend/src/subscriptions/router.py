from fastapi import APIRouter, HTTPException, Response
from settings.service import SettingsService
from subscriptions.service import Subscriptions
from rw.sdk import isUserValid

router = APIRouter(prefix="/sub", tags=["subscriptions"])

@router.get("/{short_uuid}/check")
async def get_provider_name(short_uuid: str):
    if await isUserValid(short_uuid):
        name = SettingsService.get().sub_name

        return Response(
            content=name,
            media_type="text/plain"
        )
    raise HTTPException(status_code=404, detail="Not found")


@router.get("/{short_uuid}")
async def get(short_uuid: str):
    sub = await Subscriptions.get(short_uuid)
    
    return sub