# Terra — Installation Guide

Everything in this folder is what you need to run Terra on your own server.
No internet-facing account, no subscription service: the software runs entirely
on your machine and your data never leaves it.

Set-up takes about 20 minutes, most of which is Docker downloading in the
background. You do not need to be a developer to follow this.

---

## 1. What you need before starting

| Requirement | Details |
|---|---|
| **Operating system** | Windows 10/11 (Pro or Home), Windows Server 2019+, or any modern Linux |
| **Docker** | Docker Desktop (Windows/Mac) or Docker Engine (Linux) — free download, see below |
| **Memory** | 8 GB RAM minimum, 16 GB recommended |
| **Disk space** | 20 GB free |
| **Internet** | Needed for the first install only. After that Terra runs offline. |
| **Free ports** | `3000` (the app) and `8000` (its data service) |

### Installing Docker

- **Windows / Mac** — download Docker Desktop from <https://www.docker.com/products/docker-desktop/>, run the installer, restart when asked, then launch Docker Desktop and wait until it says *Engine running*.
- **Linux** — follow <https://docs.docker.com/engine/install/> for your distribution.

> On Windows, Docker Desktop may ask you to enable WSL 2 and prompt for a
> restart. Allow it — Terra will not start otherwise.

To confirm Docker is ready, open PowerShell (Windows) or a terminal (Linux) and run:

```bash
docker --version
```

You should see a version number. If you see "command not found", Docker is not
installed or not started yet.

---

## 2. Copy this folder to the machine

Put the whole folder somewhere permanent, for example `C:\Terra` or
`/opt/terra`. Everything below is run **from inside that folder**.

Open a terminal there:

- **Windows** — open the folder in File Explorer, click the address bar, type `powershell`, press Enter.
- **Linux** — `cd /opt/terra`

---

## 3. Load the Terra software

The two `.tar` files in `images/` are the Terra application and its database
schema. Load them into Docker:

```bash
docker load -i images/absterra-app.tar
```

```bash
docker load -i images/absterra-migrate.tar
```

Each finishes with `Loaded image: ...`. This only has to be done once.

---

## 4. Generate your security keys

Terra needs a unique set of passwords and signing keys. These are generated on
**your** machine and are known only to you — ABS never sees them.

If you have Node.js installed:

```bash
node scripts/gen-supabase-keys.mjs
```

If you do not (most people), run it through Docker instead — nothing to install:

```bash
docker run --rm -v "${PWD}:/w" -w /w node:20-alpine node scripts/gen-supabase-keys.mjs
```

On Windows PowerShell, use `${PWD}` exactly as written above.

This creates a file called `.env.docker`. **Back this file up somewhere safe.**
If you lose it, your existing data cannot be read.

---

## 5. Start Terra

```bash
docker compose --env-file .env.docker up -d
```

The first run downloads supporting components and takes 5–15 minutes depending
on your connection. Subsequent starts take about 30 seconds.

Check everything is running:

```bash
docker compose --env-file .env.docker ps
```

Every service should show `Up`. The `migrate` service is expected to show
`Exited (0)` — it sets up the database once and then stops. That is correct.

---

## 6. Create your first account

A new installation has no users, and self-registration is deliberately
disabled, so the first account is created with this command. Choose your own
password — it is not sent anywhere.

```bash
node scripts/bootstrap-admin.mjs "md@yourcompany.com" "ChooseAStrongPassword"
```

Or through Docker if you do not have Node.js:

```bash
docker run --rm --network host -v "${PWD}:/w" -w /w node:20-alpine node scripts/bootstrap-admin.mjs "md@yourcompany.com" "ChooseAStrongPassword"
```

Use the Managing Director's real email address: approvals for critical actions
are sent there as one-time codes.

You can now sign in at **<http://localhost:3000>**.

---

## 7. Activate your licence

Terra runs in a limited state until it is licensed.

1. Sign in and go to **Admin → Settings → Licence**.
2. Copy the **Deployment fingerprint** shown there — it looks like `00C6-87FA-7BA2-639A-4576-DC8B`.
3. Email it to ABS at the address on your invoice.
4. ABS sends back a licence string.
5. Open `.env.docker` in Notepad and set it:

   ```
   ABS_TERRA_LICENSE=<the string ABS sent you>
   ```

6. Restart:

   ```bash
   docker compose --env-file .env.docker up -d app
   ```

Your licensed features appear immediately. The **Admin → Settings → Licence**
page shows what your plan includes.

---

## 8. Everyday operation

**Stop Terra**

```bash
docker compose --env-file .env.docker stop
```

**Start it again**

```bash
docker compose --env-file .env.docker up -d
```

**Start automatically when the server boots** — nothing to do. Docker restarts
Terra by itself, as long as Docker Desktop is set to start with Windows
(Settings → General → *Start Docker Desktop when you sign in*).

**Back up your data.** This is the one thing you must not skip:

```bash
docker run --rm -v abs-terra_db-data:/data -v "${PWD}:/backup" alpine tar czf /backup/terra-backup.tar.gz /data
```

Copy `terra-backup.tar.gz` and `.env.docker` somewhere off the machine. Together
they are a complete restore point. Do this weekly.

---

## 9. Optional settings

Open `.env.docker` in Notepad to change these, then restart with
`docker compose --env-file .env.docker up -d app`.

| Setting | What it does |
|---|---|
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM` | Outgoing email — needed for notifications, invitations and the Managing Director's one-time codes. Ask your IT team for these. |
| `APP_PORT` | Change `3000` if that port is in use |
| `NEXT_PUBLIC_SITE_URL` | Set this if staff will reach Terra by a server name rather than `localhost` — **contact ABS first**, this also requires a rebuilt application image |

---

## 10. If something goes wrong

**See what happened:**

```bash
docker compose --env-file .env.docker logs app
```

| Symptom | Cause and fix |
|---|---|
| `port is already allocated` | Another program uses port 3000 or 8000. Set `APP_PORT=3100` in `.env.docker` and start again. |
| Browser shows "can't reach this page" | Terra is still starting. Wait a minute, then `docker compose --env-file .env.docker ps` and check for `Up`. |
| `service "migrate" didn't complete successfully` | The database was not ready. Simply run the `up -d` command again — it resumes safely. |
| Licence says "wrong deployment" | The fingerprint changed, usually because `DEPLOYMENT_ID` in `.env.docker` was edited or the machine was rebuilt. Send ABS the new fingerprint. |
| Everything is broken and you want to start over | `docker compose --env-file .env.docker down -v` erases **all data permanently**, then repeat from step 5. Only do this if you have a backup or an empty system. |

---

## Support

Contact ABS at the address on your invoice. Please include:

- your deployment fingerprint (**Admin → Settings → Licence**), and
- the output of `docker compose --env-file .env.docker logs app`.

---

Terra — Powered by Amvelt
