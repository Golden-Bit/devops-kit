# Dev-Kit Central Orchestration

This repository contains 4 independent infrastructure modules:

- `PostgreSQL-setup`
- `keycloak-setup`
- `minIO-setup`
- `openFGA-setup`

A root-level orchestration layer is now available for centralized operations.

## Quick start

1. Copy orchestrator config:

```bash
cp .orchestrator.env.example .orchestrator.env
```

2. (Optional) enable Nginx/TLS per service in `.orchestrator.env`.

3. Use centralized commands:

```bash
./scripts/up.sh
./scripts/status.sh
./scripts/healthcheck.sh
./scripts/update.sh
./scripts/down.sh
```

## Root scripts

### Lifecycle

- `./scripts/up.sh [all|postgres|keycloak|minio|openfga ...]`
- `./scripts/update.sh [all|postgres|keycloak|minio|openfga ...]`
- `./scripts/down.sh [all|postgres|keycloak|minio|openfga ...]`
- `./scripts/healthcheck.sh [all|postgres|keycloak|minio|openfga ...]`
- `./scripts/status.sh [all|postgres|keycloak|minio|openfga ...]`
- `./scripts/logs.sh <postgres|keycloak|minio|openfga>`

### Nginx / TLS automation

- `./scripts/nginx-setup.sh [all|postgres|keycloak|minio|openfga ...]`
- `./scripts/nginx-disable.sh [all|postgres|keycloak|minio|openfga ...]`
- `./scripts/tls-setup.sh [all|postgres|keycloak|minio|openfga ...]`
- `./scripts/tls-renew-test.sh`
- `./scripts/expose-status.sh`

## Behavior model

- Central scripts **delegate** to each module's own scripts for lifecycle (`up`, `update`, `down`, `healthcheck`, `logs`).
- Root-level script does not replace module logic; it coordinates it.
- `up`/`update` are fail-fast by default (`ORCH_FAIL_FAST=true`).
- `down` attempts all selected modules in reverse order and reports failures at the end.

## Nginx / domain / TLS rules

- Exposure is controlled per service through `.orchestrator.env`.
- If `*_NGINX_ENABLED=false`, the service stays local-only.
- If Nginx is enabled but domain is empty, that service is skipped for Nginx/TLS setup (graceful local-only behavior).
- `tls-setup.sh` runs Certbot only where service/module/nginx/tls flags are all enabled and required domains are set.
- For MinIO, both `MINIO_API_DOMAIN` and `MINIO_CONSOLE_DOMAIN` are required.

## PostgreSQL note

PostgreSQL TLS via Nginx stream remains an advanced/manual step. The orchestrator can set up ACME HTTP helper and certificate issuance if enabled, but stream proxy hardening/configuration remains in module docs:

- `PostgreSQL-setup/nginx/http/pg-acme.conf`
- `PostgreSQL-setup/nginx/stream/pg-stream-tls.conf`

## Docs

- `docs/ORCHESTRATION.md` (centralized orchestration and exposure reference)
- Existing module docs in `docs/README-*.md` remain valid for service-specific behavior.
