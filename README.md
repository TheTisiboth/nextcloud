# Nextcloud on Raspberry Pi 5

Self-hosted Nextcloud NAS stack for a Raspberry Pi 5, deployed via Docker
Compose through [Dokploy](https://dokploy.com/). The app, database, and
cache all run off the Pi's SD card; Nextcloud's user-data directory is
bind-mounted onto a separate USB HDD so file storage isn't limited by SD
card capacity/wear.

**Stack:** Nextcloud (Apache) + PostgreSQL + Redis (object cache + file
locking) + a dedicated cron container for background jobs.

**How custom config gets applied:** the `config/*.config.php` snippets
are bind-mounted read-only to `/custom-config`
(not directly into Nextcloud's `config/` directory -- a bind mount
sitting there before Nextcloud's own install step runs breaks its
ability to write that directory at all). A `before-starting` hook script
(`hooks/before-starting/apply-custom-config.sh`) copies them into
`/var/www/html/config/` and fixes ownership *after* Nextcloud's own init
has finished, right before Apache starts. From there Nextcloud merges
every `config/*.config.php` file automatically.

## 1. Prerequisites

- Raspberry Pi 5, Raspberry Pi OS (64-bit), Docker + Docker Compose installed
- Dokploy installed and reachable on the Pi
- USB HDD physically connected. **Use a powered USB enclosure/hub** for
  spinning or power-hungry drives -- the Pi 5's USB ports can brown out
  under load, causing random drive disconnects.

## 2. Prepare the USB HDD

Identify the disk (do this carefully -- the next commands are destructive):

```bash
lsblk -f
```

Partition and format as ext4:

```bash
sudo wipefs -a /dev/sda                 # WARNING: erases the disk
sudo parted /dev/sda --script mklabel gpt mkpart primary ext4 0% 100%
sudo mkfs.ext4 -L nascloud /dev/sda1
sudo blkid /dev/sda1                    # copy the UUID printed here
```

Mount it persistently via `/etc/fstab` (using the UUID, not `/dev/sda1`,
since device names can shift). `nofail` keeps the Pi bootable even if the
drive is ever unplugged:

```bash
sudo mkdir -p /mnt/nas-hdd
echo 'UUID=<uuid-from-blkid>  /mnt/nas-hdd  ext4  defaults,nofail,x-systemd.device-timeout=10  0  2' | sudo tee -a /etc/fstab
sudo mount -a
df -h /mnt/nas-hdd                      # confirm it mounted
```

Create the data folder and hand it to the container's `www-data` user
(the official Nextcloud Apache image bakes in uid/gid `33` -- it does not
support PUID/PGID remapping):

```bash
sudo mkdir -p /mnt/nas-hdd/nextcloud-data
sudo chown -R 33:33 /mnt/nas-hdd/nextcloud-data
```

**Choosing which disk Nextcloud stores files on** is just this mount
path -- see step 3's `NEXTCLOUD_DATA_DIR_HOST`. Point it at whichever
mount you want; nothing else in the stack needs to change.

## 3. Configure the repo

```bash
git clone <your-repo-url> nextcloud && cd nextcloud
cp .env.example .env
```

Edit `.env`:
- Set strong, unique passwords for `POSTGRES_PASSWORD`, `REDIS_PASSWORD`,
  `NEXTCLOUD_ADMIN_PASSWORD`.
- Set `NEXTCLOUD_DATA_DIR_HOST=/mnt/nas-hdd/nextcloud-data` (or wherever
  you mounted the HDD).
- Set `APP_PORT` to whatever host port you want Nextcloud reachable on.
- Check [hub.docker.com/_/nextcloud](https://hub.docker.com/_/nextcloud)
  for the current stable major version and set `NEXTCLOUD_IMAGE_TAG`
  accordingly, as a major tag (e.g. `34-apache`) -- never `apache` or
  `latest`, Nextcloud can't skip major versions. See [Updating](#9-updating).
- Fill in the `SMTP_*` / `MAIL_*` block, see [Email](#10-email-gmail-smtp).

`.env` is git-ignored -- never commit it.

## 4. Deploy via Dokploy

1. Push this repo to GitHub.
2. In Dokploy, create a new **Docker Compose** application pointing at
   the repo, and load your `.env` values into Dokploy's environment
   variables UI for that app.
3. In the app's **Compose Path** field, list both compose files so
   Dokploy merges them like `-f docker-compose.yml -f docker-compose.prod.yml`:
   ```
   docker-compose.yml,docker-compose.prod.yml
   ```
   `docker-compose.prod.yml` attaches the `nextcloud` service (only) to
   Dokploy's `dokploy-network` so Traefik can route to it -- it's kept
   separate from the base file so the stack still runs standalone
   (e.g. for local testing) without depending on that external network.
4. Deploy. Confirm all four services (`db`, `redis`, `nextcloud`, `cron`)
   report healthy in Dokploy/`docker compose ps`.
5. **The bind-mount path must exist with correct ownership on whichever
   physical node Dokploy actually schedules the container on** -- confirm
   that's your Pi, since a bind mount won't materialize the HDD path on a
   different machine.

## 5. First run

Visit `http://<pi-ip>:<APP_PORT>` and log in with the admin credentials
from `.env`. Under Settings → Administration → Overview, confirm there
are no memcache/locking warnings (this verifies Redis is active).

## 6. Instance defaults (automatic)

Everything the admin overview's setup checks ask for is applied by the
repo, so a fresh install comes out configured -- no manual `occ` steps:

- `config/system.config.php`: maintenance window (01:00 UTC), default
  phone region (`FR`), server ID.
- `apache/hsts.conf`: `Strict-Transport-Security` header (only honoured by
  browsers over HTTPS, harmless on plain LAN http).
- `hooks/before-starting/configure-instance.sh` (every start, idempotent):
  background jobs mode → `cron` (the `cron` service runs `/cron.sh` every
  ~5 min), and disables `app_api` (ExApps need a Docker deploy daemon we
  don't run).
- `hooks/post-upgrade/repair-mimetypes.sh`: runs the expensive MIME-type
  migrations that `occ upgrade` skips.
- Email: SMTP env vars, see [Email](#10-email-gmail-smtp).

Intentionally left as warnings: 2FA not enforced.

## 7. Add a domain + HTTPS via Dokploy

1. In Dokploy's **Domains** tab for this application, add your domain,
   pointing at the `nextcloud` service, container port `80`, with Let's
   Encrypt enabled. This works out of the box as long as the `Compose
   Path` includes `docker-compose.prod.yml` (step 4) -- that's what
   attaches `nextcloud` to Dokploy's `dokploy-network` so Traefik can
   reach it.
2. In `.env`, set `NEXTCLOUD_TRUSTED_DOMAINS`, `OVERWRITEPROTOCOL=https`,
   `OVERWRITECLIURL=https://<your-domain>`, `OVERWRITEHOST=<your-domain>`,
   and `TRUSTED_PROXIES=<dokploy-network-cidr>` (find the CIDR with
   `docker network inspect dokploy-network | grep Subnet`).
3. Redeploy. All of this is applied automatically -- `NEXTCLOUD_TRUSTED_DOMAINS`
   directly by the Nextcloud image, and the other four via
   `config/proxy.config.php`, which is merged into Nextcloud's config on
   every start. No manual `occ` commands needed.

## 8. Moving to a different disk later

Mount the new disk, `chown -R 33:33` it, stop the stack, copy the data
across, update `NEXTCLOUD_DATA_DIR_HOST` in `.env`, and redeploy. No
`docker-compose.yml` edits are needed -- the data location is entirely
driven by that one variable.

## 9. Updating

The admin UI's web updater is intentionally disabled in the Docker image --
don't enable it. The code in the `nextcloud_html` volume must match the
image version; if the volume gets ahead of the image, the entrypoint
refuses to start. Updates always go through the image: change/pull the
image, redeploy, and the entrypoint runs `occ upgrade` automatically.

Use Dokploy **Deploy**, not **Restart** -- Restart neither recreates the
containers nor pulls a new image.

**Patch/minor (e.g. 34.0.1 → 34.0.4, 34.x):**

1. Back up the DB and config:
   ```bash
   docker exec <db_container> pg_dump -U <POSTGRES_USER> <POSTGRES_DB> > ~/nextcloud-db-backup-$(date +%F).sql
   docker cp <nextcloud_container>:/var/www/html/config ~/nextcloud-config-backup-$(date +%F)
   ```
2. Click **Deploy** in Dokploy. `pull_policy: always` fetches the newest
   image for the major tag (`34-apache`).
3. Verify:
   ```bash
   docker exec -u www-data <nextcloud_container> php occ status
   ```
   Expect the new `versionstring`, `maintenance: false`,
   `needsDbUpgrade: false`.

**Major (e.g. 34 → 35):**

1. Only once Settings → Administration → Overview reports all installed
   apps compatible with the next major.
2. Back up (as above), bump `NEXTCLOUD_IMAGE_TAG` one major at a time
   (`34-apache` → `35-apache`) in Dokploy's environment, Deploy, verify.
3. Repeat for each further major -- never skip one.

## 10. Email (Gmail SMTP)

Nextcloud sends password resets, share notifications and activity mails.
The image's built-in `config/smtp.config.php` reads the `SMTP_*`/`MAIL_*`
env vars at runtime, so mail setup lives in Dokploy's env, not the UI.

**Get an app password:**

1. Google account → Security → turn on **2-Step Verification** (app
   passwords don't exist without it).
2. Open <https://myaccount.google.com/apppasswords> (hidden from the menus;
   unavailable with Advanced Protection or a Workspace admin restriction).
3. Name it `Nextcloud` → Create → copy the 16-char password. It's shown
   only once; drop the spaces.
4. Revoke it from the same page anytime. Changing the Google account
   password revokes all app passwords -- generate a new one and update
   Dokploy.

**Configure:**

1. Dokploy → this app → Environment:
   ```
   SMTP_HOST=smtp.gmail.com
   SMTP_SECURE=ssl
   SMTP_PORT=465
   SMTP_AUTHTYPE=LOGIN
   SMTP_NAME=<you>@gmail.com
   SMTP_PASSWORD=<16-char app password, no spaces>
   MAIL_FROM_ADDRESS=<you>
   MAIL_DOMAIN=gmail.com
   ```
   `MAIL_FROM_ADDRESS` is the local part only.
2. **Deploy** (not Restart -- env changes need the containers recreated).
3. Check it's applied:
   ```bash
   docker exec -u www-data <nextcloud_container> php occ config:list system | grep mail_
   ```
4. Personal settings → set the admin account's email address (the test
   mail goes there).
5. Administration → Basic settings → Email server → **Send email**.

**Troubleshooting:**

- `535 Username and Password not accepted`: wrong/revoked app password,
  or 2-Step Verification off.
- Timeout: outbound 465 blocked -- try `SMTP_SECURE=` (empty, STARTTLS)
  with `SMTP_PORT=587`.
- The sender must be the Gmail account or a verified "Send mail as"
  alias, otherwise Gmail rewrites it.
- Mail settings edited in the UI are overridden while the env vars are set.
- Gmail caps sending at ~500 mails/day.
