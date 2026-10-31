# changedetection.io: why fields keep disappearing

Short version: changedetection.io saves your data fine. The dashboard at ersatzteil-store.ch was open to the internet with no login, and on the version you run (0.55.8), deleting watches is just a link. Anyone, or anything, that opens the right URL removes your data. No form, no confirmation, no password.

This repo is the setup I'd run instead, plus a script that proves it works.

## What I found

**The dashboard was public.** On 31 October, http://ersatzteil-store.ch/ opened the changedetection.io dashboard (version 0.55.8) straight away, with no login. The password field in the settings was empty.

**Strangers were already using it.** The only two watches in it were a LinkedIn profile and a Facebook page, nothing to do with spare parts. There was no watch for the shop. About half an hour later the dashboard suddenly had a login page because someone had set a password. Maybe that was your team, but anyone could have done it.

**On 0.55.8, deleting is a plain link.** I read the source for your version. The Delete button on the edit page is a normal link to `/delete?uuid=<id>`, and the "are you sure?" popup is JavaScript only. The same goes for "pause all", "mute all", "clear history" and deleting groups. I tested it on a clean 0.55.8 without a password, like yours:

```
watches before:                       3
GET /delete?uuid=all  (no login)  ->  302
watches after:                        0
```

One request with no cookies and no token wiped everything. A person can do that, but so can a search engine crawler, a link-preview bot or a security scanner just following links on the page. Bots don't run the JavaScript popup, they just open the URL. Your dashboard page links directly to the pause and mute links, and each watch's edit page links to its Delete link.

**The app itself doesn't lose data.** I checked this too, so we're not chasing the wrong thing:

- Every watch is written to its own `watch.json` the moment it's saved, through a temp file and an atomic rename. Nothing waits in memory.
- The server had been up for almost 7 days, so a restart hadn't wiped anything recently.

So the fields don't disappear by themselves. Something is removing them through the open dashboard.

## What this setup changes

| Problem | Fix |
|---|---|
| No login | Password set through `SALTED_PASS` in the environment. That's changedetection.io's own deployment option. When it's set, the "remove password" button in the UI does nothing, so nobody can switch the login off or lock you out by setting their own. |
| Delete/pause/clear are plain links | Runs **0.60.10**. Since 0.60.x these are POST requests with CSRF protection, so opening a URL can't change anything. I tested `GET /delete?uuid=all` on 0.60.10: 404, nothing deleted. It uses the same data format as 0.55.8 (schema 33), so there's no migration. It also includes the security advisories fixed since 0.55.8. |
| Dashboard on the public shop domain | The app only listens on `127.0.0.1`. Public access goes through your nginx on its own subdomain with HTTPS (`nginx/monitor.ersatzteil-store.ch.conf`). |
| Data could be lost on a rebuild | `/datastore` is on a named volume. The official image doesn't declare one, so without it the data lives inside the container and disappears when the container is recreated, e.g. on an update. |
| No backups | `scripts/backup.sh` and `scripts/restore.sh` |

## Running it

You need Docker with Compose. On Windows, use Git Bash.

```bash
cp .env.example .env
./scripts/set-password.sh       # asks for a password, stores only the hash
docker compose up -d
```

Then open http://localhost:5000. If port 5000 is taken (Windows often reserves it), set `PORT=5080` or similar in `.env`.

## Testing it

```bash
./scripts/check.sh
```

It asks for your password and tests the whole thing against the running app. It checks that the dashboard and settings send you to the login page, that a wrong password fails and the right one works, and that a newly added watch is still there after the containers are thrown away and recreated. This is a real run:

```
Access:
  ok    dashboard redirects anonymous visitors to /login
  ok    settings page is locked too
  ok    wrong password is refused
  ok    correct password logs in
Persistence:
  ok    added test watch https://example.com/?persistence-check=1793469900
  ..    docker compose down && up (containers are destroyed and recreated)
  ok    watch is still there after recreate
```

Delete the example.com test watch afterwards.

## Moving the live server over

1. **Back up what's there now.** Check whether the current container has a volume:
   ```bash
   docker inspect <container> --format '{{json .Mounts}}'
   ```
   Either way, copy the data out:
   ```bash
   docker cp <container>:/datastore ./datastore-old
   tar czf datastore-old.tar.gz -C datastore-old .
   ```
2. **Stop the old container**, then start this one and load the data:
   ```bash
   docker compose up -d
   ./scripts/restore.sh datastore-old.tar.gz
   ```
3. **Set up the subdomain** with `nginx/monitor.ersatzteil-store.ch.conf` and certbot. The steps are at the top of the file. Point `ersatzteil-store.ch` back at the shop.
4. **Nightly backups:**
   ```
   0 3 * * * cd /opt/changedetection && ./scripts/backup.sh
   ```

## Files

```
docker-compose.yml                      changedetection 0.60.10 + the Chrome browser it uses
.env.example                            settings, copied to .env
scripts/set-password.sh                 sets the login password
scripts/check.sh                        end-to-end test: login + data survives a rebuild
scripts/backup.sh, restore.sh           backups of the data volume
nginx/monitor.ersatzteil-store.ch.conf  site config for the nginx on the server
```

## One more thing

The task calls `http://ersatzteil-store.ch/` the site you monitor, but that address is the dashboard itself, so a watch on it would just be watching itself. Once the dashboard has its own subdomain, point the watches at the real shop and product pages.
