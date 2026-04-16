# Central Orchestration and Nginx/TLS Management

This document describes the root-level orchestration scripts and exposure automation introduced in this repository.

## Design goals

- Keep each module authoritative for its own lifecycle behavior.
- Provide a centralized command surface for operators.
- Manage optional Nginx and Certbot setup per service using one orchestrator config.
- Support local-only mode when no domains are configured.

## Orchestrator configuration

Copy:

```bash
cp .orchestrator.env.example .orchestrator.env
```

The orchestrator loads `.orchestrator.env` if present; otherwise defaults from `scripts/_orchestrator.sh` are used.

### Key variables

- Global:
  - `ORCH_FAIL_FAST`
  - `ORCH_AUTO_HEALTHCHECK`
  - `ORCH_LOG_TAIL`
  - `ORCH_DEFAULT_MODULES`
  - `ORCH_AUTO_INSTALL_PACKAGES`
  - `ORCH_ENABLE_CERTBOT_TIMER`
- Module enable flags:
  - `POSTGRES_ENABLED`, `KEYCLOAK_ENABLED`, `MINIO_ENABLED`, `OPENFGA_ENABLED`
- Nginx flags:
  - `POSTGRES_NGINX_ACME_ENABLED`, `KEYCLOAK_NGINX_ENABLED`, `MINIO_NGINX_ENABLED`, `OPENFGA_NGINX_ENABLED`
- TLS flags:
  - `POSTGRES_STREAM_TLS_ENABLED`, `KEYCLOAK_TLS_ENABLED`, `MINIO_TLS_ENABLED`, `OPENFGA_TLS_ENABLED`
- Domains:
  - `POSTGRES_DOMAIN`, `KEYCLOAK_DOMAIN`, `OPENFGA_DOMAIN`, `MINIO_API_DOMAIN`, `MINIO_CONSOLE_DOMAIN`

## Lifecycle commands

```bash
./scripts/up.sh [all|postgres|keycloak|minio|openfga ...]
./scripts/update.sh [all|postgres|keycloak|minio|openfga ...]
./scripts/down.sh [all|postgres|keycloak|minio|openfga ...]
./scripts/healthcheck.sh [all|postgres|keycloak|minio|openfga ...]
./scripts/status.sh [all|postgres|keycloak|minio|openfga ...]
./scripts/logs.sh <postgres|keycloak|minio|openfga>
```

### Execution model

- `up` and `update`: sequential, fail-fast unless disabled.
- `down`: reverse order, best-effort, aggregated summary.
- `status`: uses module `scripts/status.sh` when present, otherwise falls back to `docker compose ps` in module directory.

## Nginx automation

```bash
./scripts/nginx-setup.sh [all|postgres|keycloak|minio|openfga ...]
./scripts/nginx-disable.sh [all|postgres|keycloak|minio|openfga ...]
./scripts/expose-status.sh
```

What it does:

- Creates vhosts under `/etc/nginx/sites-available/` with names:
  - `dev-kit-keycloak`
  - `dev-kit-openfga`
  - `dev-kit-minio-api`
  - `dev-kit-minio-console`
  - `dev-kit-postgres-acme`
- Creates symlinks in `/etc/nginx/sites-enabled/`
- Runs `nginx -t` and reload

### Local-only / no-domain behavior

If a service has Nginx enabled but required domain is empty, orchestrator skips vhost setup for that service and continues. This supports environments where some services remain local-only.

## TLS / Certbot automation

```bash
./scripts/tls-setup.sh [all|postgres|keycloak|minio|openfga ...]
./scripts/tls-renew-test.sh
```

What `tls-setup.sh` does:

1. Ensures Nginx sites are configured for selected services.
2. Runs Certbot (`--nginx`) for services where module/nginx/tls flags are enabled and required domains are present.
3. Enables and starts `certbot.timer` if configured.
4. Runs renewal dry-run test.

## Compatibility notes

- Existing module scripts remain unchanged and continue to be the canonical behavior.
- Root orchestration composes module operations; it does not replace service-specific scripts.
- PostgreSQL stream TLS remains advanced/manual; use module stream config and verify your Nginx build supports stream.

## Security notes

- Do not commit `.orchestrator.env`.
- Keep service secrets in module-specific `.env` files or secret managers.
- Expose only required ports (`80/443`) when using Nginx as reverse proxy.
