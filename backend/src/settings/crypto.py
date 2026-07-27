import base64
import hashlib

from cryptography.fernet import Fernet

from config import settings


def _get_fernet() -> Fernet:
    key = hashlib.sha256(
        settings.SETTINGS_ENCRYPTION_KEY.encode("utf-8")
    ).digest()

    return Fernet(base64.urlsafe_b64encode(key))


def encrypt_value(value: str) -> str:
    if not value:
        return ""

    return _get_fernet().encrypt(value.encode("utf-8")).decode("utf-8")


def decrypt_value(value: str) -> str:
    if not value:
        return ""

    return _get_fernet().decrypt(value.encode("utf-8")).decode("utf-8")