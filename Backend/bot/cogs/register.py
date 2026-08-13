"""Discord cog: /register - create a game account linked to your Discord ID.
/token - re-issue the login token if the original message was lost.

Replies are ephemeral: the login token is only visible to the user who ran
the command, and only once.
"""
import logging

import discord
from discord import app_commands
from discord.ext import commands

from app.db.session import SessionLocal
from app.services.discord_register import create_account_from_discord, rotate_token_for_discord

logger = logging.getLogger(__name__)


class RegisterCog(commands.Cog):
    def __init__(self, bot: commands.Bot) -> None:
        self.bot = bot

    @app_commands.command(name="register", description="Create your FPS NITE game account")
    @app_commands.describe(username="Optional desired username (must be 1-24 chars)")
    async def register(
        self,
        interaction: discord.Interaction,
        username: app_commands.Range[str, 1, 24] | None = None,
    ) -> None:
        await interaction.response.defer(ephemeral=True)
        try:
            username = username.strip() if username else None
        except AttributeError:
            pass

        db = SessionLocal()
        try:
            player, token, error = create_account_from_discord(
                db, discord_id=interaction.user.id, username=username
            )
        except Exception:  # noqa: BLE001 - keep details out of the reply
            logger.exception("discord register failed")
            db.rollback()
            await interaction.followup.send(
                "Something went wrong creating your account. Try again.", ephemeral=True
            )
            return
        finally:
            db.close()

        if error == "ALREADY_LINKED":
            await interaction.followup.send(
                f"Your Discord is already linked to an account. "
                f"Use the token from your original /register message, or run /token "
                f"to get a new one.",
                ephemeral=True,
            )
            return
        if error == "NAME_TAKEN":
            await interaction.followup.send(
                f"Username `{username}` is taken. Try /register with a different username.",
                ephemeral=True,
            )
            return
        if player is None or token is None:
            await interaction.followup.send("Could not create your account.", ephemeral=True)
            return

        await interaction.followup.send(
            f"Account created!\n\n"
            f"**Username:** `{player.name}`\n"
            f"**Login token:** `{token}`\n\n"
            f"This is the only time you'll see your token. Paste it into the game "
            f"launcher once - after that you're signed in automatically.",
            ephemeral=True,
        )

    @app_commands.command(name="token", description="Get a new login token for your linked account")
    async def token(self, interaction: discord.Interaction) -> None:
        await interaction.response.defer(ephemeral=True)
        db = SessionLocal()
        try:
            player, new_token = rotate_token_for_discord(db, discord_id=interaction.user.id)
        except Exception:  # noqa: BLE001
            logger.exception("discord token rotation failed")
            db.rollback()
            await interaction.followup.send(
                "Something went wrong. Try again.", ephemeral=True
            )
            return
        finally:
            db.close()

        if player is None or new_token is None:
            await interaction.followup.send(
                "No account is linked to this Discord. Run /register first.", ephemeral=True
            )
            return

        await interaction.followup.send(
            f"New login token for **{player.name}**:\n\n`{new_token}`\n\n"
            f"The old token no longer works. This message is shown only once.",
            ephemeral=True,
        )


async def setup(bot: commands.Bot) -> None:
    await bot.add_cog(RegisterCog(bot))