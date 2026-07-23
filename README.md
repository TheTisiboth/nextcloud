# Nextcloud on Raspberry Pi 5

Self-hosted Nextcloud NAS stack for a Raspberry Pi 5, deployed via Docker
Compose through [Dokploy](https://dokploy.com/). The app, database, and
cache all run off the Pi's SD card; Nextcloud's user-data directory is
bind-mounted onto a separate USB HDD so file storage isn't limited by SD
card capacity/wear.

**Stack:** Nextcloud (Apache) + PostgreSQL + Redis (object cache + file
locking) + a dedicated cron container for background jobs.

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
  accordingly (e.g. `30-apache`). Don't use a floating tag long-term --
  Nextcloud can't skip major versions on upgrade.

`.env` is git-ignored -- never commit it.

## 4. Deploy via Dokploy

1. Push this repo to GitHub.
2. In Dokploy, create a new **Docker Compose** application pointing at
   the repo, and load your `.env` values into Dokploy's environment
   variables UI for that app.
3. Deploy. Confirm all four services (`db`, `redis`, `nextcloud`, `cron`)
   report healthy in Dokploy/`docker compose ps`.
4. **The bind-mount path must exist with correct ownership on whichever
   physical node Dokploy actually schedules the container on** -- confirm
   that's your Pi, since a bind mount won't materialize the HDD path on a
   different machine.

## 5. First run

Visit `http://<pi-ip>:<APP_PORT>` and log in with the admin credentials
from `.env`. Under Settings → Administration → Overview, confirm there
are no memcache/locking warnings (this verifies Redis is active).

## 6. Enable cron-based background jobs (one-time)

AJAX cron (the default) only runs when someone has the page open. Switch
to real cron, backed by the `cron` service in this stack:

```bash
docker exec -u www-data <nextcloud_container_name> php occ background:job:mode cron
```

(Equivalently: Settings → Administration → Basic settings → "Cron".)
This setting is stored in the database, so it's a one-time step, not
something that needs to run on every deploy. The `cron` container then
runs `/cron.sh`, executing background jobs every ~5 minutes automatically.

## 7. Add a domain + HTTPS via Dokploy

1. In Dokploy's **Domains** tab for this application, add your domain,
   pointing at the `nextcloud` service, container port `80`, with Let's
   Encrypt enabled.
2. **If the domain doesn't route:** some Dokploy versions require its
   internal `dokploy-network` to be explicitly attached to the `nextcloud`
   service in `docker-compose.yml`. This isn't guaranteed to be zero-config
   across all Dokploy releases -- check your version's docs if routing
   fails, and add the network there if needed.
3. Update `NEXTCLOUD_TRUSTED_DOMAINS` in `.env` to include the new domain
   and redeploy -- this one *is* re-applied automatically on every
   container start.
4. Set the reverse-proxy/overwrite config once (these are **not**
   auto-read from environment variables by the Nextcloud image, unlike
   trusted domains):

   ```bash
   docker exec -u www-data <nextcloud_container_name> php occ config:system:set overwriteprotocol --value="https"
   docker exec -u www-data <nextcloud_container_name> php occ config:system:set overwrite.cli.url --value="https://cloud.example.com"
   docker exec -u www-data <nextcloud_container_name> php occ config:system:set overwritehost --value="cloud.example.com"
   docker exec -u www-data <nextcloud_container_name> php occ config:system:set trusted_proxies 0 --value="<dokploy-traefik-network-cidr>"
   ```

   Find the CIDR with `docker network inspect <dokploy-network-name>`.

## 8. Moving to a different disk later

Mount the new disk, `chown -R 33:33` it, stop the stack, copy the data
across, update `NEXTCLOUD_DATA_DIR_HOST` in `.env`, and redeploy. No
`docker-compose.yml` edits are needed -- the data location is entirely
driven by that one variable.
