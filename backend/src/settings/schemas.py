import re
from datetime import datetime
from pydantic import BaseModel, Field, field_validator


DURATION_RE = re.compile(r"^(\d+)([mhd])$")


def _parse_duration_minutes(value: str) -> int:
    match = DURATION_RE.match(value)
    if not match:
        raise ValueError("Invalid format. Use <number> + m/h/d (e.g. 5m, 1h, 7d).")

    number = int(match.group(1))
    unit = match.group(2)

    multiplier = {"m": 1, "h": 60, "d": 1440}
    return number * multiplier[unit]


class RuntimeSettings(BaseModel):
    sub_name: str = "OLCWave"
    sub_update_interval: str = "1h"
    default_traffic_limit: int = 100 * 1000**3
    traffic_collect_interval: int = 10
    sync_interval: str = "4h"
    last_sync_at: datetime | None = None
    room_autogen_tokens: dict = Field(default_factory=dict)
    rw_api_url: str = ""
    rw_api_token_encrypted: str = ""
    rw_caddy_token_encrypted: str = ""


    @field_validator("sub_update_interval")
    @classmethod
    def validate_sub_update_interval(cls, v: str) -> str:
        if not DURATION_RE.match(v):
            raise ValueError(
                "Invalid format. Use <number> + m/h/d (e.g. 5m, 1h, 7d)."
            )

        minutes = _parse_duration_minutes(v)

        if minutes < 5:
            raise ValueError("Interval must be at least 5m.")
        if minutes > 43200:
            raise ValueError("Interval must be at most 30d.")

        return v

class RemnawaveSettingsResponse(BaseModel):
    rw_api_url: str
    rw_api_token_configured: bool
    rw_caddy_token_configured: bool


class RemnawaveSettingsUpdate(BaseModel):
    rw_api_url: str
    rw_api_token: str = ""
    rw_caddy_token: str = ""


class RemnawaveConnectionResult(BaseModel):
    success: bool
    message: str


class RemnawaveTestResponse(BaseModel):
    remnawave: RemnawaveConnectionResult
    caddy: RemnawaveConnectionResult