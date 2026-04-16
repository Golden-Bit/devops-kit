# minIO-setup

## Panoramica

`minIO-setup` è un repository operativo per eseguire **MinIO single-node** su Ubuntu/EC2 tramite **Docker Compose**, con bootstrap iniziale via **MinIO Client (`mc`)**, persistenza locale dei dati, backup/restore file-level, pubblicazione opzionale tramite **Nginx + TLS** e avvio automatico via **systemd**.

Il repository non contiene codice applicativo: è un setup infrastrutturale per un object storage S3-compatible pronto per ambienti singola istanza.

## Cosa fa il repository

Il repository serve a:

- avviare MinIO come storage S3-compatible;
- esporre API S3 e Console solo su loopback di default;
- creare bucket iniziali, utente applicativo e policy tramite bootstrap `mc`;
- eseguire backup e restore della data directory;
- aggiornare le immagini e riallineare il container;
- integrare Nginx, TLS e systemd in un deployment host-level.

## Struttura del repository

### File principali

- `README.md`
- `SECURITY.md`
- `docker-compose.yml`
- `.env.example`
- `.gitignore`
- `LICENSE`

### Script operativi

- `scripts/_common.sh`
- `scripts/up.sh`
- `scripts/down.sh`
- `scripts/logs.sh`
- `scripts/healthcheck.sh`
- `scripts/bootstrap.sh`
- `scripts/bootstrap-mc.sh`
- `scripts/docker-entrypoint.sh`
- `scripts/backup_data.sh`
- `scripts/restore_data.sh`
- `scripts/update.sh`
- `scripts/print-endpoints.sh`

### Configurazioni e init

- `nginx/minio-api.conf`
- `nginx/minio-console.conf`
- `systemd/minio-compose.service`
- `config/bootstrap/README.md`
- `config/bootstrap/profiles/default.env`
- `config/bootstrap/profiles/prod.env`
- `config/bootstrap/profiles/readonly-demo.env`
- `init/policies/app-readonly.json`
- `init/policies/app-readwrite.json`
- `init/policies/README.md`

### Documentazione

- `docs/DEPLOYMENT_MODES.md`
- `docs/ENVIRONMENT_VARIABLES.md`
- `docs/OPERATIONS.md`
- `docs/SECURITY.md`
- `docs/TLS_AND_REVERSE_PROXY.md`
- `docs/TROUBLESHOOTING.md`
- `docs/VIRTUAL_HOST_BUCKETS.md`

### Persistenza locale

- `data/.gitkeep`
- `backups/.gitkeep`

### Assenze rilevanti

Non risultano presenti:

- `Dockerfile` custom;
- workflow CI/CD;
- manifest applicativi (`package.json`, `requirements.txt`, ecc.);
- script Windows/PowerShell.

## Architettura e servizi

Il `docker-compose.yml` definisce due servizi.

### 1. `minio`

- immagine: `${MINIO_IMAGE}`
- container name: `minio`
- entrypoint custom: `scripts/docker-entrypoint.sh`
- API S3 sul container port `9000`
- Console sul container port `9001`
- persistenza dati montata da `${DATA_DIR}` a `${MINIO_DATA_DIR}`

### 2. `mc`

- immagine: `${MC_IMAGE}`
- profilo Compose: `tools`
- usato come container operativo per bootstrap e operazioni amministrative;
- monta `./scripts` e `./init` in sola lettura;
- dipende da `minio`.

## Porte, bind e volumi

### Porte host/container

Mapping definiti dal Compose:

- `${MINIO_API_BIND_IP}:${MINIO_API_HOST_PORT}:9000`
- `${MINIO_CONSOLE_BIND_IP}:${MINIO_CONSOLE_HOST_PORT}:9001`

Default nel template:

- `127.0.0.1:9000 -> 9000`
- `127.0.0.1:9001 -> 9001`

### Volumi

Per il servizio `minio`:

- `${DATA_DIR}:${MINIO_DATA_DIR}` per i dati persistenti;
- `./scripts:/opt/minio-setup/scripts:ro` per gli script.

Per il servizio `mc`:

- `./scripts:/opt/minio-setup/scripts:ro`
- `./init:/opt/minio-setup/init:ro`

### Implicazione operativa

La configurazione di default espone MinIO solo localmente; la pubblicazione esterna prevista è tramite Nginx su `80/443`, non con esposizione diretta delle porte `9000` e `9001` verso internet.

## Configurazione ambiente e file `.env`

Il repository si aspetta un `.env` locale non versionato, derivato da `.env.example`.

### Variabili principali presenti in `.env.example`

- `MINIO_IMAGE=minio/minio:RELEASE.2025-09-07T16-13-09Z`
- `MC_IMAGE=minio/mc:RELEASE.2025-07-21T05-28-08Z`
- `MINIO_ROOT_USER=CHANGE_ME_ROOT_USER`
- `MINIO_ROOT_PASSWORD=CHANGE_ME_ROOT_PASSWORD_SUPER_STRONG`
- `MINIO_DATA_DIR=/data`
- `MINIO_REGION_NAME=eu-south-1`
- `TZ=Europe/Rome`
- `MINIO_API_BIND_IP=127.0.0.1`
- `MINIO_API_HOST_PORT=9000`
- `MINIO_CONSOLE_BIND_IP=127.0.0.1`
- `MINIO_CONSOLE_HOST_PORT=9001`
- `MINIO_HEALTHCHECK_HOST=127.0.0.1`
- `MINIO_HEALTHCHECK_SCHEME=http`
- `MINIO_BROWSER_REDIRECT=true`
- `MINIO_BROWSER=on`
- `MINIO_BROWSER_LOGIN_ANIMATION=off`
- `MINIO_BROWSER_SESSION_DURATION=12h`
- `MINIO_PROMETHEUS_AUTH_TYPE=public`
- `MINIO_BOOTSTRAP_APPLY_CONFIGS=false`
- `MINIO_BOOTSTRAP_PROFILE=default`
- `MINIO_BOOTSTRAP_PROFILE_DIR=config/bootstrap/profiles`
- `BACKUP_DIR=./backups`
- `DATA_DIR=./data`

### Variabili bootstrap profiles-only

- `MINIO_BOOTSTRAP_BUCKETS=`
- `MINIO_BOOTSTRAP_ENABLE_VERSIONING=`
- `MINIO_BOOTSTRAP_USER=`
- `MINIO_BOOTSTRAP_USER_PASSWORD=`
- `MINIO_BOOTSTRAP_USER_POLICY=`
- `MINIO_PROFILE_BUCKETS` / `MINIO_PROFILE_ENABLE_VERSIONING` / `MINIO_PROFILE_USER` / `MINIO_PROFILE_USER_PASSWORD` / `MINIO_PROFILE_USER_POLICY` nei file profilo

### Variabili opzionali vuote nel template

- `MINIO_SERVER_URL=`
- `MINIO_BROWSER_REDIRECT_URL=`
- `MINIO_DOMAIN=`
- `MINIO_BOOTSTRAP_BUCKETS=`
- `MINIO_BOOTSTRAP_ENABLE_VERSIONING=`
- `MINIO_BOOTSTRAP_USER=`
- `MINIO_BOOTSTRAP_USER_PASSWORD=`
- `MINIO_BOOTSTRAP_USER_POLICY=`

### Dove vengono usate

- `docker-compose.yml` consuma le variabili runtime del server;
- `scripts/_common.sh` usa host, schema e porta per gli healthcheck;
- `scripts/backup_data.sh` e `scripts/restore_data.sh` usano `BACKUP_DIR` e `DATA_DIR`;
- `scripts/bootstrap-mc.sh` usa root credentials e i valori bootstrap effettivi risolti da `bootstrap.sh`;
- `scripts/docker-entrypoint.sh` tratta `MINIO_SERVER_URL`, `MINIO_BROWSER_REDIRECT_URL` e `MINIO_DOMAIN` come opzionali e le rimuove se vuote.

## Script di automazione

### `scripts/_common.sh`

Libreria comune che fornisce:

- caricamento `.env`;
- wrapper `docker compose`;
- helper log/error;
- funzioni per verificare container e costruire gli endpoint di healthcheck.

### `scripts/up.sh`

- verifica `docker`;
- verifica la presenza di `.env`;
- esegue `docker compose pull`;
- esegue `docker compose up -d minio`;
- mostra `docker compose ps`;
- se `MINIO_BOOTSTRAP_APPLY_CONFIGS=true`, esegue `scripts/bootstrap.sh`.

### `scripts/down.sh`

- esegue `docker compose down`.

### `scripts/logs.sh`

- esegue `docker compose logs -f --tail=200 minio`.

### `scripts/healthcheck.sh`

- effettua richieste `curl` ai due endpoint di liveness/readiness.

### `scripts/bootstrap.sh`

- richiede `docker` e `curl`;
- carica `.env`;
- richiede profilo bootstrap (`MINIO_BOOTSTRAP_PROFILE`);
- calcola valori effettivi con precedenza override `.env` > profilo;
- aspetta la disponibilità di MinIO;
- esegue `docker compose run --rm --no-deps mc /opt/minio-setup/scripts/bootstrap-mc.sh` passando i valori bootstrap effettivi via `-e`.

### `scripts/bootstrap-mc.sh`

È lo script che realizza il bootstrap applicativo vero e proprio:

- verifica `MINIO_ROOT_USER` e `MINIO_ROOT_PASSWORD`;
- configura un alias `mc` verso `http://minio:9000`;
- legge i valori bootstrap effettivi passati da `bootstrap.sh`;
- crea bucket con `mc mb --ignore-existing`;
- abilita versioning se richiesto;
- crea utente applicativo con `mc admin user add` **solo se** sono presenti utente e password bootstrap;
- assegna una policy built-in con `mc admin policy attach` quando viene creato l’utente.

Nota importante: il profilo `default.env` distribuito nel repository è orientato al bootstrap bucket/versioning e non crea un utente applicativo finché non vengono impostati i valori user/password nel profilo o negli override `MINIO_BOOTSTRAP_*`.

### `scripts/docker-entrypoint.sh`

- rimuove dall’environment le variabili opzionali vuote;
- avvia `minio server ... --address ":9000" --console-address ":9001"`.

### `scripts/backup_data.sh`

- ferma temporaneamente MinIO;
- crea un archivio compresso della directory dati con `tar -czf`;
- riavvia MinIO.

### `scripts/restore_data.sh`

- ferma MinIO;
- crea un backup preventivo della situazione corrente;
- svuota la directory dati;
- estrae l’archivio indicato;
- riavvia MinIO.

### `scripts/update.sh`

- esegue `docker compose pull`;
- esegue `docker compose up -d --force-recreate minio`;
- mostra `docker compose ps`;
- se `MINIO_BOOTSTRAP_APPLY_CONFIGS=true`, esegue `scripts/bootstrap.sh`.

### `scripts/print-endpoints.sh`

- stampa in output gli endpoint locali e, se configurati, quelli pubblici.

## Flussi operativi

### Flusso locale standard

1. copiare `.env.example` in `.env`;
2. impostare almeno `MINIO_ROOT_USER` e `MINIO_ROOT_PASSWORD`;
3. eseguire `./scripts/up.sh`;
4. verificare con `./scripts/healthcheck.sh`;
5. stampare gli endpoint con `./scripts/print-endpoints.sh`;
6. opzionalmente lanciare `./scripts/bootstrap.sh`.

### Bootstrap logico

Il bootstrap non è parte del container principale, ma viene eseguito tramite il servizio `mc` lanciato ad hoc. Questo consente di mantenere separata la logica di provisioning applicativo dal runtime MinIO.

### Update

`scripts/update.sh` riallinea l’immagine e ricrea il container MinIO senza introdurre altri servizi.

## File di configurazione infrastrutturale

### `nginx/minio-api.conf`

- pubblica l’endpoint API su `listen 80`;
- `server_name minio.example.com` come placeholder;
- proxy verso `127.0.0.1:9000`;
- disabilita buffering e impone `client_max_body_size 0`.

### `nginx/minio-console.conf`

- pubblica la Console su `listen 80`;
- `server_name console.minio.example.com` come placeholder;
- proxy verso `127.0.0.1:9001`;
- include supporto WebSocket (`Upgrade`, `Connection upgrade`).

### `systemd/minio-compose.service`

- `WorkingDirectory=/opt/minio-setup`
- `ExecStart=/usr/bin/docker compose up -d minio`
- `ExecStop=/usr/bin/docker compose down`

Il percorso `/opt/minio-setup` è hardcoded e va adattato se l’installazione reale usa un’altra directory.

## Policy e init JSON

### `init/policies/app-readonly.json`

Definisce permessi di sola lettura S3:

- `GetBucketLocation`
- `ListBucket`
- `GetObject`

### `init/policies/app-readwrite.json`

Definisce permessi di lettura/scrittura:

- `GetBucketLocation`
- `ListBucket`
- `ListBucketMultipartUploads`
- `GetObject`
- `PutObject`
- `DeleteObject`
- `AbortMultipartUpload`
- `ListMultipartUploadParts`

Nota importante: il bootstrap automatico usa una **policy built-in** definita dal profilo (`MINIO_PROFILE_USER_POLICY`) o da override (`MINIO_BOOTSTRAP_USER_POLICY`). I JSON presenti in `init/policies/` sono esempi o base per personalizzazioni manuali future.

## Dipendenze reali

### Runtime

- Docker Engine
- Docker Compose plugin
- `minio/minio`
- `minio/mc`

### Tool host-side

- `bash`
- `curl`
- `tar`
- `find`
- `rm`
- `nginx`
- `certbot`
- `systemd`
- `rsync` (citato nella documentazione di installazione)

## CI/CD e qualità

Non risultano pipeline CI/CD nel repository.

L’automazione inclusa è esclusivamente operativa:

- shell scripts;
- Docker Compose;
- Nginx;
- systemd;
- comandi Certbot documentati.

## Note operative e punti di attenzione

- Il setup è dichiaratamente **single-node / single-instance**, non ad alta disponibilità.
- Il reverse proxy è il pattern raccomandato per esposizione pubblica.
- `MINIO_BROWSER_REDIRECT_URL` diventa importante dietro proxy per evitare redirect errati della Console.
- `MINIO_DOMAIN` abilita virtual-host buckets ma richiede DNS/TLS coerenti.
- `restore_data.sh` è volutamente distruttivo sulla data directory corrente, anche se effettua un backup preventivo.
- I dati reali e i backup sono protetti da `.gitignore`.

## Conclusione

`minIO-setup` è un repository solido per deploy operativi MinIO single-instance: separa bene runtime, bootstrap amministrativo, backup/restore e pubblicazione host-level, con un modello semplice ma già adatto a casi d’uso reali di object storage interno o applicativo.
- fallisce esplicitamente se mancano profilo o valori bootstrap richiesti.

---

## Orchestrazione centralizzata (root repository)

Da questo ciclo di aggiornamento è disponibile anche un layer centralizzato in root repository:

- `./scripts/up.sh minio`
- `./scripts/update.sh minio`
- `./scripts/down.sh minio`
- `./scripts/healthcheck.sh minio`
- `./scripts/status.sh minio`
- `./scripts/nginx-setup.sh minio`
- `./scripts/tls-setup.sh minio`

Per i dettagli operativi e la configurazione tramite `.orchestrator.env`, vedi `docs/ORCHESTRATION.md` nel root del repository.
