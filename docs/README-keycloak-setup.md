# keycloak-setup

## Panoramica

`keycloak-setup` è un repository infrastrutturale per distribuire e gestire **Keycloak self-hosted** su host Ubuntu tramite **Docker Compose**, con **PostgreSQL** come database, **Nginx** come reverse proxy, **systemd** per l’avvio automatico e una **build locale custom** dell’immagine Keycloak che incorpora il tema UI custom `dens-studio`.

Il repository è orientato a **Keycloak** e non contiene codice applicativo: include deploy automation, bootstrap dichiarativo di realm/client, backup/restore, sync verso directory di deploy e personalizzazioni UI.

## Cosa fa il repository

Il repository serve a:

- avviare uno stack composto da **Keycloak + PostgreSQL**;
- costruire localmente un’immagine Keycloak custom a partire dall’immagine ufficiale;
- incorporare nella build il tema custom `dens-studio`;
- mantenere Keycloak esposto solo in locale su `127.0.0.1:8080`, demandando la pubblicazione a Nginx;
- creare o aggiornare realm e client OIDC da file JSON in modo dichiarativo e idempotente;
- eseguire backup e restore del database PostgreSQL;
- sincronizzare la copia sorgente del repository verso una directory di deploy separata;
- automatizzare il riavvio dello stack via systemd.

## Struttura del repository

### File principali in root

- `README.md`
- `docker-compose.yml`
- `Dockerfile`
- `.env.example`
- `.gitignore`
- `LICENSE`

### Script operativi

- `scripts/update.sh`
- `scripts/bootstrap_realms.sh`
- `scripts/backup_db.sh`
- `scripts/restore_db.sh`
- `scripts/healthcheck.sh`
- `scripts/logs.sh`
- `scripts/sync-keycloak-repo.sh`

### Configurazioni realm/client

- `config/realms/README.md`
- `config/realms/realm-a-dev.json`
- `config/realms/realm-b-dev.json`
- `config/bootstrap/README.md`
- `config/bootstrap/profiles/default.json`
- `config/bootstrap/profiles/realm-a-only.json`

### Reverse proxy e startup di sistema

- `nginx/keycloak.conf`
- `systemd/keycloak-compose.service`

### Documentazione operativa interna

- `docs/DEPLOYMENT.md`
- `docs/REPOSITORY_SYNC.md`
- `docs/CUSTOM_UI.md`
- `docs/BACKUP_RESTORE.md`
- `docs/OPERATIONS.md`
- `docs/REALM_BOOTSTRAP.md`
- `docs/SYSTEMD.md`
- `docs/NGINX_TLS.md`
- `docs/SECURITY.md`
- `docs/TROUBLESHOOTING.md`
- `docs/THEMES.md`

### Tema custom incluso nella build

Directory principale:

- `themes/dens-studio/login/`

File rilevanti trovati:

- `theme.properties`
- `template.ftl`
- `login.ftl`
- `register.ftl`
- `register-commons.ftl`
- `register-user-profile.ftl`
- `login-reset-password.ftl`
- `login-update-password.ftl`
- `info.ftl`
- `user-profile-commons.ftl`
- `messages/messages_it.properties`
- `messages/messages_en.properties`
- `resources/css/styles.css`
- `resources/js/app.js`
- `resources/img/icon-brand.svg`
- `resources/img/icon-email.svg`
- `resources/img/icon-lock.svg`

Sono presenti anche file `.bak` nel tema:

- `register.ftl.bak`
- `theme.properties.bak`
- `resources/css/styles.css.bak`

### Directory operative

- `backups/.gitkeep`

### Metadata non operativi

- `.idea/` contiene file IDE e non partecipa al runtime.

## Assenze rilevanti

Nel repository non risultano presenti:

- workflow CI/CD (`.github/workflows`, GitLab CI, Jenkinsfile, Azure Pipelines);
- script Windows / PowerShell (`.bat`, `.cmd`, `.ps1`);
- secret manager integrato;
- file di configurazione PostgreSQL custom come `postgresql.conf` o `pg_hba.conf`;
- altri servizi infra oltre a `postgres` e `keycloak` dentro Compose.

## Architettura del runtime

Il file `docker-compose.yml` definisce **due servizi**.

### 1. `postgres`

- immagine: `postgres:16`
- container name: `kc-postgres`
- restart policy: `unless-stopped`
- `env_file: .env`
- variabili environment esplicite:
  - `POSTGRES_DB=${POSTGRES_DB}`
  - `POSTGRES_USER=${POSTGRES_USER}`
  - `POSTGRES_PASSWORD=${POSTGRES_PASSWORD}`
  - `TZ=${TZ}`
- volume persistente: `postgres_data:/var/lib/postgresql/data`
- healthcheck: `pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}`

### 2. `keycloak`

- build locale da `Dockerfile`
- immagine prodotta: `keycloak-setup-local:24.0-themed`
- container name: `keycloak`
- restart policy: `unless-stopped`
- dipende da `postgres` in stato healthy
- `env_file: .env`
- comando container:
  - `start`
  - `--http-enabled=true`
  - `--http-port=8080`
  - `--proxy-headers=xforwarded`
- variabili environment:
  - `KC_DB=postgres`
  - `KC_DB_URL_HOST=postgres`
  - `KC_DB_URL_DATABASE=${POSTGRES_DB}`
  - `KC_DB_USERNAME=${POSTGRES_USER}`
  - `KC_DB_PASSWORD=${POSTGRES_PASSWORD}`
  - `KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN}`
  - `KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}`
  - `KC_HOSTNAME=${KC_HOSTNAME}`
  - `KC_PROXY=edge`
  - `TZ=${TZ}`
- bind host/container: `127.0.0.1:8080:8080`
- volume persistente: `keycloak_data:/opt/keycloak/data`

### Volumi definiti

- `postgres_data`
- `keycloak_data`

### Relazioni tra servizi

La catena di dipendenza reale è:

`postgres (healthy) -> keycloak`

## Dockerfile e strategia di build

Il `Dockerfile` usa una build multi-stage.

### Stage builder

- base image: `quay.io/keycloak/keycloak:24.0`
- `WORKDIR /opt/keycloak`
- copia l’intera directory `themes/` in `/opt/keycloak/themes/`
- esegue `/opt/keycloak/bin/kc.sh build`

### Stage finale

- base image: `quay.io/keycloak/keycloak:24.0`
- copia l’albero `/opt/keycloak/` dallo stage builder
- entrypoint: `[/opt/keycloak/bin/kc.sh]`

### Implicazione pratica

Il tema custom non viene montato a runtime ma **baked into the image**. Quindi qualsiasi modifica UI richiede:

1. aggiornamento dei file nel repository;
2. rebuild del servizio `keycloak`;
3. riavvio dello stack;
4. eventuale pulizia della cache gzip di Keycloak.

## Porte, esposizione e networking

### Porte esposte

- `8080/tcp` per Keycloak, ma **solo su loopback** (`127.0.0.1`)
- PostgreSQL non è pubblicato con `ports:` verso l’host

### Modello di esposizione previsto

Il repository è progettato per:

- esporre verso internet solo **80/443** tramite Nginx;
- non pubblicare direttamente `8080` e `5432`;
- usare `KC_PROXY=edge` e `--proxy-headers=xforwarded` per far convivere Keycloak con il reverse proxy.

## File `.env` e gestione configurazione ambiente

Il repository non versiona `.env`; fornisce `.env.example` come template.

### Variabili dichiarate in `.env.example`

- `KC_HOSTNAME=auth.example.com`
- `KEYCLOAK_ADMIN=kcadmin`
- `KEYCLOAK_ADMIN_PASSWORD=CHANGE_ME_STRONG_PASSWORD`
- `POSTGRES_DB=keycloak`
- `POSTGRES_USER=keycloak`
- `POSTGRES_PASSWORD=CHANGE_ME_STRONG_DB_PASSWORD`
- `TZ=Europe/Rome`
- `KEYCLOAK_BOOTSTRAP_APPLY_REALMS=false`
- `KEYCLOAK_BOOTSTRAP_WAIT_SECONDS=120`
- `KEYCLOAK_BOOTSTRAP_WAIT_INTERVAL=5`
- `KEYCLOAK_BOOTSTRAP_PROFILE=default`
- `KEYCLOAK_BOOTSTRAP_CONFIG_DIR=config/bootstrap`

### Variabili implicite usate dagli script ma non presenti nel template

Lo script `scripts/bootstrap_realms.sh` usa anche:

- `KEYCLOAK_INTERNAL_URL` con default `http://127.0.0.1:8080`
- `KEYCLOAK_PUBLIC_BASE_URL` opzionale
- `KEYCLOAK_PUBLIC_SCHEME` con fallback a `https`

Se `KEYCLOAK_PUBLIC_BASE_URL` non è valorizzata, lo script ricostruisce l’URL pubblico a partire da:

- `KEYCLOAK_PUBLIC_SCHEME`
- `KC_HOSTNAME`

### Regole operative sui segreti

- `.gitignore` esclude `.env`;
- le password iniziali admin e DB nel template sono placeholder e vanno sostituite;
- i file di backup SQL in `backups/` sono ignorati da Git;
- il README raccomanda `chmod 600 .env`.

## Script di automazione

### `scripts/update.sh`

Flusso reale:

1. entra nella root del repository;
2. carica `.env` se presente;
3. mostra lo stato stack con `docker compose ps`;
4. esegue `docker compose pull postgres`;
5. esegue `docker compose build --pull keycloak`;
6. esegue `docker compose up -d`;
7. mostra di nuovo `docker compose ps`;
8. se `KEYCLOAK_BOOTSTRAP_APPLY_REALMS=true`, lancia `scripts/bootstrap_realms.sh`.

Non aggiorna solo Keycloak: aggiorna anche la parte Postgres via pull dell’immagine remota.

### `scripts/bootstrap_realms.sh [profile]`

È lo script più sofisticato del repository. Implementa bootstrap **idempotente** profile-only di realm e client da JSON.

Funzioni reali:

- richiede `docker`, `python3`, `curl`;
- carica obbligatoriamente `.env`;
- valida la presenza di `KEYCLOAK_ADMIN` e `KEYCLOAK_ADMIN_PASSWORD`;
- verifica che il servizio `keycloak` esista nello stack Compose;
- attende che Keycloak sia disponibile interrogando `http://127.0.0.1:8080/realms/master/.well-known/openid-configuration` o l’URL interno configurato;
- si autentica via `kcadm.sh` dentro il container Keycloak;
- risolve il profilo attivo da argomento CLI (`[profile]`) oppure da `KEYCLOAK_BOOTSTRAP_PROFILE` in `.env`;
- risolve i target realm/client solo dal profilo (`realm_files` o `config_target`), fallendo se assenti;
- espande eventuali variabili ambiente dentro il JSON con Python;
- fallisce se restano placeholder `${...}` non risolti;
- valida la struttura del file (`realm`, `clients`, `clientId` univoci);
- separa realm e client in file temporanei;
- applica create/update di realm e client in base ai mode del profilo (`realm_mode`, `client_mode`) con default `upsert`;
- stampa un summary finale con endpoint OIDC, caratteristiche realm e dettagli client.

Salvataggi temporanei:

- usa `mktemp -d` su host per file intermedi;
- copia file temporanei nel container sotto `/tmp/bootstrap-*`;
- pulisce i file temporanei a fine esecuzione.

### `scripts/backup_db.sh`

- richiede `.env`;
- crea `backups/` se assente;
- genera un file `backups/keycloak_<YYYY-MM-DD>.sql`;
- esegue `pg_dump` nel container `kc-postgres`;
- mostra il file creato con `ls -lh`.

Nota: il backup è in SQL plain text, non compresso.

### `scripts/restore_db.sh <path_dump.sql>`

- richiede un argomento con il path del dump;
- verifica che il file esista;
- richiede `.env`;
- ferma Keycloak con `docker compose stop keycloak`;
- ripristina il dump via `psql` nel container `kc-postgres`;
- riavvia Keycloak con `docker compose start keycloak`.

Nota importante: lo script **non** drop/recreate il database. Fa replay del dump sul DB target esistente.

### `scripts/healthcheck.sh`

- stampa stato container via `docker ps --format ...`;
- verifica risposta HTTP locale di Keycloak su `127.0.0.1:8080`;
- verifica risposta HTTP locale di Nginx su `127.0.0.1:80`;
- stampa le porte in ascolto tramite `sudo ss -lntp | egrep ':80|:443|:8080|:5432'`.

Quindi lo script presuppone che:

- Nginx giri sull’host;
- sia disponibile `sudo`.

### `scripts/logs.sh`

- mostra gli ultimi 200 log di `keycloak`;
- mostra gli ultimi 200 log di `kc-postgres`.

Usa `docker logs` sui container name hardcoded, non `docker compose logs`.

### `scripts/sync-keycloak-repo.sh`

Implementa la sincronizzazione da una copia sorgente a una copia di deploy.

Valori hardcoded trovati:

- `LOCAL_REPO=/home/ubuntu/keycloak-setup`
- `OPT_REPO=/opt/keycloak`

Comportamento:

- crea `OPT_REPO` con `sudo mkdir -p`;
- esegue `rsync -a --delete`;
- esclude `.git/`, `.env`, `backups/`;
- sincronizza tutto il resto.

### Implicazioni dello script di sync

- `.env` del server non viene sovrascritto;
- i backup locali non vengono copiati;
- i file cancellati nella sorgente vengono rimossi nella destinazione a causa di `--delete`.

## Flussi operativi

### Flusso di deploy iniziale

1. copiare `.env.example` in `.env`;
2. valorizzare hostname, credenziali admin, credenziali database e timezone;
3. verificare il `server_name` in `nginx/keycloak.conf`;
4. verificare il path reale nel file `systemd/keycloak-compose.service`;
5. eseguire `docker compose build keycloak`;
6. eseguire `docker compose up -d`;
7. eseguire `./scripts/bootstrap_realms.sh` se si vogliono creare realm e client dichiarati.

### Flusso di rilascio successivo consigliato

1. aggiornare la copia sorgente del repository;
2. sincronizzarla verso la directory di deploy con `sync-keycloak-repo.sh`;
3. fare backup del database;
4. lanciare `./scripts/update.sh`;
5. controllare log, healthcheck, accesso locale e accesso pubblico.

### Flusso di aggiornamento UI

1. modificare il tema sotto `themes/dens-studio/` nella copia sorgente;
2. sincronizzare verso la directory di deploy;
3. rebuildare Keycloak;
4. svuotare la cache `kc-gzip-cache` se necessario;
5. verificare rendering e log.

## Configurazioni realm e client

La cartella `config/realms/` contiene configurazioni JSON con schema:

- oggetto `realm`
- array `clients`

### Comportamento del bootstrap

Il bootstrap è dichiarativo e idempotente:

- con `upsert` (default) crea se assente e aggiorna se presente;
- con `create_only` crea solo risorse assenti;
- con `update_only` aggiorna solo risorse esistenti.

In modalità profile-only, i file vengono selezionati tramite `config/bootstrap/profiles/*.json`.

### `realm-a-dev.json`

Definisce il realm `REALM-A-DEV` con caratteristiche principali:

- `enabled: true`
- `displayName: REALM A DEV`
- `sslRequired: external`
- registrazione abilitata;
- login con email abilitato;
- brute force protection attiva;
- eventi e admin events attivi;
- `accessTokenLifespan: 300`;
- `ssoSessionIdleTimeout: 1800`;
- `ssoSessionMaxLifespan: 36000`;
- algoritmo firma `RS256`;
- tema login `dens-studio`;
- internazionalizzazione abilitata con locali `it`, `en` e default `it`.

Client inclusi:

1. `dens-sudio-dev`
   - client browser OIDC pubblico;
   - Authorization Code Flow attivo;
   - PKCE S256 configurato;
   - redirect verso frontend web e localhost:3000.

2. `confidential-dev`
   - client confidential/server-side;
   - autenticazione `client-secret`;
   - `serviceAccountsEnabled=true`;
   - secret placeholder `CHANGE_ME_REALM_A_CONFIDENTIAL_SECRET`.

Nota: `dens-sudio-dev` sembra contenere un refuso nel nome client (`sudio` invece di `studio`), ma il repository lo definisce così.

### `realm-b-dev.json`

Definisce il realm `REALM-B-DEV` con impostazioni realm molto simili a `REALM-A-DEV`, sempre con tema `dens-studio`, localizzazione `it/en`, registrazione attiva e protezioni base.

Client inclusi:

1. `business-suite-dev`
   - client browser pubblico;
   - redirect verso `/b2b/dashboard` e localhost:3001.

2. `agents-dev`
   - client browser pubblico;
   - redirect verso `/agents/dashboard` e localhost:3002.

3. `studio-handler-dev`
   - client browser pubblico;
   - redirect verso `/studio-handler/home` e localhost:3003.

4. `confidential-dev`
   - client confidential/server-side;
   - service account abilitato;
   - secret placeholder `CHANGE_ME_REALM_B_CONFIDENTIAL_SECRET`.

### Considerazioni sui JSON

- i valori `redirectUris`, `webOrigins`, `rootUrl`, `baseUrl` e `secret` sono esempi/dev placeholder;
- lo script di bootstrap supporta espansione di variabili ambiente dentro i JSON;
- se i placeholder non vengono risolti, lo script fallisce esplicitamente.

## Tema custom `dens-studio`

Il repository include un login theme completo denominato `dens-studio`.

### Proprietà principali del tema

Dal file `theme.properties` risultano:

- `parent=keycloak`
- `import=common/keycloak`
- CSS registrato: `css/styles.css`
- JS registrato: `js/app.js`
- locali disponibili: `it,en`
- proprietà custom come:
  - `densBackToSelectionUrl`
  - `densShowDemoCredentials`
  - `densBrandIcon`
  - `densEmailIcon`
  - `densLockIcon`

Lo stesso file ridefinisce molte classi CSS Keycloak/PatternFly per adattare il rendering al design custom.

### Layout e asset

Dal contenuto del tema risultano:

- template FreeMarker custom (`template.ftl`, `login.ftl`, `register.ftl`, ecc.);
- messaggi localizzati in italiano e inglese;
- CSS custom esteso in `resources/css/styles.css`;
- JS minimale in `resources/js/app.js` per il toggle visibilità password;
- asset SVG brand/email/lock.

### Contenuto localizzato

`messages/messages_it.properties` contiene copy brandizzato come:

- `brandTitle=DENS Studio`
- `brandSubtitle=Sistema di Gestione Dentale`
- testi custom per login, registrazione, reset password, footer e label principali.

### Cosa copre il tema

La cartella `login/` copre almeno:

- login;
- registrazione;
- reset password;
- update password;
- pagine informative;
- porzioni comuni del profilo utente e della registrazione.

## Reverse proxy Nginx

Il file `nginx/keycloak.conf` definisce un vhost base HTTP:

- `listen 80`;
- `server_name auth.example.com`;
- `client_max_body_size 20m`;
- `proxy_pass http://127.0.0.1:8080`;
- inoltro header:
  - `Host`
  - `X-Real-IP`
  - `X-Forwarded-For`
  - `X-Forwarded-Proto`
- supporto header `Upgrade` e `Connection "upgrade"`;
- timeout lettura/scrittura a `180s`.

Il file è predisposto per HTTP; la procedura TLS è documentata in `docs/NGINX_TLS.md` tramite Certbot o certificati aziendali.

## systemd

Il file `systemd/keycloak-compose.service` configura:

- `Requires=docker.service`
- `After=docker.service`
- `Type=oneshot`
- `WorkingDirectory=/opt/keycloak`
- `ExecStart=/usr/bin/docker compose up -d`
- `ExecStop=/usr/bin/docker compose down`
- `RemainAfterExit=yes`

Nota: `ExecStop` usa `docker compose down`, quindi ferma e rimuove i container, ma non i volumi.

La configurazione è coerente con il path di deploy `/opt/keycloak` usato dagli script operativi del repository.

## Documentazione operativa inclusa

Il repository include già documenti tematici molto utili:

- `docs/DEPLOYMENT.md` per deploy standard;
- `docs/REPOSITORY_SYNC.md` per il modello sorgente/deploy separati;
- `docs/CUSTOM_UI.md` e `docs/THEMES.md` per il ciclo di vita del tema;
- `docs/BACKUP_RESTORE.md` per backup/restore DB;
- `docs/OPERATIONS.md` per i comandi quotidiani;
- `docs/REALM_BOOTSTRAP.md` per bootstrap di realm/client;
- `docs/NGINX_TLS.md` per pubblicazione e TLS;
- `docs/SYSTEMD.md` per startup automatico;
- `docs/SECURITY.md` e `docs/TROUBLESHOOTING.md` per hardening e incident response.

## Dipendenze reali

### Runtime e immagini

- Docker Engine
- Docker Compose plugin
- `postgres:16`
- `quay.io/keycloak/keycloak:24.0`

### Tool host-side richiesti dagli script o dalla documentazione

- `bash`
- `docker`
- `curl`
- `python3`
- `rsync`
- `sudo`
- `nginx`
- `certbot` (opzionale: solo per il percorso TLS basato su Certbot documentato in `docs/NGINX_TLS.md`)
- `ss` / `iproute2`

### Tool usati internamente al container Keycloak

- `kcadm.sh`
- `kc.sh`

## CI/CD e automazione delivery

Non risultano pipeline CI/CD versionate nel repository.

L’automazione presente è esclusivamente di tipo operativo/manuale:

- Docker Compose;
- build locale dell’immagine Keycloak;
- script shell;
- sync via `rsync`;
- unità systemd;
- reverse proxy Nginx.

## Sicurezza e note operative

### Buone pratiche già riflesse nel repository

- Keycloak è bindato su loopback, non su interfaccia pubblica;
- PostgreSQL non è esposto via `ports:`;
- `.env` è escluso da Git;
- il reverse proxy è previsto come punto di pubblicazione controllato;
- il bootstrap realm/client evita l’uso esclusivo della console admin e rende la configurazione più ripetibile.

### Rischi o punti di attenzione emersi dall’analisi

- il path di deploy non è coerente tra script e systemd;
- `logs.sh` e `backup_db.sh` dipendono da container name hardcoded (`keycloak`, `kc-postgres`);
- `restore_db.sh` non esegue reset strutturale del DB, quindi il comportamento dipende dal contenuto del dump;
- nel tema sono presenti file `.bak` che vengono copiati nell’immagine insieme al resto di `themes/` dal Dockerfile;
- nei JSON realm/client sono presenti secret placeholder che non vanno usati in produzione;
- i client di esempio puntano a domini/localhost di sviluppo e vanno adattati prima dell’uso reale.

## Conclusione

`keycloak-setup` è un repository completo per il deploy operativo di Keycloak con personalizzazione UI, gestione dichiarativa di realm/client e tooling di manutenzione. Il suo valore principale sta nell’unire deploy, sync, bootstrap e tema custom nello stesso punto; il principale punto di attenzione è invece la coerenza dei path di deploy e dei placeholder di configurazione, che vanno sistemati con precisione prima di andare in produzione.

---

## Orchestrazione centralizzata (root repository)

Da questo ciclo di aggiornamento è disponibile anche un layer centralizzato in root repository:

- `./scripts/up.sh keycloak`
- `./scripts/update.sh keycloak`
- `./scripts/down.sh keycloak`
- `./scripts/healthcheck.sh keycloak`
- `./scripts/status.sh keycloak`
- `./scripts/nginx-setup.sh keycloak`
- `./scripts/tls-setup.sh keycloak`

Per i dettagli operativi e la configurazione tramite `.orchestrator.env`, vedi `docs/ORCHESTRATION.md` nel root del repository.
