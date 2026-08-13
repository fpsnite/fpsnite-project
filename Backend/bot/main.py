"""FPS NITE Discord bot entrypoint.

Run with:  python -m bot   (from Backend/, using .venv)
Requires DISCORD_BOT_TOKEN in Backend/.env.
"""
import logging

import discord
from discord.ext import commands

from app.core.config import settings
from bot.cogs.register import RegisterCog

logger = logging.getLogger(__name__)

DISCORD_INTENTS = discord.Intents.default()


def build_bot() -> commands.Bot:
    bot = commands.Bot(command_prefix="!", intents=DISCORD_INTENTS)

    @bot.event
    async def on_ready() -> None:
        logger.info("Logged in as %s (id=%s)", bot.user, bot.user.id if bot.user else "?")

    async def setup() -> None:
        await bot.add_cog(RegisterCog(bot))
        await bot.tree.sync()
        logger.info("Slash commands synced")

    bot.setup_hook = setup
    return bot


def main() -> None:
    token = settings.discord_bot_token.strip()
    if not token:
        raise SystemExit("DISCORD_BOT_TOKEN is not set in Backend/.env")
    logging.basicConfig(level=logging.INFO)
    build_bot().run(token)


if __name__ == "__main__":
    main()