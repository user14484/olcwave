from remnawave.models.users import GetAllUsersResponseDto, UserResponseDto
from remnawave.models.users import GetUserByShortUuidResponseDto
from remnawave.models.subscription import GetSubscriptionInfoResponseDto
from remnawave import RemnawaveSDK
from remnawave.exceptions.general import NotFoundError
from remnawave.models import (
    SubscriptionInfoResponseDto,
    SubscriptionSettingsResponseDto,
)

from config import settings
from settings.service import SettingsService


def get_remnawave() -> RemnawaveSDK:
    api_url, api_token, caddy_token = (
        SettingsService.get_remnawave_credentials()
    )

    return RemnawaveSDK(
        base_url=api_url,
        token=api_token,
        caddy_token=caddy_token or None,
    )

async def getAllUsers() -> GetAllUsersResponseDto:
    PAGE_SIZE = 100

    client = get_remnawave()
    start = 0
    users: list[UserResponseDto] = []

    while True:
        response = await get_remnawave().users.get_all_users(
            start=start,
            size=PAGE_SIZE,
        )

        users.extend(response.users)

        if len(response.users) < PAGE_SIZE or len(users) >= response.total:
            break

        start += len(response.users)

    return GetAllUsersResponseDto(
        users=users,
        total=len(users),
    )


async def isUserValid(short_uuid: str) -> SubscriptionInfoResponseDto | None:
    client = get_remnawave()

    try:
        sub: GetSubscriptionInfoResponseDto = await client.subscription.get_subscription_info_by_short_uuid(short_uuid)  # pyright: ignore[reportAssignmentType]

        if not sub.is_found:
            return None

        if settings.RW_SQUAD_NAME:
            user: GetUserByShortUuidResponseDto = await client.users.get_user_by_short_uuid(short_uuid)  # pyright: ignore[reportAssignmentType]

            for squad in user.active_internal_squads:
                if settings.RW_SQUAD_NAME == squad.name or settings.RW_SQUAD_NAME == str(squad.uuid):
                    return sub
            return None

        return sub

    except NotFoundError:
        return None


async def getSubscriptionSettings():
    client = get_remnawave()

    sub: SubscriptionSettingsResponseDto = (
        await client.subscriptions_settings.get_settings()
    )

    return sub