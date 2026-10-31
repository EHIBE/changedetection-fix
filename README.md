# changedetection.io: why fields keep disappearing

Short version: changedetection.io itself is saving everything just fine. The problem is that the dashboard at ersatzteil-store.ch has no login, so anyone who has the link can edit or delete watches. That link was sent to a lot of people.

This repo is the setup I'd run instead. Login is enforced at the deployment level, the data sits on a volume that survives container rebuilds, and there's a script that tests both.

## What I found

When I opened http://ersatzteil-store.ch/ on 31 October, I didn't get a shop. I got the changedetection.io dashboard (version 0.55.8), with no password prompt. Settings → General → Password was empty.

There were two watches in it: a LinkedIn profile and a Facebook page. Neither had anything to do with spare parts, and there was no watch for the shop. Somebody had replaced whatever was there before.

About half an hour later the dashboard suddenly had a login page. Someone had set a password. Maybe that was your team, but it could just as easily have been any visitor, because the settings page was open to everyone. That's really the whole problem in one example.

I also wanted to rule out the software losing data on its own, so I read the 0.55.8 source:

- Every watch is written to its own `watch.json` the moment you save it, using a temp file plus an atomic rename (`store/file_saving_datastore.py`). It doesn't sit in memory waiting for a flush, so nothing gets "half saved".
- The server had been up for almost 7 days, so a restart wiping data recently was out as well.

So the fields aren't disappearing on their own. Other people are removing them.

Two things in the source shaped the fix:

1. **`SALTED_PASS`.** You can give changedetection.io its password through an environment variable instead of the settings page. Once that's set, the "remove password" button stops working (`blueprint/settings/__init__.py`). A visitor can't turn it off or lock you out by setting their own.
2. **The official image doesn't declare a volume for `/datastore`.** If the container is started without one, all data lives inside the container and is gone the next time it's recreated, e.g. on an image update. I can't see from the outside how your server is set up, so this repo makes sure that can't happen.

## What's in here

```
docker-compose.yml                    the app + the Chrome browser it's configured for
.env.example                          settings (copied to .env)
scripts/set-password.sh               sets the login password
scripts/check.sh                      tests the login and that data survives a rebuild
scripts/backup.sh, restore.sh         backups of the data volume
nginx/monitor.ersatzteil-store.ch.conf   site config for the nginx already on the server
```

The app only listens on `127.0.0.1:5000`, so it can't be reached directly from the internet. Public traffic goes through nginx with HTTPS.

The version is pinned to 0.55.8, the one you're running now. Upgrades should happen on purpose. Newer versions migrate the data format and keep the old file around for rollback, so jumping between versions can make it look like recent changes vanished.

## Running it

You need Docker with Compose. On Windows, run the scripts in Git Bash or WSL.

```bash
cp .env.example .env
./scripts/set-password.sh       # asks for a password, stores only its hash
docker compose up -d
```

Then open http://localhost:5000 and log in.

## Testing it

```bash
./scripts/check.sh
```

It asks for your password, then:

- checks that the dashboard and settings redirect to the login page when you're not logged in
- checks that a wrong password doesn't get in and the right one does
- adds a real watch, runs `docker compose down` and `up` (which throws the containers away), logs in again and checks the watch is still there

The output should look like this:

```
Access:
  ok    dashboard redirects anonymous visitors to /login
  ok    settings page is locked too
  ok    wrong password is refused
  ok    correct password logs in
Persistence:
  ok    added test watch https://example.com/?persistence-check=...
  ..    docker compose down && up (containers are destroyed and recreated)
  ok    watch is still there after recreate
```

You can also do it by hand. Add a watch, change a few of its fields, run `docker compose down && docker compose up -d`, and it's all still there. Open the site in a private window and you get the login page.

## Moving the live server over

1. **Save the current data.** Find out where it lives:
   ```bash
   docker inspect <container> --format '{{json .Mounts}}'
   ```
   If nothing is mounted on `/datastore`, the data is inside the container. Copy it out before you touch anything:
   ```bash
   docker cp <container>:/datastore ./datastore-old
   tar czf datastore-old.tar.gz -C datastore-old .
   ```
2. **Start this setup**, then load the old data into it:
   ```bash
   docker compose up -d
   ./scripts/restore.sh datastore-old.tar.gz
   ```
3. **Point a subdomain at it.** Use `nginx/monitor.ersatzteil-store.ch.conf` and run certbot. The steps are at the top of the file. Put `ersatzteil-store.ch` back to serving the shop.
4. **Back up nightly**:
   ```
   0 3 * * * cd /opt/changedetection && ./scripts/backup.sh
   ```

## One more thing

The task calls `http://ersatzteil-store.ch/` the site you monitor. Right now that address *is* the monitoring dashboard, so a watch on it would just be watching itself. Once the dashboard moves to its own subdomain, point the watches at the actual shop and product pages you care about.
