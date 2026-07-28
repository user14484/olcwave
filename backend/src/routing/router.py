from fastapi import APIRouter, Depends, Body, HTTPException

from auth.dependencies import get_current_admin
from settings.service import SettingsService
from xraycore.sdk import XrayCore
from routing.service import Routing

router = APIRouter(prefix="/routing", tags=["routing"])

@router.get("/enabled")
async def check_enabled(_admin: dict = Depends(get_current_admin)):
    try:
        await Routing.get() # if enabled -> record in db exists -> True; if not error 404
    except HTTPException:
        return False
        
    return True

@router.get("/config")
async def get(_admin: dict = Depends(get_current_admin)):
    profile = await Routing.get()

    return profile

@router.post("/config")
async def create(xray_json: str = Body(), _admin: dict = Depends(get_current_admin)):
    await Routing.create(xray_json)

    return "ok"
    
@router.put("/config")
async def update(xray_json: str = Body(), _admin: dict = Depends(get_current_admin)):
    await Routing.update(xray_json)

@router.delete("/config")
async def delete(_admin: dict = Depends(get_current_admin)):
    await Routing.delete()

@router.get("/logs")
async def logs(_admin: dict = Depends(get_current_admin)):
    return XrayCore.logs()

@router.get("/geotags")
async def get_geotags(_admin: dict = Depends(get_current_admin)):
    return Routing.get_geotags()