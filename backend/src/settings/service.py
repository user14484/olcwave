from datetime import datetime

from settings.models import SettingsModel
from settings.schemas import RuntimeSettings
from database import async_session_factory
from config import settings as env_settings
from settings.crypto import encrypt_value, decrypt_value

class SettingsService:
    _settings: RuntimeSettings | None = None

    @staticmethod
    def get():
        if SettingsService._settings is None:
            raise RuntimeError("Settings not loaded")
        return SettingsService._settings

    @staticmethod
    async def load():
        async with async_session_factory() as db:
            obj = await db.get(SettingsModel, 1)

            if obj is None:
                obj = SettingsModel(id=1, data=RuntimeSettings().model_dump(mode="json"))
                db.add(obj)
                await db.commit()

        SettingsService._settings = RuntimeSettings.model_validate(obj.data)

        changed = False

        if (
            env_settings.RW_API_URL
            and not SettingsService._settings.rw_api_url
        ):
            SettingsService._settings.rw_api_url = env_settings.RW_API_URL.rstrip("/")
            changed = True

        if (
            env_settings.RW_API_TOKEN
            and not SettingsService._settings.rw_api_token_encrypted
        ):
            SettingsService._settings.rw_api_token_encrypted = encrypt_value(
                env_settings.RW_API_TOKEN
            )
            changed = True

        if (
            env_settings.RW_CADDY_TOKEN
            and not SettingsService._settings.rw_caddy_token_encrypted
        ):
            SettingsService._settings.rw_caddy_token_encrypted = encrypt_value(
                env_settings.RW_CADDY_TOKEN
            )
            changed = True

        if changed:
            async with async_session_factory() as db:
                obj = await db.get(SettingsModel, 1)
                if obj is not None:
                    obj.data = SettingsService._settings.model_dump(mode="json")
                    await db.commit()

    @staticmethod
    async def set(settings: RuntimeSettings):
        SettingsService._settings = settings

        async with async_session_factory() as db:
            obj = await db.get(SettingsModel, 1)

            if obj is None:
                obj = SettingsModel(id=1, data=settings.model_dump(mode="json"))
                db.add(obj)
            else:
                obj.data = settings.model_dump(mode="json")

            await db.commit()

    @staticmethod
    async def set_remnawave(
        rw_api_url: str,
        rw_api_token: str = "",
        rw_caddy_token: str = "",
        clear_api_token: bool = False,
        clear_caddy_token: bool = False,
    ):
        current = SettingsService.get()

        current.rw_api_url = rw_api_url.strip().rstrip("/")

        if clear_api_token:
            current.rw_api_token_encrypted = ""
        elif rw_api_token:
            current.rw_api_token_encrypted = encrypt_value(rw_api_token.strip())

        if clear_caddy_token:
            current.rw_caddy_token_encrypted = ""
        elif rw_caddy_token:
            current.rw_caddy_token_encrypted = encrypt_value(
                rw_caddy_token.strip()
            )

        await SettingsService.set(current)

    @staticmethod
    def get_remnawave_credentials() -> tuple[str, str, str]:
        current = SettingsService.get()

        return (
            current.rw_api_url,
            decrypt_value(current.rw_api_token_encrypted),
            decrypt_value(current.rw_caddy_token_encrypted),
        )

    @staticmethod
    async def update_last_sync(dt: datetime):
        if SettingsService._settings is None:
            return
        SettingsService._settings.last_sync_at = dt

        async with async_session_factory() as db:
            obj = await db.get(SettingsModel, 1)
            if obj is not None:
                obj.data = SettingsService._settings.model_dump(mode="json")
                await db.commit()