# Deploying the backend for free (Render)

The backend is FastAPI + SQLite and runs on Render's free tier. Photon (Fusion)
needs nothing from you - it is already a cloud service; the app id is baked
into the game export.

## 1. Push the backend to GitHub

The `Backend/` folder is self-contained. Create a new empty repo (e.g.
`fpsnite-backend`) and push just this folder:

```sh
git init
git add .
git commit -m "FPS NITE backend"
git remote add origin https://github.com/<you>/fpsnite-backend.git
git push -u origin main
```

> `.gitignore` already excludes `.env`, `*.db`, `.venv`, `__pycache__` - no
> secrets or local data will be uploaded.

## 2. Create the Render service

Option A - Blueprint (auto):

1. Go to https://render.com, sign up (free), then **New > Blueprint**
2. Connect your GitHub account and pick `fpsnite-backend`
3. `render.yaml` in the repo is picked up automatically -> **Apply**

Option B - Manual web service:

1. **New > Web Service**, connect the repo
2. Root directory: `Backend` (leave empty if you pushed the folder as its own repo)
3. Build command: `pip install -r requirements.txt`
4. Start command: `sh -c "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port $PORT"`
5. Instance type: **Free**
6. Add env var `ENV=production`, `CORS_ORIGINS=*` (see below)
7. **Create Web Service**

Wait for the deploy to finish, then open
`https://<your-service>.onrender.com/api/health` - it should return
`{"status": "ok", ...}`. The interactive API docs are at `/docs`.

## 3. Point the game at the deployed URL

`Scripts/backend.gd` resolves the URL in this order (first match wins):

1. Env var `FPSNITE_BACKEND_URL` (useful for the editor / dev)
2. File `res://backend_url.cfg` in the project root - **gitignored**, so dev
   collaborators can each point the editor at the deployed backend without
   touching tracked files. Create it and put the URL on one line:
   `https://<your-service>.onrender.com`
3. Project setting `network/backend_url` in `project.godot` (used by exports)
4. `http://127.0.0.1:8000` (local dev, default)

**For collaborators:** clone the repo, create `backend_url.cfg` with the
deployed URL, run the game from the editor - no build needed. Both of you can
use the same deployed backend while testing multiplayer. If you run the
backend locally instead, just delete the file (or leave it - delete = localhost).

### Running two instances on one machine (two accounts)

The launcher stores one login token per machine (`user://settings.cfg`), so a
second instance must use its own profile file or both would log in as the
same account:

```sh
# Instance 1: default profile (token A)
game.exe

# Instance 2: profile 2 (token B)
set FPSNITE_PROFILE=2
game.exe
```

or `game.exe --profile 2` (also supports `--profile=2`). Profile 2 reads and
writes `user://settings_2.cfg` - its own token, name, skin and graphics - so
paste token B in its launcher once. Works the same in the editor (set the env
var before launching the second editor instance).

In the Godot editor there is an even easier way: **Debug > Run Multiple
Instances** opens a window where each instance can carry its own command-line
arguments - give the second instance `--profile 2` and press Run. The profile
scan accepts the arg in any form (`--profile 2`, `--profile=2`, env var
`FPSNITE_PROFILE=2`), no matter how Godot forwards it.

Before exporting the build your friend runs, set:

```ini
[network]

backend_url="https://<your-service>.onrender.com"
```

in `project.godot` (keep `http://127.0.0.1:8000` for local dev).

## 4. Discord bot (optional, runs alongside the API)

The bot runs **inside the API process** (FastAPI lifespan, `bot/runner.py`) -
no extra service needed. `python -m bot` still works as a standalone too.

To enable it:

1. Create the bot at https://discord.com/developers -> New Application ->
   Bot -> copy the token. Enable the **Message Content intent** if the bot
   needs it.
2. Render dashboard -> your service -> **Environment** -> add
   `DISCORD_BOT_TOKEN` = your token -> **Save changes** -> **Deploy**
   (the blueprint's `DISCORD_BOT_TOKEN` entry with `sync: false` exists for
   exactly this - set it manually, never commit it).
3. On boot the logs show `Discord bot started as background task` and
   `Logged in as <bot>`. Without a token the API logs
   `DISCORD_BOT_TOKEN not set - Discord bot disabled` and just serves the API.

Keep the service on **one worker** (Render's default `WEB_CONCURRENCY=1`):
multiple uvicorn workers would each try to log in with the same token.

## 5. Give your friend a login token

The launcher needs a bearer token. The Discord bot is optional - generate one
manually from the deployed API:

- Open `https://<your-service>.onrender.com/docs`
- `POST /api/auth/register` with `{"name": "friendname", "password": "something"}`
- `POST /api/auth/token` with the same body - copy the `token` value
- Your friend pastes it into the launcher's token field once; it is stored
  afterwards and validated on every launch

(or, without the UI: `curl -X POST <url>/api/auth/token -H "Content-Type: application/json" -d '{"name":"...","password":"..."}'`)

## Free-tier gotchas

- **Cold starts:** a free service sleeps after ~15 min of inactivity and takes
  ~30-60 s to wake. The first request after idle will be slow.
- **SQLite resets on redeploy:** free instances have ephemeral disks. Accounts
  survive until the next deploy. If you want persistent data, create a free
  Neon Postgres database and set `DATABASE_URL` to its connection string
  (works without code changes - SQLAlchemy + Alembic handle it).
- **CORS `*`:** fine for the Godot desktop client; if you ever export to web,
  set `CORS_ORIGINS` to your web origin instead.
- Rate limits are generous; this is fine for a friend test.