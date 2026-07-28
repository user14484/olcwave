import asyncio

from docker.errors import NotFound
from fastapi import HTTPException

import json

from xraycore.sdk import XrayCore
from database import async_session_factory
from routing.db import RoutingDB
from xraycore.geodata.geodat_pb2 import GeoSiteList, GeoIPList

class Routing:
    @staticmethod
    def validate_routing_geotags(routing: str):
        try:
            geotags = Routing.get_geotags()
        except Exception:
            raise HTTPException(status_code=400, detail="Cannot load geotags")

        geoip_set = {
            x.lower()
            for x in geotags.get("geoip", [])
        }

        geosite_set = {
            x.lower()
            for x in geotags.get("geosite", [])
        }

        try:
            config = json.loads(routing)
        except (json.JSONDecodeError, TypeError):
            raise HTTPException(status_code=400, detail="Invalid json")

        rules = config.get("routing", {}).get("rules", [])
        if not isinstance(rules, list):
            raise HTTPException(status_code=400, detail="Routing.rules is required")

        invalid = []

        for i, rule in enumerate(rules):
            if not isinstance(rule, dict):
                continue

            for ip_val in rule.get("ip", []):
                if isinstance(ip_val, str) and ip_val.lower().startswith("geoip:"):
                    code = ip_val[6:].lower()
                    if code not in geoip_set:
                        invalid.append({
                            "field": "routing.geoip",
                            "value": ip_val,
                            "reason": f'"{ip_val}" does not exist in available geoip tags',
                        })

            for domain_val in rule.get("domain", []):
                if isinstance(domain_val, str) and domain_val.lower().startswith("geosite:"):
                    code = domain_val[8:].lower()
                    if code not in geosite_set:
                        invalid.append({
                            "field": "routing.geosite",
                            "value": domain_val,
                            "reason": f'"{domain_val}" does not exist in available geosite tags',
                        })

        if invalid:
            detail = "Invalid geotag references in routing config:\n" + "\n".join(
                f'- {e["field"]}: {e["value"]} - {e["reason"]}' for e in invalid
            )
            raise HTTPException(status_code=422, detail=detail)

    @staticmethod
    def routing_to_xray_json(routing: str):
        xray_config = json.loads(routing)
        xray_config["dns"] = {"servers": [{"address": "1.1.1.1"}],"queryStrategy": "IPIfNonMatch"}
        xray_config["inbounds"] = [{
            "tag": "socks",
            "listen": "0.0.0.0",
            "port": 10808,
            "protocol": "socks",
            "settings": {
                "auth": "noauth",
                "udp": True
            },
            "sniffing": {
                "enabled": True,
                "destOverride": [
                "http",
                "tls",
                "fakedns"
                ]
            }
            }
        ]

        return json.dumps(xray_config, indent=2)

    @staticmethod
    async def create(routing: str):
        Routing.validate_routing_geotags(routing)

        xray_json = Routing.routing_to_xray_json(routing)

        async with async_session_factory() as db:  
            _= await RoutingDB.create(db, xray_json)

        XrayCore.run(xray_json)

        asyncio.create_task(Routing.restart_all_with_proxy())

        return xray_json

    @staticmethod
    async def get():
        async with async_session_factory() as db:
            xray_json = await RoutingDB.get(db) 
        return xray_json

    @staticmethod
    async def update(routing: str):
        Routing.validate_routing_geotags(routing)

        xray_json = Routing.routing_to_xray_json(routing)

        async with async_session_factory() as db:  
            _= await RoutingDB.update(db, xray_json) 

        XrayCore.run(xray_json)

        return xray_json


    @staticmethod
    async def delete():
        async with async_session_factory() as db:  
            _=await RoutingDB.delete(db)

        try:
            XrayCore.stop()
        except NotFound:
            pass

        asyncio.create_task(Routing.restart_all_with_proxy())

    @staticmethod
    def get_geotags():
        geoip_data = XrayCore.get_geoip()
        geosite_data = XrayCore.get_geosite()
        
        geoip = GeoIPList()
        geosite = GeoSiteList()

        geoip.ParseFromString(geoip_data)
        geosite.ParseFromString(geosite_data)

        return {
            "geoip": [x.code.lower() for x in geoip.entry],
            "geosite": [x.code.lower() for x in geosite.entry]
        }
    
    @staticmethod
    async def restart_all_with_proxy():
        from olcrtc.service import Containers

        sem = asyncio.Semaphore(10)

        async def restart_one(container):
            async with sem:
                await asyncio.to_thread(
                    Containers.restart,
                    container.name,
                    upstream_proxy_addr="host.docker.internal:10808",
                )

        await asyncio.gather(
            *(restart_one(c) for c in Containers.all())
        )