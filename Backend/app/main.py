"""FastAPI application entrypoint."""
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.router import api_router
from app.core.config import settings
from app.services.errors import APIError


@asynccontextmanager
async def lifespan(_app: FastAPI):
    ## The Discord bot is a long-running background task - unsuitable for
    ## Vercel serverless. It only starts when RUN_BOT=true and a token is set
    ## (e.g. the standalone bot process or a long-lived host). On Vercel the
    ## API serves requests only; run the bot separately with `python -m bot`.
    if os.getenv("RUN_BOT", "").lower() == "true":
        from bot.runner import bot_runner

        await bot_runner.start()
        yield
        await bot_runner.stop()
    else:
        yield


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(APIError)
async def api_error_handler(_request: Request, exc: APIError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": {"code": exc.code, "message": exc.message}},
    )


app.include_router(api_router, prefix=settings.api_prefix)


@app.get("/")
def root() -> dict:
    return {"app": settings.app_name, "docs": "/docs", "health": f"{settings.api_prefix}/health"}