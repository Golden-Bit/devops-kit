# openFGA-setup

## Panoramica

`openFGA-setup` è un repository infrastrutturale orientato alle operation per distribuire **OpenFGA** su host Ubuntu/EC2 tramite **Docker Compose**, con **PostgreSQL** come datastore persistente, autenticazione tramite **preshared key**, esposizione opzionale via **Nginx** e avvio automatico via **systemd**.

Non è un repository applicativo: contiene configurazioni, script shell, file di esempio per chiamate API, documentazione architetturale e script di gestione operativa.

## Cosa fa il repository

Il repository serve a:

- avviare uno stack OpenFGA completo con database PostgreSQL;
- eseguire automaticamente la migrazione iniziale del datastore;
- esporre l’API OpenFGA in locale su loopback per un deployment più sicuro;
- permettere bootstrap e smoke test delle API tramite script `curl`;
- salvare artefatti runtime e ID generati in `.runtime/`;
- eseguire backup e restore del database PostgreSQL;
- integrare opzionalmente Nginx e systemd per deploy host-level.

## Struttura del repository

### File principali in root

- `README.md`
- `docker-compose.yml`
- `.env.example`
- `.gitignore`
- `LICENSE`

### Documentazione

- `docs/01-architecture.md`
- `docs/02-authorization-model.md`
- `docs/03-bootstrap-profiles.md`
- `docs/04-production-hardening.md`

### Script operativi

- `scripts/00-bootstrap.sh`
- `scripts/bootstrap_configs.sh`
- `scripts/openfga_bootstrap.py`
- `scripts/up.sh`
- `scripts/update.sh`
- `scripts/down.sh`
- `scripts/status.sh`
- `scripts/logs.sh`
- `scripts/healthcheck.sh`
- `scripts/create_store.sh`
- `scripts/write_model.sh`
- `scripts/write_tuples.sh`
- `scripts/check.sh`
- `scripts/list_objects.sh`
- `scripts/backup_postgres.sh`
- `scripts/restore_postgres.sh`

### Configurazioni infrastrutturali

- `nginx/openfga.conf`
- `systemd/openfga-compose.service`

### File di esempio API

- `examples/model.json`
- `examples/tuples.json`
- `examples/check.json`
- `examples/listobjects.json`

### Assenze rilevanti

Nel repository non risultano presenti:

- `Dockerfile` custom;
- workflow CI/CD (`.github/workflows`, GitLab CI, Jenkinsfile, Azure Pipelines);
- script Windows/PowerShell;
- manifest applicativi (`package.json`, `requirements.txt`, `go.mod`, ecc.).

## Architettura e servizi

Il file `docker-compose.yml` definisce tre servizi.

### 1. `postgres`

- immagine: `postgres:17`
- container: `fga-postgres`
- restart policy: `unless-stopped`
- volume persistente: `postgres_data:/var/lib/postgresql/data`
- healthcheck con `pg_isready -U ${POSTGRES_USER}`
- comando custom: `postgres -c 'max_connections=100'`

### 2. `migrate`

- immagine: `openfga/openfga:${OPENFGA_VERSION}`
- container: `fga-migrate`
- esegue la migrazione del datastore con comando `migrate`
- restart policy: `no`
- dipende da `postgres` in stato healthy

### 3. `openfga`

- immagine: `openfga/openfga:${OPENFGA_VERSION}`
- container: `openfga`
- comando: `run`
- dipende da `migrate` completato con successo
- restart policy: `unless-stopped`
- healthcheck con `grpc_health_probe`

### Catena di dipendenze

L’ordine reale di startup è:

`postgres` → `migrate` → `openfga`

## Porte, bind e volumi

### Bind host/container

- `127.0.0.1:8080 -> 8080` per API HTTP OpenFGA
- `127.0.0.1:8081 -> 8081` per gRPC
- `127.0.0.1:3000 -> 3001` per Playground
- `127.0.0.1:2112 -> 2112` per metriche

PostgreSQL non è esposto direttamente verso l’host.

### Volumi

- volume nominato Docker: `postgres_data`

### Sicurezza di rete

Il binding su `127.0.0.1` indica che il deployment è pensato per pubblicare eventualmente il servizio solo tramite un reverse proxy esterno, non direttamente su internet.

## Configurazione ambiente e file `.env`

Il repository non versiona `.env`; fornisce invece `.env.example` come template.

### Variabili presenti in `.env.example`

- `OPENFGA_PUBLIC_HOSTNAME=fga.example.com`
- `POSTGRES_DB=openfga`
- `POSTGRES_USER=openfga`
- `POSTGRES_PASSWORD=CHANGE_ME_STRONG_DB_PASSWORD`
- `OPENFGA_VERSION=v1.11.2`
- `OPENFGA_DATASTORE_ENGINE=postgres`
- `OPENFGA_AUTHN_METHOD=preshared`
- `OPENFGA_AUTHN_PRESHARED_KEYS=CHANGE_ME_TOKEN_1,CHANGE_ME_TOKEN_2`
- `OPENFGA_PLAYGROUND_ENABLED=false`
- `OPENFGA_BOOTSTRAP_APPLY_CONFIGS=false`
- `OPENFGA_BOOTSTRAP_PROFILE=default`
- `OPENFGA_BOOTSTRAP_CONFIG_DIR=config/bootstrap`
- `OPENFGA_BOOTSTRAP_WAIT_SECONDS=120`
- `OPENFGA_BOOTSTRAP_WAIT_INTERVAL=5`
- `OPENFGA_BOOTSTRAP_STATE_FILE=.runtime/bootstrap-state.json`

### Variabili realmente usate dal Compose

Tutte le variabili sopra sono usate dal runtime, ad eccezione di `OPENFGA_PUBLIC_HOSTNAME`, che è principalmente documentativa e utilizzata nel README/processo di pubblicazione, non direttamente iniettata nel Compose.

### Variabili usate dagli script

- `FGA_API_URL`, con default `http://127.0.0.1:8080`
- `FGA_API_TOKEN`, opzionale come fallback
- `OPENFGA_AUTHN_PRESHARED_KEYS`, usata dagli script per derivare automaticamente il token dalla prima chiave disponibile

## Script di automazione

### `scripts/00-bootstrap.sh`

- crea `.env` partendo da `.env.example` se non esiste;
- crea le directory `.runtime/` e `backups/`.

### `scripts/up.sh`

- esegue `docker compose up -d`;
- poi `docker compose ps`;
- se `OPENFGA_BOOTSTRAP_APPLY_CONFIGS=true`, esegue `scripts/bootstrap_configs.sh`.

### `scripts/update.sh`

- esegue `docker compose pull`;
- esegue `docker compose up -d` e `docker compose ps`;
- se `OPENFGA_BOOTSTRAP_APPLY_CONFIGS=true`, esegue `scripts/bootstrap_configs.sh`.

### `scripts/bootstrap_configs.sh`

- wrapper shell per avvio bootstrap configurabile;
- richiede `.env` presente;
- invoca `scripts/openfga_bootstrap.py`.

### `scripts/openfga_bootstrap.py`

- risolve profilo bootstrap da `config/bootstrap/profiles/*.json`;
- in modalità profile-only risolve target e mode esclusivamente dal profilo;
- supporta override one-shot del profilo via CLI (`scripts/bootstrap_configs.sh <profile>`);
- attende health API;
- applica store/model/tuples in modo idempotente secondo modalità configurate;
- esegue check opzionali;
- salva stato in `.runtime/bootstrap-state.json` e summary in `.runtime/bootstrap-summary.json`.

### `scripts/down.sh`

- esegue `docker compose down`.

### `scripts/status.sh`

- esegue `docker compose ps`.

### `scripts/logs.sh`

- mostra i log live di OpenFGA con `docker compose logs -f --tail=200 openfga`.

### `scripts/healthcheck.sh`

- esegue una richiesta `curl` verso `http://127.0.0.1:8080/healthz`.

### `scripts/create_store.sh`

- carica `.env` se presente;
- usa `FGA_API_URL` o il default locale;
- ricava il bearer token dalla prima voce in `OPENFGA_AUTHN_PRESHARED_KEYS`;
- invia `POST /stores`;
- salva la risposta in `.runtime/create_store.json`;
- salva lo `store_id` in `.runtime/store_id`.

### `scripts/write_model.sh`

- richiede `.runtime/store_id`;
- invia `POST /stores/{store_id}/authorization-models` usando `examples/model.json`;
- salva la risposta in `.runtime/write_model.json`;
- salva il model ID in `.runtime/model_id`.

### `scripts/write_tuples.sh`

- richiede `.runtime/store_id`;
- invia `POST /stores/{store_id}/write` usando `examples/tuples.json`;
- salva la risposta in `.runtime/write_tuples.json`.

### `scripts/check.sh`

- richiede `.runtime/store_id`;
- invia `POST /stores/{store_id}/check` usando `examples/check.json`;
- salva la risposta in `.runtime/check.json`.

### `scripts/list_objects.sh`

- richiede `.runtime/store_id`;
- invia `POST /stores/{store_id}/list-objects` usando `examples/listobjects.json`;
- salva la risposta in `.runtime/listobjects.json`.

### `scripts/backup_postgres.sh`

- crea `backups/` se necessario;
- esegue `pg_dump` nel container `fga-postgres`;
- produce un file SQL timestampato in `backups/`.

### `scripts/restore_postgres.sh`

- richiede come argomento il file SQL da ripristinare;
- ferma temporaneamente `openfga`;
- ripristina il dump dentro PostgreSQL tramite `psql`;
- riavvia `openfga`.

## Flussi operativi

### Bootstrap iniziale

1. copiare `.env.example` in `.env`;
2. valorizzare password DB, chiavi preshared e hostname pubblico opzionale;
3. facoltativamente proteggere `.env` con permessi restrittivi;
4. avviare lo stack.

### Avvio stack

Manuale:

- `docker compose pull`
- `docker compose up -d`
- `docker compose ps`

Scriptato:

- `./scripts/up.sh`

### Flusso API di bootstrap e test

Ordine consigliato:

1. `create_store.sh`
2. `write_model.sh`
3. `write_tuples.sh`
4. `check.sh`
5. opzionale `list_objects.sh`

### Flusso bootstrap automatico profile-only

1. impostare in `.env` `OPENFGA_BOOTSTRAP_APPLY_CONFIGS=true`;
2. selezionare `OPENFGA_BOOTSTRAP_PROFILE`;
3. avviare stack con `./scripts/up.sh` oppure `./scripts/update.sh`.

Override one-shot del profilo:

- `./scripts/bootstrap_configs.sh demo-rbac`

Nota: anche con override CLI del profilo, il bootstrap viene eseguito solo se `OPENFGA_BOOTSTRAP_APPLY_CONFIGS=true`.

Struttura configurazioni:

- `config/bootstrap/profiles/`
- `config/bootstrap/stores/`
- `config/bootstrap/models/`
- `config/bootstrap/tuples/`
- `config/bootstrap/checks/`

### Avvio automatico al boot

`systemd/openfga-compose.service` esegue `scripts/up.sh` all’avvio macchina.

Nota importante: il file systemd usa `WorkingDirectory=/opt/openfga`, quindi il deployment atteso è sotto quel path o richiede modifica manuale del service file.

### Pubblicazione via Nginx

`nginx/openfga.conf` fa proxy verso `127.0.0.1:8080` ed è pensato per pubblicare il servizio tramite `80/443`, lasciando OpenFGA non esposto direttamente.

## File di configurazione infrastrutturale

### `nginx/openfga.conf`

- reverse proxy verso `127.0.0.1:8080`;
- `server_name` hardcoded su `fga.example.com`, da adattare;
- pensato per integrazione con TLS/Certbot documentata ma non automatizzata.

### `systemd/openfga-compose.service`

- `Requires=docker.service`
- `After=docker.service`
- `WorkingDirectory=/opt/openfga`
- avvio stack con `scripts/up.sh` (quindi con bootstrap automatico opzionale basato su `.env`)

## Gestione artefatti runtime

Il repository usa directory locali non versionate per i risultati operativi.

- `.runtime/` contiene ID e risposte raw delle API;
- `backups/` contiene i dump SQL;
- entrambe sono ignorate da `.gitignore`.

## Dipendenze reali

### Runtime

- Docker Engine
- Docker Compose plugin
- `postgres:17`
- `openfga/openfga:v1.11.2` come default

### Tool host-side richiamati dagli script o dalla documentazione

- `bash`
- `curl`
- `sed`
- `tee`
- `python3`
- `systemd`
- `nginx`
- `certbot`

## CI/CD e qualità

Nel repository non risultano pipeline CI/CD versionate. Non ci sono workflow GitHub Actions, GitLab CI, Jenkinsfile o altri file di delivery automation.

L’automazione presente è esclusivamente di tipo operativo:

- shell script;
- Docker Compose;
- systemd;
- configurazione Nginx.

## Note operative e punti di attenzione

- Il repository usa immagini upstream, non build custom.
- Gli script API e il bootstrap profile-only usano il primo token definito in `OPENFGA_AUTHN_PRESHARED_KEYS`.
- `OPENFGA_PLAYGROUND_ENABLED` è disabilitato di default, coerente con un assetto più sicuro.
- `backup_postgres.sh` e `restore_postgres.sh` dipendono dal nome container `fga-postgres`.
- Il bootstrap automatico salva stato in `.runtime/bootstrap-state.json` e summary in `.runtime/bootstrap-summary.json`.
- Alcuni documenti interni riportano mapping porte che non coincidono perfettamente con `docker-compose.yml`; per il runtime reale il file autorevole è il Compose.

## Conclusione

`openFGA-setup` è un repository di deploy e gestione operativa per OpenFGA, con un’impostazione chiara: stack minimale, automazione shell, datastore persistente su PostgreSQL, surface area ridotta tramite bind locale e pubblicazione opzionale via reverse proxy.

---

## Orchestrazione centralizzata (root repository)

Da questo ciclo di aggiornamento è disponibile anche un layer centralizzato in root repository:

- `./scripts/up.sh openfga`
- `./scripts/update.sh openfga`
- `./scripts/down.sh openfga`
- `./scripts/healthcheck.sh openfga`
- `./scripts/status.sh openfga`
- `./scripts/nginx-setup.sh openfga`
- `./scripts/tls-setup.sh openfga`

Per i dettagli operativi e la configurazione tramite `.orchestrator.env`, vedi `docs/ORCHESTRATION.md` nel root del repository.
