# Deploying the backend for free (Vercel)

The backend is FastAPI + Postgres (Supabase) and runs on Vercel's free tier as
a serverless function. Photon (Fusion) needs nothing from you - it is already
a cloud service; the app id is baked into the game export.

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

## 2. Create the Vercel project

1. Go to https://vercel.com, sign up (free), then **Add New > Project**
2. Import the `fpsnite-backend` repo
3. Framework preset: **Other**. Root directory: `Backend`
4. Build command: none (the Python runtime builds `api/index.py` via
   `@vercel/python` from `vercel.json`)
5. Install command: `pip install -r requirements.txt` (run automatically by
   the Python runtime; listed here in case you use `vc dev`)
6. Environment variables (Project Settings > Environment Variables):
   - `ENV=production`
   - `DATABASE_URL=<your supabase connection string>` (see below)
   - `CORS_ORIGINS=*`
7. **Deploy**

Wait for the deploy to finish, then open
`https://<your-project>.vercel.app/api/health` - it should return
`{"status": "ok", ...}`. The interactive API docs are at `/docs`.

### Why Vercel is different from Render

- **Serverless, no start command.** There is no `uvicorn` process and no
  `alembic upgrade head` on boot. Run migrations once yourself (step 4).
- **Stateless functions.** The Discord bot cannot run inside Vercel serverless
  functions; run it as a standalone process (step 5) or on a spare machine /
  cron host. `main.py` only starts the bot when `RUN_BOT=true` (default off).
- **Cold starts.** Free functions sleep after inactivity and wake on the next
  request; the first request after idle may be slow.
- **No long-lived connections.** Each request opens its own DB connection via
  the Supabase pooler. Use the **session pooler** (port 5432) connection
  string so Vercel's dynamic IPs are accepted.

## 3. Point the game at the deployed URL

`Scripts/backend.gd` resolves the URL in this order (first match wins):

1. Env var `FPSNITE_BACKEND_URL` (useful for the editor / dev)
2. File `res://backend_url.cfg` in the project root - **gitignored**, so dev
   collaborators can each point the editor at the deployed backend without
   touching tracked files. Create it and put the URL on one line:
   `https://<your-project>.vercel.app`
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

backend_url="https://<your-project>.vercel.app"
```

in `project.godot` (keep `http://127.0.0.1:8000` for local dev).

## 4. Run the database migrations once

Vercel doesn't run migrations on boot. After setting `DATABASE_URL`, apply the
migrations to Supabase once from your machine (needs `psycopg2-binary`, already
in `requirements.txt`):

```sh
cd Backend
python -m alembic upgrade head
```

> `DATABASE_URL` is read from `Backend/.env` for this step. Keep that file out
> of git (`.gitignore` already excludes it).

## 5. Discord bot (optional, standalone)

The bot no longer runs inside the API (serverless = stateless). Run
`python -m bot` anywhere with the `DATABASE_URL` and `DISCORD_BOT_TOKEN` env
vars set - a desktop PC, a spare VPS, or any always-on box. Only one instance
may run (a second would fight for the gateway with the same token).

To enable it:

1. Create the bot at https://discord.com/developers -> New Application ->
   Bot -> copy the token. Enable the **Message Content intent** if the bot
   needs it.
2. Set `DISCORD_BOT_TOKEN` and `DATABASE_URL` in the environment of the host
   running the bot, then start it with `python -m bot`.
3. On boot the logs show `Discord bot started as background task` and
   `Logged in as <bot>`. Without a token the bot logs
   `DISCORD_BOT_TOKEN not set - Discord bot disabled` and exits.

## 6. Give your friend a login token

The launcher needs a bearer token. The Discord bot is optional - generate one
manually from the deployed API:

- Open `https://<your-project>.vercel.app/docs`
- `POST /api/auth/register` with `{"name": "friendname", "password": "something"}`
- `POST /api/auth/token` with the same body - copy the `token` value
- Your friend pastes it into the launcher's token field once; it is stored
  afterwards and validated on every launch

(or, without the UI: `curl -X POST <url>/api/auth/token -H "Content-Type: application/json" -d '{"name":"...","password":"..."}'`)

## Free-tier gotchas

- **Cold starts:** a free function sleeps after ~15 min of inactivity and
  takes a moment to wake. The first request after idle will be slow.
- **Persistent data via Supabase (Postgres):** Vercel functions have ephemeral
  filesystems, so SQLite would reset on every redeploy. Instead, the backend
  uses a hosted Postgres database:

  1. Create a free project at https://supabase.com (don't let it auto-import
     the SQLite data - we start fresh).
  2. Project Settings -> Database -> Connection string -> **URI**, choose
     **Session pooler** (port **5432**). The transaction pooler on 6543 only
     supports short-lived transactions; the session pooler gives SQLAlchemy
     real sessions.
  3. Copy the `postgresql://...` URI. **Note:** the Supabase password is
     percent-encoded in the URL (e.g. `%40` for `@`); keep it exactly as
     shown.
  4. Local dev: put it in `Backend/.env` as `DATABASE_URL=...` and run
     `python -m alembic upgrade head` once.
  5. Vercel: Project Settings -> Environment Variables -> set `DATABASE_URL`
     to the same URI -> redeploy. Never commit it.
  6. `GET /api/health/db` should report `"database": "postgres"`.

  Postgres needs the `psycopg2-binary` driver, already in
  `requirements.txt`. The Alembic migrations run unchanged on Postgres.
- **CORS `*`:** fine for the Godot desktop client; if you ever export to web,
  set `CORS_ORIGINS` to your web origin instead.
- Rate limits are generous; this is fine for a friend test.