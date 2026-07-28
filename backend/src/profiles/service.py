import yaml

from fastapi import HTTPException

from olcrtc.service import Containers
from database import async_session_factory
from profiles.db import ProfilesDB
from profiles.schemas import ProfileSchema

class Profiles:
    @staticmethod
    def validate(config: str):
        profile_obj: dict = yaml.safe_load(config)  

        profile_obj['mode'] = "srv"
        profile_obj['data'] = "data"

        if profile_obj.get('socks', None):
            profile_obj.pop('socks')
        
        if profile_obj.get('crypto', None) is None or profile_obj["crypto"].get('key', None) is None or profile_obj['crypto']["key"] != "":
            profile_obj["crypto"] = {}
            profile_obj["crypto"]["key"] = ""    

        return yaml.safe_dump(profile_obj, sort_keys=False)

    @staticmethod
    async def add(profile: ProfileSchema):
        profile.profile = Profiles.validate(profile.profile)

        if not profile.tag:
            raise HTTPException(status_code=400, detail="Tag cannot be empty")

        profile.tag = profile.tag.replace("-", "")

        async with async_session_factory() as db:  
            _= await ProfilesDB.add(db, profile) 

    @staticmethod
    async def get(tag: str):
        async with async_session_factory() as db:
            profile = await ProfilesDB.get(db, tag) 
        return profile

    @staticmethod
    async def update(tag: str, name: str, profile: str):
        profile = Profiles.validate(profile)

        async with async_session_factory() as db:  
            _= await ProfilesDB.update(db, tag, name, profile) 

        await Containers.remove_all_by_config_tag(tag)

    @staticmethod
    async def delete(tag: str):
        async with async_session_factory() as db:  
            _=await ProfilesDB.delete(db, tag) 

        await Containers.remove_all_by_config_tag(tag)

    @staticmethod
    async def get_all() -> list[ProfileSchema]:
        async with async_session_factory() as db:  
            profiles: list[ProfileSchema] = await ProfilesDB.get_all(db) 
        
        return profiles