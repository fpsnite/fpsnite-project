"""Vercel serverless entrypoint: expose the FastAPI app as an ASGI handler."""
from app.main import app

handler = app