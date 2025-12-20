---
title: LockWise — Infraestrutura
subtitle: "Configuração e implantação da infraestrutura do sistema LockWise"
author:
    - Lucca M. A. Pellegrini
date: 2025-12-16
lang: pt-BR
---

[← Anterior: Back-end](Backend.md)

# Setup da Infraestrutura

Já falamos extensivamente a respeito de *como* cada um dos componentes próprios
desse projeto foi projetado e desenvolvido nas páginas anteriores, mas convém
descrever aqui a configuração e a organização do *broker* MQTT, do proxy
reverso, do contêiner, e do banco de dados. Na página anterior, mostramos um
diagrama que ilustra o funcionamento do *back-end* a grosso modo — mas, para
ser mais exato, o *deployment* final entregue segue o seguinte diagrama:

```mermaid
graph LR
    A[[App Flutter]] -->|API Firebase| B[Firestore]
    A -->|API Firebase| C[Firebase Auth]
    A -->|APIs REST| D{{openresty.service}}
    A <-->|WebSocket| D
    A -.->|AP de Pareamento| E[[Fechadura LockWise]]
    E <-->|MQTTS| F[Broker NanoMQ]
    E -->|APIs REST| D
    D -->|Porta TCP Local| G[cargo run]
    F <-->|MQTTS| G
    G -->|Toolkit SQLx| H{{postgresql.service}}
    G ==>|Conexão Interna| I[uvicorn speechbrain_service:app]
    J{{certbot-renew.service}} --> |Atualização de Arquivos| K
    K[[Certificados TLS]] -.-> |Carregamento de Certificados| D
    K  -.-> |Carregamento de Certificados| F
    K  -.-> |Carregamento de Certificados| H
    L[nginx.conf] -.-> |Leitura de Configuração| D
    M[nanomq.conf] -.-> |Leitura de Configuração| F
    N[nanomq_pwd.conf] -.-> |Leitura de Credenciais| F
    O[nanomq_acl.conf] -.-> |Leitura de Controle de Acesso| F
    P[setfacl] ==> |Modificação de ACL| K
    Q{{docker-restart-running.service}} -.-> |Reinicia| F
    Q{{docker-restart-running.service}} -.-> |Reinicia| G
    Q{{docker-restart-running.service}} -.-> |Reinicia| I
    subgraph Google
        B
        C
    end
    subgraph "VPS Debian GNU/Linux 12 (bookworm)"
        D
        F
        G
        H
        I
        J
        K
        L
        M
        N
        O
        P
        Q
        subgraph Imagem Docker
            F
        end
        subgraph Imagem Docker
            G
            I
        end
    end
```

Nas seções abaixo, procuraremos explicar cada um dos componentes *dentro* da
VPS Debian, e como cada um é configurado e gerenciado. Não entraremos em
detalhes sobre o funcionamento interno do *Back-end Rocket* nem do *Back-end
FastAPI*, pois já os descrevemos extensivamente na página anterior.

## Servidor

Para implementar esse projeto, usamos um [VPS da empresa
*Ionos*](https://ionos.com/servers/vps) que já tínhamos adquirido para um
projeto de IoT em um semestre anterior. Esse VPS já contava com um broker
[NanoMQ](https://nanomq.io/), um banco de dados
[PostgreSQL](https://postgresql.org), certificados TLS de [Let's
Encrypt](https://letsencrypt.org), um *daemon* [Docker](https://docker.com),
e um servidor web [OpenResty](https://openresty.org/) (uma distribuição de
[Nginx](https://nginx.org)). Para adaptar esses serviços ao LockWise, bastou
adicionar credenciais de clientes e controle de acesso ao *broker*, um único
bloco `server` à configuração do OpenResty para atuar como proxy reverso, e um
único arquivo `docker-compose.override.yml` para o back-end do LockWise.

### OpenResty

Este serviço é controlado pela [unidade
Systemd](https://man.archlinux.org/man/systemd.unit.5) padrão do Debian
*bookworm*, mostrada abaixo, sem nenhum *override* necessário:

```ini
[Unit]
Description=The OpenResty Application Platform
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/usr/local/openresty/nginx/logs/nginx.pid
ExecStartPre=/usr/local/openresty/nginx/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/local/openresty/nginx/sbin/nginx -g 'daemon on; master_process on;'
ExecStartPost=/bin/sleep 1
ExecReload=/usr/local/openresty/nginx/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /usr/local/openresty/nginx/logs/nginx.pid
RuntimeDirectory=openresty
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
```

A configuração do servidor em si foi feita em um único arquivo
`/etc/openresty/nginx.conf`. As definições de `http` sendo:

```nginx.conf
worker_processes 2;

events {
    worker_connections 1024;
}

http {
    include           mime.types;
    default_type      application/octet-stream;
    sendfile          on;
    keepalive_timeout 65;
    gzip              off; # BREACH attack bad!

    # Enable HTTP/2 and HTTP/3
    http2 on;
    http3 on;
    http3_hq on;
    quic_retry on;
    quic_gso on;

    # ... (continua) ...

    server {
        listen 80;
        listen [::]:80;
        listen 443 ssl;
        listen [::]:443 ssl;
        listen 443 quic;
        listen [::]:443 quic;

        server_name        OMITIDO.com;
        more_clear_headers Server;
        server_tokens      off;

        ssl_certificate     /etc/letsencrypt/live/OMITIDO.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/OMITIDO.com/privkey.pem;
        ssl_session_cache   shared:le_nginx_SSL:10m;

        ssl_session_timeout       1440m;
        ssl_session_tickets       off;
        ssl_protocols             TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers off;
        ssl_ciphers               "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";

        add_header              Strict-Transport-Security "max-age=31536000" always;
        add_header              Alt-Svc 'h3=":$server_port"; ma=86400';
        ssl_trusted_certificate /etc/letsencrypt/live/OMITIDO.com/chain.pem;
        ssl_stapling            on;
        ssl_stapling_verify     on;

        access_log /var/log/nginx/lockwise-access.log;
        error_log  /var/log/nginx/lockwise-error.log; #debug;

        root /var/lib/nginx/lockwise/html;

        location /.well-known/acme-challenge/ {
            try_files $uri =404;
        }

        location / {
            proxy_pass http://127.0.0.1:12223;

            proxy_request_buffering off;
            proxy_buffering off;

            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";

            client_max_body_size 0;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    # ... (continua) ...
}
```

O uso de `proxy_http_version`, `proxy_set_header Upgrade $http_upgrade` e
`proxy_set_header Connection "upgrade"` se deve ao fato de que nosso back-end
usa [WebSockets](https://websockets.spec.whatwg.org/) para atualizações
*push* em tempo real do aplicativo móvel, que, em geral, só são utilizadas via
HTTP/1.1. O bloco `location /.well-known/acme-challenge/` é usado para que o
[Certbot](https://certbot.eff.org/) possa emitir certificados TLS pelo [método
*webroot*](https://certbot.eff.org/instructions?ws=other&os=pip), que nos
permite renovar os certificados sem ter que interromper o servidor.

### Certbot

Utilizamos [Certbot](https://certbot.eff.org) para emitir os certificados TLS
para o nosso domínio. Usamos o comando seguinte para cada componente, uma vez
para o proxy reverso, uma vez para o *broker* MQTT, e uma vez para o
PostgreSQL:

```bash
sudo /var/lib/certbot/bin/certbot certonly --webroot
```

Um par de unidades Systemd
[serviço](https://man.archlinux.org/man/systemd.service.5) e
[timer](https://man.archlinux.org/man/systemd.timer.5) renova os certificados
assim que a data de expiração se aproxima. A verificação é feita três vezes por
mês:

```ini
[Unit]
Description=Update SSL certificates
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
Restart=on-failure
ExecStart=/var/lib/certbot/bin/certbot renew

[Install]
WantedBy=multi-user.target
```
```ini
[Unit]
Description=Run certbot renew periodically

[Timer]
OnActiveSec=10min
OnCalendar=*-*-1,10,20 00:00:00
RandomizedDelaySec=10h
Persistent=true

[Install]
WantedBy=timers.target
```

Para permitir que o PostgreSQL, que não executa como `root`, possa acessar os
certificados TLS, usamos:

```bash
sudo setfacl -m u:postgres:r /etc/letsencrypt/archive/OMITIDO.com/*
sudo setfacl -d -m u:postgres:rX /etc/letsencrypt/archive/OMITIDO.com
```

### NanoMQ

Para ser nosso *broker* MQTT, usamos o [NanoMQ](https://nanomq.io/) com o
*feature set* completo, executado em uma imagem Docker:

```bash
sudo docker run -d --name nanomq                                               \
    -p 1883:1883 -p 8083:8083 -p 8883:8883                                     \
    --restart unless-stopped                                                   \
    -v /etc/letsencrypt/live/OMITIDO.com/cert.pem:/certs/cert.pem:ro           \
    -v /etc/letsencrypt/live/OMITIDO.com/chain.pem:/certs/chain.pem:ro         \
    -v /etc/letsencrypt/live/OMITIDO.com/fullchain.pem:/certs/fullchain.pem:ro \
    -v /etc/letsencrypt/live/OMITIDO.com/privkey.pem:/certs/privkey.pem:ro     \
    -v /etc/nanomq.conf:/etc/nanomq.conf:ro                                    \
    -v /etc/nanomq_pwd.conf:/etc/nanomq_pwd.conf:ro                            \
    -v /etc/nanomq_acl.conf:/etc/nanomq_acl.conf:ro                            \
    emqx/nanomq:0.23.5-full
```

Como o NanoMQ não é capaz de automaticamente detectar e recarregar certificados
TLS atualizados, criamos um par de unidades Systemd
[serviço](https://man.archlinux.org/man/systemd.service.5) e
[timer](https://man.archlinux.org/man/systemd.timer.5) para periodicamente
reiniciar todas as imagens Docker que estiverem online:

```ini
[Unit]
Description=Restart all running Docker containers

[Service]
Type=oneshot
ExecStart=/usr/bin/sh -c 'docker ps -q | xargs docker restart'
```
```ini
[Unit]
Description=Restart all running Docker containers every 3 days

[Timer]
OnUnitActiveSec=3d
AccuracySec=1h
Persistent=false

[Install]
WantedBy=timers.target
```

Para configurar o broker, usamos três arquivos. O primeiro é um arquivo de
configuração geral; o segundo contém as credenciais do back-end e de cada
dispositivo cliente, que devem ser manualmente provisionadas pelo *sysadmin*; e
o terceiro contém as definições de controle de acesso utilizadas para que o
broker defina, dentro dos tópicos `lockwise/#`, *quem* pode publicar ou se
inscrever *em cada um*. (Note que as credenciais abaixo são meros exemplos.)

```/etc/nanomq.conf
mqtt {
    property_size = 32
    max_packet_size = 260MB
    max_mqueue_len = 2048
    retry_interval = 10s
    keepalive_multiplier = 1.25

    # Three of below, unsupported now
    max_inflight_window = 2048
    max_awaiting_rel = 10s
    await_rel_timeout = 10s
}

listeners.tcp {
    bind = "0.0.0.0:1883"
}

listeners.ssl {
    bind = "0.0.0.0:8883"
    keyfile = "/certs/privkey.pem"
    certfile = "/certs/fullchain.pem"
    cacertfile = "/certs/chain.pem"
    verify_peer = false
    fail_if_no_peer_cert = false
}

listeners.ws {
    bind = "0.0.0.0:8083/mqtt"
}

http_server {
    port = 8081
    ip_addr = "127.0.0.1"
    limit_conn = 2
    username = admin
    password = public
    auth_type = basic
    jwt {
        public.keyfile = "/etc/certs/jwt/jwtRS256.key.pub"
    }
}

log {
    to = [file, console]
    level = warn
    dir = "/tmp"
    file = "nanomq.log"
    rotation {
        size = 10MB
        count = 5
    }
}

auth {
    allow_anonymous = true
    no_match = allow
    deny_action = ignore

    cache = {
        max_size = 1024
        ttl = 1m
    }

    password = {include "/etc/nanomq_pwd.conf"}
    acl = {include "/etc/nanomq_acl.conf"}
}
```
```/etc/nanomq_pwd.conf
  "admin": "76aMoJCeGhPmYgflJIQVlC400uuxcppA"
  "lockwisebackend": "oxidative-ba-asu-circuitry-hp-gather-pledge-ou-rome-nocturnal"
  "43f6b35c-596c-4606-a043-74ccfdfd0f91": "39_98ToZiuZ-uU4UsLR3zeVD1igkyzM1UsIDMy3iTuAf_BmwJt39IRrlUEPtH4skxltJk_-RMXZyxLzpFzBXJXflDH5gxlqKr2Vwk68-Segd3OJjbmOV6LsQQ2x0z0X9i4n_2eBhcuLDBvi1adK95hWQJn2AnGG2-_3dSLJszRHTeFQeiqR7-d4BYzkm7nKfHoCMGnIO8AYRFHEFNC0fPp8htKFM7-K9uyTRw5PWsG_0ziJvG5WU86KAjd_lLd4"
  "6177f205-cbb4-40b2-94b3-61e6a9d0b35b": "lgb9DRwLAttMgqUu0J_SOm7oXtn1Ioc3K-nQ87Mq_QMvMHT6DDd3pSTT4QE_lPHqYIGY0BZ6RfmMsHz4TdedHF8qFLjnkz7gjQjU6Gh3twkjl7KD23cYdVM9Dye4PBJtXMt0biU3xKXXlhRNzu7C4Y_M350SQRwhNFMtNwq4fMFEfHMm-z6veu-7SANTJtGcq5bAusd_zPJiCV0GkMP7KrGiNO64X3V_LkGRfhkqLBCD7q2XzarXZZb3froQTst"
  "e54ef0eb-dea6-4613-8cdf-ebf5425a7325": "EFuW0roG1UFnnvHbfVDgNK8nO51zqm-_KnN36M-7BsVLgx-rXjJ54RQlU93b3Mgcdebr5Ys2_jye_7b2_4Z4eFbFEZmiSBjkTx-aHEMYKf8PcRCuBQS5eQMldqGNQh1vQNVeGSKpTug2eFZUYdLjFX0p1lGOtObBkHD973hBQzTItIs_qjYKtOsI8lpJQmQQwOuEK1QGwDdSv779FhTWtSb7X4OWIPw8EnPL5HA0jgH2IlL-3SFEN4MksJtLNSb"
  "f3a3d08b-08c2-4a7a-bfaa-cd7d615919a0": "PzRtZCiWEMLD-K6VQH_QnSqR5Zq08to8rOMbktEx1-wNqCoS2GsKlHFkvSOdNWdoiPzWiy8qYW_TSR58HAP-gz55f1mf20BT6W-9gjk17oEO_rdM4TDrZkQ_-pW0yJA3wmUCGB8BTK_feq6YEmJ8_nbwQgrzRvtYkdfbr8R_Tnh1woPsG59pzrJt5TODPHdZf4E8b0Os-4B9e70NZ8YeRx_eEoZJIzjE1RQZ8rmXC4aH-6BC9O-oV9YI2IvsQbv"
```
```/etc/nanomq_acl.conf
rules = [
    ## Allow admin to access all
    {"permit": "allow", "username": "admin", "action": "pubsub", "topics": ["#"]}

    ## Allow lockwise backend to access all LockWise topics
    {"permit": "allow", "username": "lockwisebackend", "action": "pubsub", "topics": ["lockwise/#"]}

    ## Allow each device to see its own topics
    {"permit": "allow", "username": "#", "action": "publish", "topics": ["lockwise/${username}/status"]}
    {"permit": "allow", "username": "#", "action": "subscribe", "topics": ["lockwise/${username}/control"]}

    ## Deny all other LockWise access
    {"permit": "deny", "username": "#", "action": "subscribe", "topics": ["lockwise/#"]}
    {"permit": "deny", "username": "#", "action": "publish", "topics": ["lockwise/#"]}

    ## Allow any other publish/subscribe operation
    {"permit": "allow"}
]
```

### Imagem Docker do Back-End

Finalmente, para executar a imagem Docker do Back-End, usamos o seguinte
`docker-compose.override.yml` (note que as credenciais foram substituídas
abaixo por exemplos):

```yml
version: '3.8'

services:
    lockwise-backend:
        image: localhost/lockwise-backend
        container_name: lockwise-backend
        ports:
            - "12223:12223"
        environment:
            - DATABASE_URL=postgresql://lockwisebackend:OMITIDO@OMITIDO.com/lockwise
            - HOMEPAGE_URL=https://github.com/lucca-pellegrini/LockWise
            - MQTT_HOST=OMITIDO.com
            - MQTT_PASSWORD=oxidative-ba-asu-circuitry-hp-gather-pledge-ou-rome-nocturnal
            - MQTT_PORT=8883
            - MQTT_TLS=true
            - MQTT_USERNAME=lockwisebackend
            - PORT=12223
            - SPEECHBRAIN_URL=http://localhost:5008
        restart: unless-stopped
        healthcheck:
            test: ["CMD", "curl", "-f", "http://localhost:12223/health"]
            interval: 30s
            timeout: 10s
            retries: 3
            start_period: 40s
```

Para evitar a necessidade de montar a imagem no VPS, que não é muito potente,
usamos o seguinte snippet para gerar a imagem num sistema local e transferi-la
para o VPS, comprimindo com [Zstandard](https://github.com/facebook/zstd) em
trânsito, a cada iteração do desenvolvimento (vale notar que o sistema local
não usa Docker, mas [Podman](https://podman.io/) via
[`podman-docker`](https://archlinux.org/packages/extra/x86_64/podman-docker/)):

```zsh
time docker build -t lockwise-backend . &&
time docker save lockwise-backend | zstd -v3T0 | ssh OMITIDO 'sh -c "zstdcat | docker load"' &&
time ssh OMITIDO -t 'cd ~/LockWise/backend && docker-compose up -d'
```

[← Anterior: Back-end](Backend.md)
