from docker.models.containers import Container
from fastapi import HTTPException

from routing.service import Routing
from xraycore.sdk import XrayCore
from olcrtc.sdk import OlcRTC
from olcrtc.schemas import ContainerSchema, ContainerConfigSchema, ContainerLogsSchema, ContainerStatsSchema

class Containers:
    @staticmethod
    def is_panel_container(cont: Container) -> bool:
        parts = cont.name.split("-")  # pyright: ignore[reportOptionalMemberAccess]
        return len(parts) == 3 and parts[0] == "olcwave"

    @staticmethod
    def to_schema(cont: Container) -> ContainerSchema | None:
        if len(cont.name.split("-")) != 3: 
            return

        _, config_tag, user_id = cont.name.split("-")  # pyright: ignore[reportOptionalMemberAccess]

        return ContainerSchema(
            id=cont.short_id, 
            name=cont.name,  # pyright: ignore[reportArgumentType]
            short_uuid=user_id,
            config_tag=config_tag,
            status=cont.status,
            created=cont.attrs.get("Created", ""),  # pyright: ignore[reportAny]
            image=cont.image.tags[0] if cont.image and cont.image.tags else "olcrtc",  # pyright: ignore[reportOptionalMemberAccess]
        )

    @staticmethod
    def all() -> list[ContainerSchema]:
        return [  # pyright: ignore[reportReturnType]
            Containers.to_schema(cont)
            for cont in OlcRTC.all(include_stopped=True)
            if Containers.is_panel_container(cont) and Containers.to_schema(cont) is not None
        ]

    @staticmethod
    def run(config: str, config_tag: str, short_uuid: str):
        routing_socks_addr = ""
        if XrayCore.is_running():
            routing_socks_addr = f"host.docker.internal:10808"

        OlcRTC.run(config, config_tag, short_uuid, routing_socks_addr)

    @staticmethod
    def start(name: str):
        OlcRTC.start(name)

    @staticmethod
    def stop(name: str):
        OlcRTC.stop(name)

    @staticmethod
    def restart(
        name: str,
        upstream_proxy_addr: str = "",
        upstream_proxy_user: str = "",
        upstream_proxy_pass: str = "",
    ):
        OlcRTC.restart(name, upstream_proxy_addr, upstream_proxy_user, upstream_proxy_pass)

    @staticmethod
    def remove(name: str):
        OlcRTC.remove(name)

    @staticmethod
    def logs(name: str) -> ContainerLogsSchema:
        return ContainerLogsSchema(name=name, logs=OlcRTC.logs(name))

    @staticmethod
    def get_config(name: str) -> ContainerConfigSchema:
        config: str = OlcRTC.get_config(name).output.decode()  # pyright: ignore[reportAny]
        return ContainerConfigSchema(name=name, config=config)

    @staticmethod
    def get_stats(name: str) -> ContainerStatsSchema:
        data = OlcRTC.get_stats(name)
        return ContainerStatsSchema(
            name=name,
            upload_bytes=int(data.get("upload_bytes", 0)),
            download_bytes=int(data.get("download_bytes", 0)),
            total_bytes=int(data.get("total_bytes", 0)),
            upload_rate_bps=int(data.get("upload_rate_bps", 0)),
            download_rate_bps=int(data.get("download_rate_bps", 0)),
        )


    @staticmethod
    def stop_all_by_short_uuid(short_uuid: str):
        containers = Containers.all()
        
        for container in containers:
            if container.short_uuid == short_uuid:
                Containers.stop(container.name)

    @staticmethod
    def stop_all_by_config_tag(config_tag: str):
        containers = Containers.all()

        for container in containers:
            if container.config_tag == config_tag:
                Containers.stop(container.name)

    @staticmethod
    def remove_all_by_short_uuid(short_uuid: str):
        containers = Containers.all()
        
        for container in containers:
            if container.short_uuid == short_uuid:
                Containers.remove(container.name)

    @staticmethod
    def remove_all_by_config_tag(config_tag: str):
        containers = Containers.all()

        for container in containers:
            if container.config_tag == config_tag:
                Containers.remove(container.name)

