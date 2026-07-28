import io
import tarfile

import docker_client
from aiodocker import DockerError
from aiodocker.containers import DockerContainer


class XrayCore:
    CONTAINER_NAME = "olcwave-xraycore"

    @staticmethod
    async def run(xray_json: str) -> DockerContainer:
        docker = docker_client.docker
        try:
            old = await docker.containers.get(XrayCore.CONTAINER_NAME)
            await old.delete(force=True)
        except DockerError:
            pass

        container = await docker.containers.create(
            config={
                "Image": "xraycore",
                "Env": [
                    f"CONFIG={xray_json}",
                ],
                "HostConfig": {
                    "PortBindings": {
                        "10808/tcp": [
                            {
                                "HostIp": "172.17.0.1",
                                "HostPort": "10808",
                            }
                        ],
                        "10808/udp": [
                            {
                                "HostIp": "172.17.0.1",
                                "HostPort": "10808",
                            }
                        ],
                    },
                },
                "ExposedPorts": {
                    "10808/tcp": {},
                    "10808/udp": {},
                },
            },
            name=XrayCore.CONTAINER_NAME,
        )

        await container.start()

        return container

    @staticmethod
    async def start() -> None:
        docker = docker_client.docker
        try:
            container = await docker.containers.get(XrayCore.CONTAINER_NAME)
            await container.start()
        except DockerError:
            print("XRAY CONTAINER NOT FOUND")

    @staticmethod
    async def stop() -> None:
        docker = docker_client.docker
        container = await docker.containers.get(XrayCore.CONTAINER_NAME)
        await container.stop()

    @staticmethod
    async def logs() -> str:
        docker = docker_client.docker
        container = await docker.containers.get(XrayCore.CONTAINER_NAME)
        logs = await container.log(stdout=True, stderr=True)
        return "".join(logs)

    @staticmethod
    async def get() -> DockerContainer:
        docker = docker_client.docker
        return await docker.containers.get(XrayCore.CONTAINER_NAME)

    @staticmethod
    async def is_running() -> bool:
        docker = docker_client.docker
        try:
            container = await docker.containers.get(XrayCore.CONTAINER_NAME)
            info = await container.show()
            return info["State"]["Status"] == "running"
        except DockerError:
            return False

    @staticmethod
    async def _get_archive(path: str) -> bytes:
        docker = docker_client.docker
        async with docker._query(
            f"containers/{XrayCore.CONTAINER_NAME}/archive",
            method="GET",
            params={"path": path},
        ) as response:
            archive = await response.read()    

            with tarfile.open(fileobj=io.BytesIO(archive), mode="r:*") as tar:
                member = tar.getmembers()[0]

                fp = tar.extractfile(member)
                if fp is None:
                    raise FileNotFoundError(path)

                return fp.read()

    @staticmethod
    async def get_geoip() -> bytes:
        return await XrayCore._get_archive("/app/geoip.dat")

    @staticmethod
    async def get_geosite() -> bytes:
        return await XrayCore._get_archive("/app/geosite.dat")