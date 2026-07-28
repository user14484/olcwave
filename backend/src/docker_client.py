import aiodocker

docker: aiodocker.Docker | None = None


async def init_docker():
    global docker
    docker = aiodocker.Docker()


async def close_docker():
    global docker

    if docker:
        await docker.close()
        docker = None