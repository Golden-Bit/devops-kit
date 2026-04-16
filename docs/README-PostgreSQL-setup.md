# PostgreSQL-setup

## Panoramica

`PostgreSQL-setup` è un repository infrastrutturale pensato per distribuire e gestire **PostgreSQL** su Ubuntu/EC2 tramite **Docker Compose**, con script per bootstrap, migrazioni, backup/restore, operazioni distruttive controllate, integrazione opzionale con **Nginx stream/TLS** e avvio automatico via **systemd**.

Non contiene codice applicativo: è un toolkit operativo per creare e mantenere database, ruoli, schemi ed evoluzioni SQL in modo ripetibile.

## Cosa fa il repository

Il repository serve a:

- avviare un’istanza PostgreSQL containerizzata;
- inizializzare il cluster al primo avvio;
- creare database, ruoli, schemi ed estensioni tramite configurazioni JSON dichiarative;
- applicare migrazioni SQL versionate con checksum e metadata tracking;
- eseguire backup e restore del database;
- permettere reset di database o dell’intero cluster;
- integrare startup automatico via systemd e pubblicazione protetta via Nginx/TLS.

## Struttura del repository

### File principali

- `README.md`
- `docker-compose.yml`
- `.env.example`

### Script operativi

- `scripts/up.sh`
- `scripts/update.sh`
- `scripts/down.sh`
- `scripts/logs.sh`
- `scripts/healthcheck.sh`
- `scripts/backup.sh`
- `scripts/restore.sh`
- `scripts/bootstrap_databases.sh`
- `scripts/migrate_databases.sh`
- `scripts/remove_database.sh`
- `scripts/remove_schema.sh`
- `scripts/reset_database.sh`
- `scripts/reset_cluster.sh`
- `scripts/lib/postgres_common.sh`
- `scripts/lib/postgres_profiles.sh`

### Bootstrap e migrazioni

- `bootstrap/databases/README.md`
- `bootstrap/databases/template-appdb.json`
- `bootstrap/databases/example-analytics-dev.json`
- `bootstrap/profiles/README.md`
- `bootstrap/profiles/default.json`
- `bootstrap/profiles/analytics-only.json`
- `bootstrap/sql/template-appdb/app/001-schema.sql`
- `bootstrap/sql/example-analytics-dev/app/001-schema.sql`
- `bootstrap/migrations/README.md`
- `bootstrap/migrations/template-appdb/V001__app_add_updated_at.sql`
- `bootstrap/migrations/example-analytics-dev/V001__app_add_project_status.sql`
- `bootstrap/migrations/example-analytics-dev/V002__integration_create_sync_runs.sql`

### Config infrastrutturali

- `init/00-init.sql`
- `systemd/postgres-compose.service`
- `nginx/stream/pg-stream-tls.conf`
- `nginx/http/pg-acme.conf`

### Documentazione

- `docs/BOOTSTRAP_DATABASES.md`
- `docs/MIGRATIONS.md`
- `docs/DESTRUCTIVE_OPERATIONS.md`
- `docs/docker-install.md`
- `docs/exposure-and-tls.md`

### Directory operative

- `backups/`

### Assenze rilevanti

Non sono presenti:

- workflow CI/CD;
- `Dockerfile` custom;
- script Windows;
- file versionati di `postgresql.conf` o `pg_hba.conf`.

## Architettura del runtime

Il `docker-compose.yml` definisce un solo servizio: `postgres`.

### Servizio `postgres`

- immagine: `postgres:16`
- container name: `pg`
- restart policy: `unless-stopped`
- `env_file: .env`
- volume persistente: `pg_data:/var/lib/postgresql/data`
- mount read-only: `./init:/docker-entrypoint-initdb.d:ro`
- healthcheck: `pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}`

## Porte, bind e volumi

### Porte

Il mapping è parametrico:

- `${PG_BIND_IP}:${PG_PORT}:5432`

Default nel template `.env.example`:

- `PG_BIND_IP=127.0.0.1`
- `PG_PORT=5432`

Quindi il comportamento di default è esposizione solo locale su loopback.

### Volumi

- volume Docker nominato: `pg_data`
- mount read-only della directory `init/`

### Effetto operativo

- `pg_data` mantiene lo stato persistente del cluster;
- `init/00-init.sql` viene eseguito solo alla prima inizializzazione del data directory;
- gli script di bootstrap e migrazione gestiscono invece gli aggiornamenti ripetibili post-avvio.

## Configurazione ambiente e file `.env`

Il repository si aspetta un file `.env` locale non versionato, derivato da `.env.example`.

### Variabili presenti in `.env.example`

- `POSTGRES_DB=appdb`
- `POSTGRES_USER=appuser`
- `POSTGRES_PASSWORD=CHANGE_ME_STRONG`
- `PG_PORT=5432`
- `PG_BIND_IP=127.0.0.1`
- `TZ=Europe/Rome`
- `POSTGRES_BOOTSTRAP_APPLY_CONFIGS=false`
- `POSTGRES_BOOTSTRAP_WAIT_SECONDS=120`
- `POSTGRES_BOOTSTRAP_WAIT_INTERVAL=5`
- `POSTGRES_MIGRATIONS_APPLY_CONFIGS=false`
- `POSTGRES_BOOTSTRAP_PROFILE=default`
- `POSTGRES_BOOTSTRAP_PROFILE_DIR=bootstrap/profiles`
- `POSTGRES_BOOTSTRAP_ADMIN_USER=`
- `POSTGRES_BOOTSTRAP_ADMIN_PASSWORD=`
- `POSTGRES_BOOTSTRAP_ADMIN_DATABASE=postgres` (commentata come esempio)

### Variabili opzionali per i sample JSON

- `ANALYTICS_OWNER_PASSWORD`
- `ANALYTICS_APP_PASSWORD`
- `APP_DB_OWNER_PASSWORD`

Queste vengono lette dai file JSON di bootstrap tramite il campo `password_env`.

### Logica reale di fallback

La libreria `scripts/lib/postgres_common.sh` applica questa logica:

- admin user = `POSTGRES_BOOTSTRAP_ADMIN_USER` oppure `POSTGRES_USER`;
- admin password = `POSTGRES_BOOTSTRAP_ADMIN_PASSWORD` oppure `POSTGRES_PASSWORD`;
- admin database = `POSTGRES_BOOTSTRAP_ADMIN_DATABASE` oppure `postgres`.

## Script di automazione

### `scripts/up.sh`

- esegue `docker compose pull`;
- esegue `docker compose up -d`;
- esegue `docker compose ps`;
- se `POSTGRES_BOOTSTRAP_APPLY_CONFIGS=true`, avvia `bootstrap_databases.sh`;
- se `POSTGRES_MIGRATIONS_APPLY_CONFIGS=true`, avvia `migrate_databases.sh`.

La selezione target è profile-only e dipende dal profilo attivo, scelto tramite argomento CLI (`[profile]`) oppure `POSTGRES_BOOTSTRAP_PROFILE`.

### `scripts/update.sh`

- pull delle immagini;
- riallineamento stack con `docker compose up -d`;
- esecuzione opzionale di bootstrap e migrazioni.

### `scripts/down.sh`

- esegue `docker compose down`.

### `scripts/logs.sh`

- esegue `docker compose logs -f --tail=200`.

### `scripts/healthcheck.sh`

Esegue tre verifiche:

- stato container tramite `docker inspect`;
- readiness con `pg_isready`;
- query smoke test `select now();` tramite `psql`.

### `scripts/backup.sh`

- crea `backups/`;
- esegue `pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"` nel container;
- comprime l’output in `backups/pg_<timestamp>.sql.gz`.

Nota: il backup riguarda il database `POSTGRES_DB`, non l’intero cluster.

### `scripts/restore.sh <file.sql.gz>`

- richiede conferma esplicita `RESTORE`;
- termina le connessioni al DB target;
- esegue `DROP DATABASE IF EXISTS`;
- ricrea il database;
- ripristina il dump compresso via `zcat | psql`.

### `scripts/bootstrap_databases.sh [profile]`

Script dichiarativo e idempotente che:

- aspetta che PostgreSQL sia ready;
- risolve i file target dal profilo (`bootstrap_files` o `bootstrap_target`);
- crea ruoli mancanti;
- crea database mancanti;
- crea schemi;
- crea estensioni;
- applica SQL iniziale se necessario.

La modalità bootstrap è risolta dal profilo (`bootstrap_mode`) con default `upsert`.

### `scripts/migrate_databases.sh [profile]`

Motore migrazioni che:

- aspetta readiness;
- risolve le configurazioni dal profilo (`migration_files` o `migrations_target`);
- individua directory migrazioni;
- applica file `VNNN__descrizione.sql` in ordine;
- salva checksum e stato in tabella metadata.

Supporta modalità `migrations_mode` dal profilo:

- `apply_pending`
- `skip`
- `require_clean`

### `scripts/remove_database.sh <database_name>`

- richiede conferma `REMOVE_DATABASE`;
- termina le connessioni;
- esegue `DROP DATABASE`.

### `scripts/remove_schema.sh <database_name> <schema_name>`

- richiede conferma `REMOVE_SCHEMA`;
- esegue `DROP SCHEMA ... CASCADE`.

### `scripts/reset_database.sh <bootstrap-config.json>`

- legge il nome DB dal JSON;
- richiede conferma `RESET_DATABASE`;
- elimina e ricrea il database usando poi bootstrap e migrazioni.

### `scripts/reset_cluster.sh`

- richiede conferma `RESET_CLUSTER`;
- esegue `docker compose down -v --remove-orphans`;
- ricrea il cluster da zero con `docker compose up -d`;
- rilancia opzionalmente bootstrap e migrazioni.

### `scripts/lib/postgres_common.sh`

È la libreria condivisa per:

- caricamento `.env`;
- fallback credenziali admin;
- wrapper `docker compose exec`;
- helper SQL escaping;
- wait loop con `pg_isready`;
- controllo esistenza ruoli/database/schema;
- create role/database/schema/extension;
- terminazione connessioni attive.

## Flussi operativi

### Primo avvio del cluster

Con volume vuoto:

1. il container inizializza `pg_data`;
2. esegue `init/00-init.sql`;
3. poi gli script di bootstrap/migrazioni possono applicare logica dichiarativa ulteriore.

Nota: `init/00-init.sql` attualmente contiene solo commenti/esempi, quindi non introduce oggetti reali significativi.

### Bootstrap ripetibile

Il repository separa chiaramente:

- inizializzazione one-shot dell’immagine ufficiale (`init/`);
- bootstrap dichiarativo post-avvio (`bootstrap_databases.sh`);
- migrazioni versionate (`migrate_databases.sh`).

Questo consente di usare il repository non solo per creare il cluster, ma anche per mantenerlo nel tempo.

### Avvio automatico via systemd

`systemd/postgres-compose.service` usa:

- `WorkingDirectory=/opt/postgres`
- `ExecStart=/usr/bin/docker compose up -d`
- `ExecStop=/usr/bin/docker compose down`

Il path `/opt/postgres` è hardcoded e va adattato se il deploy avviene altrove.

## Bootstrap dichiarativo: file JSON trovati

### `bootstrap/databases/example-analytics-dev.json`

Definisce:

- database `analytics_dev`;
- owner `analytics_owner`;
- ruolo applicativo `analytics_app`;
- schema `app` con SQL iniziale;
- schema `integration`;
- estensioni `pgcrypto` e `uuid-ossp`;
- migrazioni abilitate in `bootstrap/migrations/example-analytics-dev`.

### `bootstrap/databases/template-appdb.json`

È un template generico per nuovi database applicativi e mostra la struttura minima attesa:

- nome database;
- owner;
- ruoli;
- schemi;
- estensioni;
- SQL iniziale;
- directory migrazioni.

## Migrazioni trovate

### Migrazioni esempio analytics

- `V001__app_add_project_status.sql`
- `V002__integration_create_sync_runs.sql`

### Migrazione template

- `V001__app_add_updated_at.sql`

Le migrazioni vengono registrate in tabelle metadata con checksum, così da evitare riesecuzioni non volute.

## Configurazioni infrastrutturali

### `nginx/stream/pg-stream-tls.conf`

Configurazione Nginx stream per pubblicare PostgreSQL con TLS davanti al bind locale.

### `nginx/http/pg-acme.conf`

Configurazione HTTP per challenge ACME/Let’s Encrypt.

### `init/00-init.sql`

Script eseguito dalla entrypoint ufficiale di Postgres al primo bootstrap del volume. Nel repository attuale funge soprattutto da esempio/base iniziale.

## Dipendenze reali

### Runtime

- Docker Engine
- Docker Compose plugin
- `postgres:16`

### Tool host-side richiesti dagli script

- `bash`
- `docker`
- `python3`
- `sha256sum`
- `gzip`
- `zcat`
- `curl`

### Dipendenze opzionali

- `systemd`
- `nginx`
- `certbot`

## CI/CD e qualità

Non risultano pipeline CI/CD versionate nel repository.

L’automazione presente è di tipo operativo e amministrativo:

- shell scripts;
- Docker Compose;
- unità systemd;
- configurazioni Nginx;
- documentazione procedurale.

## Note operative e punti di attenzione

- Molti script assumono il container name `pg`; cambiarlo impatta i flussi.
- Il repository usa un solo container PostgreSQL: Nginx non fa parte dello stack Compose.
- `reset_cluster.sh` è altamente distruttivo perché rimuove anche il volume dati.
- `backup.sh` non fa backup cluster-wide ma del solo database target.
- Non ci sono file repository-managed per `pg_hba.conf` o `postgresql.conf`; eventuali hardening avanzati restano fuori da questo repository.

## Conclusione

`PostgreSQL-setup` è un repository pensato per la gestione strutturata del ciclo di vita di PostgreSQL: provisioning, bootstrap, migrazioni, backup, reset e integrazione host-level. È particolarmente utile quando si vuole mantenere una base dichiarativa e ripetibile per più database o ambienti sullo stesso stack PostgreSQL.

---

## Orchestrazione centralizzata (root repository)

Da questo ciclo di aggiornamento è disponibile anche un layer centralizzato in root repository:

- `./scripts/up.sh postgres`
- `./scripts/update.sh postgres`
- `./scripts/down.sh postgres`
- `./scripts/healthcheck.sh postgres`
- `./scripts/status.sh postgres`
- `./scripts/nginx-setup.sh postgres` (helper ACME HTTP)
- `./scripts/tls-setup.sh postgres` (certificato; stream TLS resta avanzato/manuale)

Per i dettagli operativi e la configurazione tramite `.orchestrator.env`, vedi `docs/ORCHESTRATION.md` nel root del repository.
