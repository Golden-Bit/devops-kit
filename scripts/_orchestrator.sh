#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ORCH_ENV_FILE="${ROOT_DIR}/.orchestrator.env"

MODULE_IDS=(postgres keycloak minio openfga)

module_dir() {
  case "$1" in
    postgres) echo "PostgreSQL-setup" ;;
    keycloak) echo "keycloak-setup" ;;
    minio) echo "minIO-setup" ;;
    openfga) echo "openFGA-setup" ;;
    *) return 1 ;;
  esac
}

module_label() {
  case "$1" in
    postgres) echo "PostgreSQL" ;;
    keycloak) echo "Keycloak" ;;
    minio) echo "MinIO" ;;
    openfga) echo "OpenFGA" ;;
    *) echo "$1" ;;
  esac
}

module_enabled_var() {
  case "$1" in
    postgres) echo "POSTGRES_ENABLED" ;;
    keycloak) echo "KEYCLOAK_ENABLED" ;;
    minio) echo "MINIO_ENABLED" ;;
    openfga) echo "OPENFGA_ENABLED" ;;
    *) return 1 ;;
  esac
}

module_nginx_enabled_var() {
  case "$1" in
    postgres) echo "POSTGRES_NGINX_ACME_ENABLED" ;;
    keycloak) echo "KEYCLOAK_NGINX_ENABLED" ;;
    minio) echo "MINIO_NGINX_ENABLED" ;;
    openfga) echo "OPENFGA_NGINX_ENABLED" ;;
    *) return 1 ;;
  esac
}

module_tls_enabled_var() {
  case "$1" in
    postgres) echo "POSTGRES_STREAM_TLS_ENABLED" ;;
    keycloak) echo "KEYCLOAK_TLS_ENABLED" ;;
    minio) echo "MINIO_TLS_ENABLED" ;;
    openfga) echo "OPENFGA_TLS_ENABLED" ;;
    *) return 1 ;;
  esac
}

set_defaults() {
  ORCH_FAIL_FAST="${ORCH_FAIL_FAST:-true}"
  ORCH_AUTO_HEALTHCHECK="${ORCH_AUTO_HEALTHCHECK:-true}"
  ORCH_LOG_TAIL="${ORCH_LOG_TAIL:-200}"
  ORCH_DEFAULT_MODULES="${ORCH_DEFAULT_MODULES:-all}"
  ORCH_AUTO_INSTALL_PACKAGES="${ORCH_AUTO_INSTALL_PACKAGES:-false}"
  ORCH_ENABLE_CERTBOT_TIMER="${ORCH_ENABLE_CERTBOT_TIMER:-true}"

  POSTGRES_ENABLED="${POSTGRES_ENABLED:-true}"
  KEYCLOAK_ENABLED="${KEYCLOAK_ENABLED:-true}"
  MINIO_ENABLED="${MINIO_ENABLED:-true}"
  OPENFGA_ENABLED="${OPENFGA_ENABLED:-true}"

  POSTGRES_NGINX_ACME_ENABLED="${POSTGRES_NGINX_ACME_ENABLED:-false}"
  KEYCLOAK_NGINX_ENABLED="${KEYCLOAK_NGINX_ENABLED:-false}"
  MINIO_NGINX_ENABLED="${MINIO_NGINX_ENABLED:-false}"
  OPENFGA_NGINX_ENABLED="${OPENFGA_NGINX_ENABLED:-false}"

  POSTGRES_STREAM_TLS_ENABLED="${POSTGRES_STREAM_TLS_ENABLED:-false}"
  KEYCLOAK_TLS_ENABLED="${KEYCLOAK_TLS_ENABLED:-false}"
  MINIO_TLS_ENABLED="${MINIO_TLS_ENABLED:-false}"
  OPENFGA_TLS_ENABLED="${OPENFGA_TLS_ENABLED:-false}"

  POSTGRES_DOMAIN="${POSTGRES_DOMAIN:-}"
  KEYCLOAK_DOMAIN="${KEYCLOAK_DOMAIN:-}"
  OPENFGA_DOMAIN="${OPENFGA_DOMAIN:-}"
  MINIO_API_DOMAIN="${MINIO_API_DOMAIN:-}"
  MINIO_CONSOLE_DOMAIN="${MINIO_CONSOLE_DOMAIN:-}"
}

load_orchestrator_env() {
  set_defaults
  if [[ -f "${ORCH_ENV_FILE}" ]]; then
    set -a
    source "${ORCH_ENV_FILE}"
    set +a
    set_defaults
  fi
}

bool_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

module_enabled() {
  local var
  var="$(module_enabled_var "$1")"
  if bool_true "${!var}"; then
    return 0
  fi
  return 1
}

module_nginx_enabled() {
  local var
  var="$(module_nginx_enabled_var "$1")"
  if bool_true "${!var}"; then
    return 0
  fi
  return 1
}

module_tls_enabled() {
  local var
  var="$(module_tls_enabled_var "$1")"
  if bool_true "${!var}"; then
    return 0
  fi
  return 1
}

contains_module() {
  local target="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

split_csv() {
  local csv="$1"
  csv="${csv// /}"
  if [[ -z "$csv" ]]; then
    return 0
  fi
  local old_ifs="$IFS"
  IFS=','
  read -r -a _csv_items <<< "$csv"
  IFS="$old_ifs"
  local item
  for item in "${_csv_items[@]}"; do
    if [[ -n "$item" ]]; then
      echo "$item"
    fi
  done
}

resolve_default_modules() {
  local resolved=()
  if [[ "${ORCH_DEFAULT_MODULES}" == "all" ]]; then
    local m
    for m in "${MODULE_IDS[@]}"; do
      if module_enabled "$m"; then
        resolved+=("$m")
      fi
    done
    printf '%s\n' "${resolved[@]}"
    return 0
  fi

  local item
  while IFS= read -r item; do
    if contains_module "$item" "${MODULE_IDS[@]}"; then
      if module_enabled "$item"; then
        resolved+=("$item")
      fi
    fi
  done < <(split_csv "${ORCH_DEFAULT_MODULES}")

  printf '%s\n' "${resolved[@]}"
}

validate_module_id() {
  if contains_module "$1" "${MODULE_IDS[@]}"; then
    return 0
  fi
  echo "Unknown module: $1" >&2
  return 1
}

resolve_modules() {
  local args=("$@")
  local selected=()

  if [[ "${#args[@]}" -eq 0 ]]; then
    while IFS= read -r m; do
      if [[ -n "$m" ]]; then
        selected+=("$m")
      fi
    done < <(resolve_default_modules)
  else
    local a
    for a in "${args[@]}"; do
      if [[ "$a" == "all" ]]; then
        local m
        for m in "${MODULE_IDS[@]}"; do
          if module_enabled "$m"; then
            selected+=("$m")
          fi
        done
      else
        validate_module_id "$a"
        if module_enabled "$a"; then
          selected+=("$a")
        else
          echo "Skipping disabled module: $a" >&2
        fi
      fi
    done
  fi

  if [[ "${#selected[@]}" -eq 0 ]]; then
    echo "No modules selected/enabled." >&2
    return 1
  fi

  printf '%s\n' "${selected[@]}"
}

reverse_modules() {
  local arr=("$@")
  local i
  for (( i=${#arr[@]}-1; i>=0; i-- )); do
    echo "${arr[$i]}"
  done
}

run_in_module() {
  local module="$1"
  local rel_script="$2"
  local module_path
  module_path="${ROOT_DIR}/$(module_dir "$module")"

  if [[ ! -d "$module_path" ]]; then
    echo "Module path not found: $module_path" >&2
    return 1
  fi

  if [[ ! -x "${module_path}/${rel_script}" ]]; then
    echo "Missing executable script ${rel_script} in ${module_path}" >&2
    return 1
  fi

  (
    cd "$module_path"
    "./${rel_script}"
  )
}

run_compose_ps() {
  local module="$1"
  local module_path
  module_path="${ROOT_DIR}/$(module_dir "$module")"

  (
    cd "$module_path"
    docker compose ps
  )
}

run_compose_logs() {
  local module="$1"
  local tail_lines="$2"
  local module_path
  module_path="${ROOT_DIR}/$(module_dir "$module")"

  (
    cd "$module_path"
    docker compose logs --tail "$tail_lines"
  )
}

lifecycle_command_for() {
  case "$1" in
    up) echo "scripts/up.sh" ;;
    update) echo "scripts/update.sh" ;;
    down) echo "scripts/down.sh" ;;
    healthcheck) echo "scripts/healthcheck.sh" ;;
    logs) echo "scripts/logs.sh" ;;
    *) return 1 ;;
  esac
}

summarize_results() {
  local title="$1"
  shift
  local failures=("$@")

  echo
  echo "== ${title} =="
  if [[ "${#failures[@]}" -eq 0 ]]; then
    echo "Result: SUCCESS"
  else
    echo "Result: FAILED (${#failures[@]} module(s))"
    local f
    for f in "${failures[@]}"; do
      echo " - ${f}"
    done
  fi
}

run_lifecycle() {
  local command="$1"
  shift

  load_orchestrator_env

  local modules=()
  while IFS= read -r m; do
    if [[ -n "$m" ]]; then
      modules+=("$m")
    fi
  done < <(resolve_modules "$@")

  local ordered=("${modules[@]}")
  if [[ "$command" == "down" ]]; then
    ordered=()
    while IFS= read -r m; do
      ordered+=("$m")
    done < <(reverse_modules "${modules[@]}")
  fi

  local script
  script="$(lifecycle_command_for "$command")"

  local failures=()
  local module
  for module in "${ordered[@]}"; do
    echo
    echo "--> [$(module_label "$module")] ${command}"
    if ! run_in_module "$module" "$script"; then
      failures+=("$module")
      if [[ "$command" != "down" ]] && bool_true "$ORCH_FAIL_FAST"; then
        summarize_results "${command} summary" "${failures[@]}"
        return 1
      fi
    fi
  done

  summarize_results "${command} summary" "${failures[@]}"

  if [[ "$command" == "up" ]] || [[ "$command" == "update" ]]; then
    if bool_true "$ORCH_AUTO_HEALTHCHECK"; then
      echo
      echo "Auto healthcheck enabled; running healthcheck..."
      if ! run_lifecycle "healthcheck" "${modules[@]}"; then
        return 1
      fi
    fi
  fi

  if [[ "${#failures[@]}" -gt 0 ]]; then
    return 1
  fi
}

run_status() {
  load_orchestrator_env

  local modules=()
  while IFS= read -r m; do
    if [[ -n "$m" ]]; then
      modules+=("$m")
    fi
  done < <(resolve_modules "$@")

  local failures=()
  local module
  for module in "${modules[@]}"; do
    echo
    echo "--> [$(module_label "$module")] status"
    if [[ -x "${ROOT_DIR}/$(module_dir "$module")/scripts/status.sh" ]]; then
      if ! run_in_module "$module" "scripts/status.sh"; then
        failures+=("$module")
      fi
    else
      if ! run_compose_ps "$module"; then
        failures+=("$module")
      fi
    fi
  done

  summarize_results "status summary" "${failures[@]}"
  if [[ "${#failures[@]}" -gt 0 ]]; then
    return 1
  fi
}

run_logs() {
  load_orchestrator_env

  if [[ "$#" -eq 0 ]]; then
    echo "Usage: logs.sh <module>" >&2
    return 1
  fi

  local module="$1"
  validate_module_id "$module"

  if [[ ! -d "${ROOT_DIR}/$(module_dir "$module")" ]]; then
    echo "Module not found: $module" >&2
    return 1
  fi

  echo "--> [$(module_label "$module")] logs"
  if [[ -x "${ROOT_DIR}/$(module_dir "$module")/scripts/logs.sh" ]]; then
    run_in_module "$module" "scripts/logs.sh"
  else
    run_compose_logs "$module" "$ORCH_LOG_TAIL"
  fi
}

require_command() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  echo "Missing required command: $cmd" >&2
  return 1
}

have_sudo() {
  if command -v sudo >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

run_privileged() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
    return
  fi

  if have_sudo; then
    sudo "$@"
    return
  fi

  echo "This operation requires root privileges. Re-run as root or install sudo." >&2
  return 1
}

ensure_packages() {
  local packages=("$@")
  local missing=()
  local pkg
  for pkg in "${packages[@]}"; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    return 0
  fi

  if ! bool_true "$ORCH_AUTO_INSTALL_PACKAGES"; then
    echo "Missing packages/commands: ${missing[*]}" >&2
    echo "Install them manually or set ORCH_AUTO_INSTALL_PACKAGES=true in .orchestrator.env" >&2
    return 1
  fi

  echo "Installing required packages: ${missing[*]}"
  run_privileged apt update

  local apt_pkgs=()
  for pkg in "${missing[@]}"; do
    case "$pkg" in
      nginx) apt_pkgs+=("nginx") ;;
      certbot) apt_pkgs+=("certbot") ;;
      *) ;;
    esac
  done

  if contains_module "certbot" "${missing[@]}"; then
    apt_pkgs+=("python3-certbot-nginx")
  fi

  if [[ "${#apt_pkgs[@]}" -eq 0 ]]; then
    return 1
  fi

  run_privileged apt install -y "${apt_pkgs[@]}"
}

nginx_site_name_for() {
  case "$1" in
    keycloak) echo "dev-kit-keycloak" ;;
    openfga) echo "dev-kit-openfga" ;;
    minio-api) echo "dev-kit-minio-api" ;;
    minio-console) echo "dev-kit-minio-console" ;;
    postgres-acme) echo "dev-kit-postgres-acme" ;;
    *) return 1 ;;
  esac
}

render_nginx_site() {
  local service="$1"
  case "$service" in
    keycloak)
      cat <<'CONF'
server {
    listen 80;
    listen [::]:80;
    server_name __DOMAIN__;

    client_max_body_size 20m;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 180s;
        proxy_send_timeout 180s;
    }
}
CONF
      ;;
    openfga)
      cat <<'CONF'
server {
    listen 80;
    listen [::]:80;
    server_name __DOMAIN__;

    client_max_body_size 10m;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 180s;
        proxy_send_timeout 180s;
    }
}
CONF
      ;;
    minio-api)
      cat <<'CONF'
server {
    listen 80;
    listen [::]:80;
    server_name __DOMAIN__;

    client_max_body_size 0;
    proxy_buffering off;
    proxy_request_buffering off;

    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_http_version 1.1;

        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
CONF
      ;;
    minio-console)
      cat <<'CONF'
server {
    listen 80;
    listen [::]:80;
    server_name __DOMAIN__;

    location / {
        proxy_pass http://127.0.0.1:9001;
        proxy_http_version 1.1;

        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
CONF
      ;;
    postgres-acme)
      cat <<'CONF'
server {
    listen 80;
    listen [::]:80;
    server_name __DOMAIN__;

    location / {
        return 200 "ACME OK\\n";
        add_header Content-Type text/plain;
    }
}
CONF
      ;;
    *)
      return 1
      ;;
  esac
}

install_nginx_site() {
  local service="$1"
  local domain="$2"

  local site_name
  site_name="$(nginx_site_name_for "$service")"

  local rendered
  rendered="$(render_nginx_site "$service")"
  rendered="${rendered//__DOMAIN__/${domain}}"

  local tmp_file
  tmp_file="/tmp/${site_name}.conf"
  printf '%s\n' "$rendered" > "$tmp_file"

  run_privileged mkdir -p /etc/nginx/sites-available
  run_privileged mkdir -p /etc/nginx/sites-enabled
  run_privileged install -m 0644 "$tmp_file" "/etc/nginx/sites-available/${site_name}"
  run_privileged ln -sf "/etc/nginx/sites-available/${site_name}" "/etc/nginx/sites-enabled/${site_name}"
}

remove_nginx_site() {
  local service="$1"
  local site_name
  site_name="$(nginx_site_name_for "$service")"

  run_privileged rm -f "/etc/nginx/sites-enabled/${site_name}"
  run_privileged rm -f "/etc/nginx/sites-available/${site_name}"
}

reload_nginx() {
  run_privileged nginx -t
  run_privileged systemctl reload nginx
}

setup_nginx() {
  load_orchestrator_env
  ensure_packages nginx

  local targets=("$@")
  if [[ "${#targets[@]}" -eq 0 ]]; then
    targets=(all)
  fi

  local services=()
  local t
  for t in "${targets[@]}"; do
    case "$t" in
      all)
        services+=(keycloak openfga minio postgres)
        ;;
      keycloak|openfga|minio|postgres)
        services+=("$t")
        ;;
      *)
        echo "Unknown service for nginx setup: $t" >&2
        return 1
        ;;
    esac
  done

  local processed=()
  local s
  for s in "${services[@]}"; do
    if contains_module "$s" "${processed[@]}"; then
      continue
    fi
    processed+=("$s")

    case "$s" in
      keycloak)
        if ! module_enabled keycloak; then
          echo "Skipping Keycloak (module disabled)"
          continue
        fi
        if ! module_nginx_enabled keycloak; then
          echo "Skipping Keycloak Nginx (disabled in env)"
          continue
        fi
        if [[ -z "$KEYCLOAK_DOMAIN" ]]; then
          echo "Skipping Keycloak Nginx (no KEYCLOAK_DOMAIN configured)"
          continue
        fi
        install_nginx_site keycloak "$KEYCLOAK_DOMAIN"
        echo "Installed Nginx site for Keycloak -> $KEYCLOAK_DOMAIN"
        ;;
      openfga)
        if ! module_enabled openfga; then
          echo "Skipping OpenFGA (module disabled)"
          continue
        fi
        if ! module_nginx_enabled openfga; then
          echo "Skipping OpenFGA Nginx (disabled in env)"
          continue
        fi
        if [[ -z "$OPENFGA_DOMAIN" ]]; then
          echo "Skipping OpenFGA Nginx (no OPENFGA_DOMAIN configured)"
          continue
        fi
        install_nginx_site openfga "$OPENFGA_DOMAIN"
        echo "Installed Nginx site for OpenFGA -> $OPENFGA_DOMAIN"
        ;;
      minio)
        if ! module_enabled minio; then
          echo "Skipping MinIO (module disabled)"
          continue
        fi
        if ! module_nginx_enabled minio; then
          echo "Skipping MinIO Nginx (disabled in env)"
          continue
        fi
        if [[ -z "$MINIO_API_DOMAIN" ]] || [[ -z "$MINIO_CONSOLE_DOMAIN" ]]; then
          echo "Skipping MinIO Nginx (MINIO_API_DOMAIN and MINIO_CONSOLE_DOMAIN are both required)"
          continue
        fi
        install_nginx_site minio-api "$MINIO_API_DOMAIN"
        install_nginx_site minio-console "$MINIO_CONSOLE_DOMAIN"
        echo "Installed Nginx sites for MinIO -> $MINIO_API_DOMAIN, $MINIO_CONSOLE_DOMAIN"
        ;;
      postgres)
        if ! module_enabled postgres; then
          echo "Skipping PostgreSQL (module disabled)"
          continue
        fi
        if ! module_nginx_enabled postgres; then
          echo "Skipping PostgreSQL ACME Nginx helper (disabled in env)"
          continue
        fi
        if [[ -z "$POSTGRES_DOMAIN" ]]; then
          echo "Skipping PostgreSQL ACME helper (no POSTGRES_DOMAIN configured)"
          continue
        fi
        install_nginx_site postgres-acme "$POSTGRES_DOMAIN"
        echo "Installed Nginx ACME helper for PostgreSQL -> $POSTGRES_DOMAIN"
        ;;
    esac
  done

  reload_nginx
}

disable_nginx() {
  load_orchestrator_env
  ensure_packages nginx

  local targets=("$@")
  if [[ "${#targets[@]}" -eq 0 ]]; then
    targets=(all)
  fi

  local t
  for t in "${targets[@]}"; do
    case "$t" in
      all)
        remove_nginx_site keycloak
        remove_nginx_site openfga
        remove_nginx_site minio-api
        remove_nginx_site minio-console
        remove_nginx_site postgres-acme
        ;;
      keycloak)
        remove_nginx_site keycloak
        ;;
      openfga)
        remove_nginx_site openfga
        ;;
      minio)
        remove_nginx_site minio-api
        remove_nginx_site minio-console
        ;;
      postgres)
        remove_nginx_site postgres-acme
        ;;
      *)
        echo "Unknown service for nginx disable: $t" >&2
        return 1
        ;;
    esac
  done

  reload_nginx
}

certbot_domains_for() {
  case "$1" in
    keycloak) echo "$KEYCLOAK_DOMAIN" ;;
    openfga) echo "$OPENFGA_DOMAIN" ;;
    minio)
      if [[ -n "$MINIO_API_DOMAIN" ]] && [[ -n "$MINIO_CONSOLE_DOMAIN" ]]; then
        echo "$MINIO_API_DOMAIN $MINIO_CONSOLE_DOMAIN"
      fi
      ;;
    postgres) echo "$POSTGRES_DOMAIN" ;;
    *) return 1 ;;
  esac
}

run_certbot_for() {
  local service="$1"
  local domains
  domains="$(certbot_domains_for "$service")"

  if [[ -z "$domains" ]]; then
    echo "Skipping TLS for ${service}: missing domain(s)"
    return 0
  fi

  local certbot_args=(--nginx)
  local d
  for d in $domains; do
    certbot_args+=(-d "$d")
  done

  echo "Running certbot for ${service}: ${domains}"
  run_privileged certbot "${certbot_args[@]}"
}

setup_tls() {
  load_orchestrator_env
  ensure_packages nginx certbot

  local targets=("$@")
  if [[ "${#targets[@]}" -eq 0 ]]; then
    targets=(all)
  fi

  setup_nginx "${targets[@]}"

  local services=()
  local t
  for t in "${targets[@]}"; do
    case "$t" in
      all)
        services+=(keycloak openfga minio postgres)
        ;;
      keycloak|openfga|minio|postgres)
        services+=("$t")
        ;;
      *)
        echo "Unknown service for TLS setup: $t" >&2
        return 1
        ;;
    esac
  done

  local done_list=()
  local s
  for s in "${services[@]}"; do
    if contains_module "$s" "${done_list[@]}"; then
      continue
    fi
    done_list+=("$s")

    case "$s" in
      keycloak)
        if module_enabled keycloak && module_nginx_enabled keycloak && module_tls_enabled keycloak; then
          run_certbot_for keycloak
        else
          echo "Skipping Keycloak TLS (module/nginx/tls flag not fully enabled)"
        fi
        ;;
      openfga)
        if module_enabled openfga && module_nginx_enabled openfga && module_tls_enabled openfga; then
          run_certbot_for openfga
        else
          echo "Skipping OpenFGA TLS (module/nginx/tls flag not fully enabled)"
        fi
        ;;
      minio)
        if module_enabled minio && module_nginx_enabled minio && module_tls_enabled minio; then
          run_certbot_for minio
        else
          echo "Skipping MinIO TLS (module/nginx/tls flag not fully enabled)"
        fi
        ;;
      postgres)
        if module_enabled postgres && module_nginx_enabled postgres && module_tls_enabled postgres; then
          run_certbot_for postgres
          if [[ -n "$POSTGRES_DOMAIN" ]]; then
            echo "PostgreSQL TLS stream proxy remains manual/advanced: adapt PostgreSQL-setup/nginx/stream/pg-stream-tls.conf with cert paths."
          fi
        else
          echo "Skipping PostgreSQL TLS (module/nginx/tls flag not fully enabled)"
        fi
        ;;
    esac
  done

  if bool_true "$ORCH_ENABLE_CERTBOT_TIMER"; then
    run_privileged systemctl enable --now certbot.timer
  fi

  renew_tls_dry_run
}

renew_tls_dry_run() {
  load_orchestrator_env
  ensure_packages certbot
  run_privileged certbot renew --dry-run
}

show_exposure_status() {
  load_orchestrator_env

  echo "Orchestrator env file: ${ORCH_ENV_FILE}"
  if [[ -f "$ORCH_ENV_FILE" ]]; then
    echo "Loaded: yes"
  else
    echo "Loaded: no (using defaults)"
  fi

  echo
  echo "Service exposure summary"
  echo "------------------------"

  local site

  site="$(nginx_site_name_for keycloak)"
  echo "Keycloak: enabled=${KEYCLOAK_ENABLED} nginx=${KEYCLOAK_NGINX_ENABLED} tls=${KEYCLOAK_TLS_ENABLED} domain=${KEYCLOAK_DOMAIN:-<none>} site_enabled=$( [[ -L "/etc/nginx/sites-enabled/${site}" ]] && echo yes || echo no )"

  site="$(nginx_site_name_for openfga)"
  echo "OpenFGA : enabled=${OPENFGA_ENABLED} nginx=${OPENFGA_NGINX_ENABLED} tls=${OPENFGA_TLS_ENABLED} domain=${OPENFGA_DOMAIN:-<none>} site_enabled=$( [[ -L "/etc/nginx/sites-enabled/${site}" ]] && echo yes || echo no )"

  local api_site
  local console_site
  api_site="$(nginx_site_name_for minio-api)"
  console_site="$(nginx_site_name_for minio-console)"
  echo "MinIO   : enabled=${MINIO_ENABLED} nginx=${MINIO_NGINX_ENABLED} tls=${MINIO_TLS_ENABLED} api_domain=${MINIO_API_DOMAIN:-<none>} console_domain=${MINIO_CONSOLE_DOMAIN:-<none>} api_site=$( [[ -L "/etc/nginx/sites-enabled/${api_site}" ]] && echo yes || echo no ) console_site=$( [[ -L "/etc/nginx/sites-enabled/${console_site}" ]] && echo yes || echo no )"

  site="$(nginx_site_name_for postgres-acme)"
  echo "Postgres: enabled=${POSTGRES_ENABLED} nginx_acme=${POSTGRES_NGINX_ACME_ENABLED} tls_stream=${POSTGRES_STREAM_TLS_ENABLED} domain=${POSTGRES_DOMAIN:-<none>} acme_site=$( [[ -L "/etc/nginx/sites-enabled/${site}" ]] && echo yes || echo no )"
}

show_help() {
  cat <<'HELP'
Usage: _orchestrator.sh <command> [modules/services...]

Lifecycle commands:
  up [all|postgres|keycloak|minio|openfga ...]
  update [all|postgres|keycloak|minio|openfga ...]
  down [all|postgres|keycloak|minio|openfga ...]
  healthcheck [all|postgres|keycloak|minio|openfga ...]
  status [all|postgres|keycloak|minio|openfga ...]
  logs <postgres|keycloak|minio|openfga>

Nginx/TLS commands:
  nginx-setup [all|postgres|keycloak|minio|openfga ...]
  nginx-disable [all|postgres|keycloak|minio|openfga ...]
  tls-setup [all|postgres|keycloak|minio|openfga ...]
  tls-renew-test
  expose-status
HELP
}

main() {
  local cmd="${1:-help}"
  if [[ "$#" -gt 0 ]]; then
    shift
  fi

  case "$cmd" in
    up|update|down|healthcheck)
      run_lifecycle "$cmd" "$@"
      ;;
    status)
      run_status "$@"
      ;;
    logs)
      run_logs "$@"
      ;;
    nginx-setup)
      setup_nginx "$@"
      ;;
    nginx-disable)
      disable_nginx "$@"
      ;;
    tls-setup)
      setup_tls "$@"
      ;;
    tls-renew-test)
      renew_tls_dry_run
      ;;
    expose-status)
      show_exposure_status
      ;;
    help|-h|--help)
      show_help
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      show_help
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
