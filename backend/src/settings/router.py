from fastapi import APIRouter, Depends
from remnawave import RemnawaveSDK

from auth.dependencies import get_current_admin
from settings.schemas import (
    RuntimeSettings,
    RemnawaveSettingsResponse,
    RemnawaveSettingsUpdate,
    RemnawaveConnectionResult,
    RemnawaveTestResponse,
)
from settings.service import SettingsService

router = APIRouter(prefix="/settings", tags=["settings"])

def format_connection_error(exc: Exception) -> str:
    message = str(exc).lower()

    if "401" in message or "unauthorized" in message:
        return "Не удалось авторизоваться. Проверьте API Token."

    if "403" in message or "forbidden" in message:
        return "Доступ запрещён. Проверьте права токена."

    if "404" in message or "not found" in message:
        return "API Remnawave не найден. Проверьте адрес панели."

    if "timeout" in message or "timed out" in message:
        return "Remnawave не ответила вовремя."

    if "connect" in message or "connection" in message:
        return "Не удалось подключиться к Remnawave."

    return "Не удалось проверить подключение."ё

@router.get("/")
async def get_settings(_admin: dict = Depends(get_current_admin)):
    current = SettingsService.get()

    return current.model_dump(
        exclude={
            "rw_api_token_encrypted",
            "rw_caddy_token_encrypted",
        }
    )

@router.put("/")
async def set_setting(
    new_settings: RuntimeSettings,
    _admin: dict = Depends(get_current_admin),
):
    current = SettingsService.get()

    new_settings.rw_api_url = current.rw_api_url
    new_settings.rw_api_token_encrypted = current.rw_api_token_encrypted
    new_settings.rw_caddy_token_encrypted = current.rw_caddy_token_encrypted

    await SettingsService.set(new_settings)

    return new_settings.model_dump(
        exclude={
            "rw_api_token_encrypted",
            "rw_caddy_token_encrypted",
        }
    )

@router.get("/remnawave", response_model=RemnawaveSettingsResponse)
async def get_remnawave_settings(
    _admin: dict = Depends(get_current_admin),
):
    current = SettingsService.get()

    return RemnawaveSettingsResponse(
        rw_api_url=current.rw_api_url,
        rw_api_token_configured=bool(current.rw_api_token_encrypted),
        rw_caddy_token_configured=bool(current.rw_caddy_token_encrypted),
    )


@router.put("/remnawave", response_model=RemnawaveSettingsResponse)
async def update_remnawave_settings(
    data: RemnawaveSettingsUpdate,
    _admin: dict = Depends(get_current_admin),
):
    await SettingsService.set_remnawave(
        rw_api_url=data.rw_api_url,
        rw_api_token=data.rw_api_token,
        rw_caddy_token=data.rw_caddy_token,
        clear_api_token=data.clear_api_token,
        clear_caddy_token=data.clear_caddy_token,
    )

    current = SettingsService.get()

    return RemnawaveSettingsResponse(
        rw_api_url=current.rw_api_url,
        rw_api_token_configured=bool(current.rw_api_token_encrypted),
        rw_caddy_token_configured=bool(current.rw_caddy_token_encrypted),
    )

@router.post("/remnawave/test", response_model=RemnawaveTestResponse)
async def test_remnawave_settings(
    data: RemnawaveSettingsUpdate,
    _admin: dict = Depends(get_current_admin),
):
    current_url, current_api_token, current_caddy_token = (
        SettingsService.get_remnawave_credentials()
    )

    api_url = data.rw_api_url.rstrip("/") or current_url
    api_token = data.rw_api_token or current_api_token
    caddy_token = data.rw_caddy_token or current_caddy_token

    try:
        client = RemnawaveSDK(
            base_url=api_url,
            token=api_token,
            caddy_token=caddy_token or None,
        )

        await client.users.get_all_users(start=0, size=1)

        remnawave_result = RemnawaveConnectionResult(
            success=True,
            message="Подключение к Remnawave успешно",
        )
    except Exception as exc:
        remnawave_result = RemnawaveConnectionResult(
            success=False,
            message=format_connection_error(exc),
        )

    if not caddy_token:
        caddy_result = RemnawaveConnectionResult(
            success=True,
            message="Caddy Auth не используется",
        )
    else:
        try:
            client = RemnawaveSDK(
                base_url=api_url,
                token=api_token,
                caddy_token=caddy_token,
            )

            await client.subscriptions_settings.get_settings()

            caddy_result = RemnawaveConnectionResult(
                success=True,
                message="Запрос через Caddy Auth выполнен успешно",
            )
        except Exception as exc:
            caddy_result = RemnawaveConnectionResult(
                success=False,
                message=format_connection_error(exc),
            )

    return RemnawaveTestResponse(
        remnawave=remnawave_result,
        caddy=caddy_result,
    )