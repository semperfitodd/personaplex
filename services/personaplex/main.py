import os
from fastapi import FastAPI
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    hf_token: str = ""
    port: int = 8998
    
    class Config:
        env_prefix = ""

settings = Settings()
app = FastAPI()

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.get("/ready")
async def ready():
    return {"status": "ready", "model": "nvidia/personaplex-7b-v1"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=settings.port)
