# Copyright (C) 2026 invdevv - https://github.com/invdevv
# This file is part of olcwave.
# OLCWave is free software licensed under AGPL-3.0.

import asyncio

from docker.errors import NotFound
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

import uvicorn

from routing.service import Routing
from settings.service import SettingsService
from settings.router import router as settings_router
from auth.router import router as auth_router
from profiles.router import router as configs_router
from users.router import router as users_router
from subscriptions.router import router as subscriptions_router
from olcrtc.router import router as containers_router
from routing.router import router as routing_router
from xraycore.sdk import XrayCore
from config import settings
from database import create_tables
from traffic import TrafficManager
from rw_sync import SyncManager


async def lifespan(app: FastAPI):
    await create_tables() # TODO: add alembic migrations
    await SettingsService.load()

    try:
        routing = await Routing.get()
    except HTTPException:
        routing = False
    if routing:
        XrayCore.run(routing)

    SyncManager.start()
    task = asyncio.create_task(TrafficManager.run())
    yield
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass
    await SyncManager.stop()
    try:
        XrayCore.stop()
    except NotFound:
        pass

app = FastAPI(lifespan=lifespan, openapi_url="", docs_url="", redoc_url="")  # pyright: ignore[reportArgumentType]

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(configs_router)
app.include_router(users_router)
app.include_router(subscriptions_router)
app.include_router(containers_router)
app.include_router(settings_router)
app.include_router(routing_router)

@app.get("/health")
async def healthcheck():
    return "ok"

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0")
