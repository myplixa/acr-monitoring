# acr-monitoring

Ansible role that deploys a Grafana + Prometheus + Loki monitoring stack in
Docker, fronted by Caddy (reverse proxy / TLS) and fed by Grafana Alloy
running as a host agent (node/cAdvisor metrics, Docker/journal/file logs).

## Requirements

- Target host: Debian or Ubuntu, with **Docker Engine and the Docker Compose
  plugin already installed and running** (this role deploys the monitoring
  stack on top of Docker — it does not install Docker itself; it fails fast
  with a clear error if `docker` / `docker compose` isn't usable, see
  [tasks/preflight.yml](tasks/preflight.yml))
- Control node: Ansible >= 2.15
- Collections: `community.docker`

## Download

**Option 1 — clone and run standalone**

```bash
git clone git@github.com:myplixa/acr-monitoring.git
cd acr-monitoring
ansible-galaxy collection install -r requirements.yml
```

**Option 2 — pull the role into another project**

Add to that project's `requirements.yml`:

```yaml
roles:
  - name: acr_monitoring
    src: https://github.com/myplixa/acr-monitoring.git
    scm: git
    version: main
```

```bash
ansible-galaxy install -r requirements.yml
```

**Option 3 — run on the target host with `ansible-pull`** (no separate
control node needed):

```bash
ansible-pull -U git@github.com:myplixa/acr-monitoring.git examples/playbook.yml -i localhost,
```

## Run

Edit [examples/inventory.ini](examples/inventory.ini) with your target host,
set the required variables below in [examples/playbook.yml](examples/playbook.yml)
(or your own playbook), then:

```bash
ansible-playbook -i examples/inventory.ini examples/playbook.yml --ask-become-pass
```

## Variables you must set before running

These have insecure or placeholder defaults. The role **refuses to run**
(`ansible.builtin.assert` in [tasks/checks.yml](tasks/checks.yml)) while
they're left at their default, unless you explicitly opt out:

| Variable | Default | Why you need to set it |
|---|---|---|
| `acr_monitoring_domain` | `monitoring.example.local` | Hostname Caddy serves and Prometheus advertises as its external URL. Must resolve to the target host (or be added to `/etc/hosts`) for TLS/reverse-proxy routing to work. |
| `acr_monitoring_grafana_admin_password` | `admin` | Default Grafana admin password — change it, ideally via Ansible Vault. |
| `acr_monitoring_grafana_admin_user` | `admin` | Default Grafana admin username (not enforced, only the password is). |

For a throwaway lab/CI run where you genuinely want the placeholder domain
and/or `admin` password, set `acr_monitoring_allow_insecure_defaults: true`
to bypass both checks.

Example (in your playbook `vars:` or `group_vars`):

```yaml
acr_monitoring_domain: monitoring.mycompany.com
acr_monitoring_grafana_admin_user: admin
acr_monitoring_grafana_admin_password: "{{ vault_grafana_admin_password }}"
```

## Other variables

[defaults/main.yml](defaults/main.yml) holds only bare variable
assignments — this README is the sole reference for what each one does and
when to change it.

### General

| Variable | Default | Description |
|---|---|---|
| `acr_monitoring_base_dir` | `/opt/docker/monitoring` | Stack root directory on the target host |
| `acr_monitoring_timezone` | `Europe/Moscow` | Timezone applied to all containers |
| `acr_monitoring_allow_insecure_defaults` | `false` | Set `true` only to knowingly run with the placeholder domain and/or default Grafana password (e.g. a throwaway lab/CI run) — see [Variables you must set before running](#variables-you-must-set-before-running) |

### Component toggles

| Variable | Default | Description |
|---|---|---|
| `acr_monitoring_install_stack` | `true` | Set `false` on a remote host that should only run the Alloy agent — see [Remote Alloy agent](#remote-alloy-agent-no-local-stack) below |
| `acr_monitoring_enable_caddy` | `true` | Toggle the reverse proxy / TLS termination |
| `acr_monitoring_enable_alloy` | `true` | Toggle installing Grafana Alloy as a host systemd service |
| `acr_monitoring_uninstall_remove_data` | `false` | Only used by the `uninstall` tag — see [Uninstalling](#uninstalling) below |

### Images / versions

| Variable | Default | Description |
|---|---|---|
| `acr_monitoring_grafana_image` | `grafana/grafana` | Grafana container image |
| `acr_monitoring_grafana_version` | `13.1.0` | Grafana image tag |
| `acr_monitoring_prometheus_image` | `prom/prometheus` | Prometheus container image |
| `acr_monitoring_prometheus_version` | `v3.13.0` | Prometheus image tag |
| `acr_monitoring_loki_image` | `grafana/loki` | Loki container image |
| `acr_monitoring_loki_version` | `3.7.3` | Loki image tag |
| `acr_monitoring_caddy_image` | `caddy` | Caddy container image |
| `acr_monitoring_caddy_version` | `2.11.4-alpine` | Caddy image tag |
| `acr_monitoring_alloy_version` | `1.17.1` | Grafana Alloy `.deb` version |
| `acr_monitoring_alloy_arch` | `amd64` | Architecture of the Alloy `.deb` asset downloaded from GitHub Releases — see [Known limitations](#known-limitations) |

### Grafana

| Variable | Default | Description |
|---|---|---|
| `acr_monitoring_grafana_admin_user` | `admin` | Grafana admin username (not enforced by the insecure-defaults check, only the password is) |
| `acr_monitoring_grafana_admin_password` | `admin` | Grafana admin password — change it, ideally via Ansible Vault |
| `acr_monitoring_grafana_uid` / `_gid` | `472` / `472` | uid/gid the Grafana container runs as (matches the upstream image's default) |

### Prometheus

| Variable | Default | Description |
|---|---|---|
| `acr_monitoring_prometheus_retention_time` | `7d` | Prometheus TSDB retention (time) |
| `acr_monitoring_prometheus_retention_size` | `20GB` | Prometheus TSDB retention (size) |
| `acr_monitoring_prometheus_enable_remote_write_receiver` | `true` | Enable Prometheus's remote-write receiver, used by Alloy (local and remote agents) to push metrics |
| `acr_monitoring_prometheus_uid` / `_gid` | `65534` / `65534` | uid/gid the Prometheus container runs as (matches the upstream image's "nobody") |

### Loki

| Variable | Default | Description |
|---|---|---|
| `acr_monitoring_loki_retention_period` | `168h` | Loki log retention |
| `acr_monitoring_loki_uid` / `_gid` | `10001` / `10001` | uid/gid the Loki container runs as |

### Caddy / TLS

| Variable | Default | Description |
|---|---|---|
| `acr_monitoring_caddy_local_certs` | `true` | `true` = Caddy issues a self-signed cert from its own internal CA (browsers will warn). Set `false` for one of two things: if `acr_monitoring_caddy_cert_file`/`_key_file` are also set, Caddy uses that certificate; otherwise it requests one from Let's Encrypt automatically — see below. |
| `acr_monitoring_caddy_cert_file` | `""` | Path, on the Ansible control node, to a certificate (fullchain) file to install and use instead of Let's Encrypt. Only takes effect when `acr_monitoring_caddy_local_certs: false`. Must be set together with `acr_monitoring_caddy_key_file` — the role refuses to deploy if only one is set. |
| `acr_monitoring_caddy_key_file` | `""` | Path, on the Ansible control node, to the private key matching `acr_monitoring_caddy_cert_file`. |

With `acr_monitoring_caddy_local_certs: false` and no cert/key set, `acr_monitoring_domain`
must be a real, publicly resolvable domain pointing at this host, with ports
80/443 reachable from the internet for the ACME challenge. With a cert/key
pair set, the role copies both files to `{{ acr_monitoring_base_dir }}/caddy/certs/`
on the target host (private key at mode `0600`) and points Caddy's `tls`
directive at them — no domain reachability requirement in that case.

### Alloy (host agent)

| Variable | Default | Description |
|---|---|---|
| `acr_monitoring_alloy_run_as_root` | `false` | Set `true` if container names/labels are missing from Docker/cAdvisor metrics. When `false`, Alloy runs as its own systemd user, added to the `docker` group instead. |
| `acr_monitoring_alloy_monitor_docker` | `true` | Set `false` on hosts that don't run Docker at all, to skip the cAdvisor exporter, Docker log source, the alloy-to-docker-group membership, and the Docker images inventory collector below |
| `acr_monitoring_alloy_remote_write_url` | `""` | Empty = write metrics/logs to the local Prometheus/Loki (`127.0.0.1`). Set to a central acr_monitoring stack's base URL (e.g. `https://monitoring.example.local`) to ship this host's data there instead — used together with `acr_monitoring_install_stack: false` to run Alloy standalone on a remote host. |
| `acr_monitoring_alloy_remote_write_insecure_skip_verify` | `false` | Skip TLS verification when shipping to `acr_monitoring_alloy_remote_write_url` (e.g. for a self-signed cert on the central stack) |
| `acr_monitoring_alloy_poligon_label` | `default` | Value of the `poligon` external label attached to every metric/log series shipped by this host — see [vm-monitoring dashboard](https://github.com/myplixa/dashboards-lib/tree/main/vm-monitoring), which filters on it |
| `acr_monitoring_alloy_extra_log_paths` | see below | List of `{path, job}` file-log sources tailed by Alloy, in addition to journal and (if enabled) Docker logs. Default: `/var/log/*.log` (job `system`), `/var/log/apt/*.log` (job `apt`), `/var/log/unattended-upgrades/*.log` (job `unattended-upgrades`). |
| `acr_monitoring_alloy_textfile_dir` | `/var/lib/alloy/textfile` | Directory node exporter's `textfile` collector reads from — feeds the `docker_image_info` metric, see [Docker images inventory](#docker-images-inventory-optional) |
| `acr_monitoring_alloy_docker_images_cron_minute` | `*/5` | Cron schedule (minute field) for the Docker images inventory collector |

### Grafana dashboard provisioning

See [Grafana dashboard provisioning](#grafana-dashboard-provisioning-optional)
below for `acr_monitoring_grafana_dashboards_repo_url` and
`acr_monitoring_grafana_dashboards`.

| Variable | Default | Description |
|---|---|---|
| `acr_monitoring_grafana_datasource_prometheus_uid` | `cfghiuq3ev400b` | Fixed UID of the primary Prometheus datasource provisioned alongside any configured dashboard |
| `acr_monitoring_grafana_datasource_prometheus_alt_uid` | `ef4s443shfcw0a` | Fixed UID of a second Prometheus datasource pointed at the same Prometheus — some dashboards reference this one instead of the primary |
| `acr_monitoring_grafana_datasource_loki_uid` | `cfghiyx26fzlsb` | Fixed UID of the Loki datasource provisioned alongside any configured dashboard |

These three are only provisioned when `acr_monitoring_grafana_dashboards` is
non-empty, and exist so that dashboards referencing these UIDs directly
resolve correctly regardless of Grafana's own auto-generated datasource
UIDs.

## What gets deployed

- **docker-compose stack** at `{{ acr_monitoring_base_dir }}`: Caddy, Grafana, Prometheus, Loki
- **Grafana Alloy** installed on the host (`.deb` package) to scrape node/cAdvisor
  metrics and ship Docker/journal/file logs into the local Prometheus/Loki
  (or a remote endpoint via `acr_monitoring_alloy_remote_write_url`)

## Grafana dashboard provisioning (optional)

Disabled by default (`acr_monitoring_grafana_dashboards: []`). Set it to a
list of dashboard JSON paths to have the role download and auto-provision
them into Grafana on deploy. Each path is relative to
`acr_monitoring_grafana_dashboards_repo_url` (default: the root of
[myplixa/dashboards-lib](https://github.com/myplixa/dashboards-lib), which
keeps one folder per dashboard) and must include that board's folder, so you
can mix dashboards from several different boards in one deploy:

```yaml
acr_monitoring_grafana_dashboards_repo_url: "https://raw.githubusercontent.com/myplixa/dashboards-lib/main"
acr_monitoring_grafana_dashboards:
  - vm-monitoring/dashboards/vm-monitoring.json
  - another-board/dashboards/another-board.json
```

Downloaded files are saved flat (by basename) into Grafana's dashboards
directory, so filenames must be unique across whichever boards you pick.
Point `acr_monitoring_grafana_dashboards_repo_url` at your own repo/CDN to
serve different dashboards entirely. Alongside any configured dashboard, the
role provisions fixed-UID Prometheus/Loki datasources
(`acr_monitoring_grafana_datasource_*_uid` in
[defaults/main.yml](defaults/main.yml)) so dashboards that reference those
UIDs directly resolve correctly regardless of Grafana's own auto-generated
datasource UIDs.

The default [vm-monitoring](https://github.com/myplixa/dashboards-lib/tree/main/vm-monitoring)
dashboard expects a `poligon` label on your metrics/logs (see
`acr_monitoring_alloy_poligon_label`) — it will show no data without it. Its
"Docker All Image" panel additionally needs the Docker images inventory
collector below.

### Docker images inventory (optional)

When `acr_monitoring_alloy_monitor_docker` is `true`, the role also deploys
its bundled collector script ([files/scripts/docker_images_collector.sh](files/scripts/docker_images_collector.sh))
to `/usr/local/bin/docker_images_collector.sh` on every host running Alloy —
not just the Grafana host — and schedules it via cron
(`acr_monitoring_alloy_docker_images_cron_minute`,
default every 5 minutes). It lists every Docker image present on the host —
including ones with no running container — and writes a `docker_image_info`
metric to `acr_monitoring_alloy_textfile_dir`, picked up by Alloy's node
exporter `textfile` collector. This is what feeds the "Docker All Image"
table in the vm-monitoring dashboard; cAdvisor alone only sees images
belonging to currently running containers.

## Remote Alloy agent (no local stack)

To monitor other hosts without deploying a full Docker stack on each of
them, run the role against those hosts with `acr_monitoring_install_stack:
false` — only Grafana Alloy gets installed, shipping its data to a central
acr_monitoring deployment over the network:

```yaml
acr_monitoring_install_stack: false
acr_monitoring_enable_alloy: true
acr_monitoring_alloy_remote_write_url: "https://monitoring.example.local"
acr_monitoring_alloy_monitor_docker: true  # false if this host has no Docker at all
```

See [examples/playbook-agent.yml](examples/playbook-agent.yml) and
[examples/inventory-agent.ini](examples/inventory-agent.ini). The central
stack must be reachable from the agent host over HTTPS on the domain in
`acr_monitoring_alloy_remote_write_url` (Caddy proxies `/prometheus/*` and
`/loki/*` to the internal Prometheus/Loki containers for exactly this use
case).

## Known limitations

- **Alloy install is amd64-only.** `tasks/alloy.yml` downloads a fixed
  `.deb` asset from GitHub Releases (`acr_monitoring_alloy_arch: amd64` in
  `defaults/main.yml`) rather than adding Grafana's official apt repo. It
  will not work as-is on arm64 hosts, and future Alloy upgrades require
  bumping `acr_monitoring_alloy_version` manually rather than `apt upgrade`.
- **Single stack per host.** Container names, host ports (80/443/9090/3100)
  and the `alloy` systemd service are not namespaced, so the role can't
  deploy two independent stacks on the same machine.

## Uninstalling

`tasks/uninstall.yml` is tagged `never, uninstall`, so it's skipped by every
normal run and only executes when explicitly requested:

```bash
ansible-playbook -i examples/inventory.ini examples/playbook.yml --tags uninstall
```

This stops and removes the Alloy service/package/cron job/collector script
(if `acr_monitoring_enable_alloy` is `true`) and the docker compose stack
(if `acr_monitoring_install_stack` is `true`). Data directories
(`acr_monitoring_base_dir` and `/var/lib/alloy`) are left in place unless
you also set `acr_monitoring_uninstall_remove_data: true` — that's
destructive and removes all Grafana/Prometheus/Loki data.

## Structure

```
acr-monitoring/
├── meta/main.yml            # Galaxy metadata
├── requirements.yml         # Collections required by this role
├── defaults/main.yml        # Tunable variables
├── vars/main.yml            # Internal/computed variables
├── tasks/
│   ├── main.yml
│   ├── checks.yml           # Pre-deploy assert checks
│   ├── preflight.yml        # Verify Docker/Compose are present and usable
│   ├── directories.yml      # Stack directory layout & ownership
│   ├── configs.yml          # Render compose file + service configs
│   ├── dashboards.yml       # Provision Grafana datasources + dashboards (optional)
│   ├── deploy.yml           # docker compose up
│   ├── healthcheck.yml      # Wait for Grafana/Prometheus/Loki to become ready
│   ├── alloy.yml            # Host-level Grafana Alloy agent
│   └── uninstall.yml        # Tear down the stack/agent (tags: never, uninstall)
├── handlers/main.yml
├── templates/
│   ├── docker-compose.yml.j2
│   ├── Caddyfile.j2
│   ├── prometheus.yml.j2
│   ├── loki.yml.j2
│   ├── grafana/
│   │   ├── datasources.yml.j2
│   │   └── dashboards.yml.j2
│   └── alloy/
│       ├── config.alloy.j2
│       └── override.conf.j2
├── files/
│   └── scripts/
│       └── docker_images_collector.sh   # Docker images inventory collector, deployed to every Alloy host
└── examples/
    ├── playbook.yml
    ├── inventory.ini
    ├── playbook-agent.yml   # Remote Alloy-only agent (no local stack)
    ├── inventory-agent.ini
    └── requirements.yml     # Example of consuming this role from another repo
```
