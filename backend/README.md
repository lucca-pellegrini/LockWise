---
title: LockWise — Back-end
subtitle: "Serviços de back-end para o sistema LockWise, incluindo API REST, gerenciamento de dispositivos via MQTT e autenticação por voz"
author: "Lucca M. A. Pellegrini, Felipe Castelo Branco de Mello"
date: 2025-12-13
lang: pt-BR
---

# LockWise — Back-end

Serviços de back-end para o sistema LockWise, construído com Rust (Rocket) para
a API principal e Python (FastAPI) para o serviço de reconhecimento de voz,
utilizando PostgreSQL para armazenamento e MQTT para comunicação em tempo real.

## Funcionalidades

- **API REST**: Endpoints para gerenciamento de usuários, dispositivos e convites
- **Autenticação de Usuário**: Integração com Firebase Authentication e senhas locais
- **Gerenciamento de Dispositivos**: Registro, controle remoto e monitoramento via MQTT
- **Autenticação por Voz**: Registro e verificação de embeddings de voz usando SpeechBrain
- **Logs de Acesso**: Histórico detalhado de operações em dispositivos
- **Convites Temporários**: Compartilhamento de acesso a dispositivos com expiração
- **Heartbeat MQTT**: Monitoramento contínuo do estado dos dispositivos
- **Configuração Remota**: Atualização de parâmetros de dispositivos via MQTT

## Requisitos de Hardware

- **Servidor Linux/Windows/macOS** com conectividade de rede
- **Banco de Dados PostgreSQL** (versão 12+)
- **Broker MQTT** (ex.: NanoMQ, Mosquitto, HiveMQ)
- **Armazenamento Persistente** para logs e dados de usuário

## Pré-requisitos

### Rust e Cargo

Certifique-se de que Rust está instalado usando o gerenciador de pacotes do seu
sistema, ou:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
```

### Python e Dependências

Instale Python 3.10 (versões 3.11 e 3.12 têm status desconhecido; 3.13 não
funciona) e as dependências. Recomenda-se usar um ambiente virtual:

```bash
python3.10 -m venv venv
source venv/bin/activate  # Linux/macOS
# ou
venv\Scripts\activate     # Windows
pip install -r requirements.txt
```

### PostgreSQL

Configure um banco de dados PostgreSQL e defina a variável de ambiente
`DATABASE_URL`.

**Importante**: Em produção, especialmente quando o banco de dados está em uma
máquina diferente do back-end, use TLS para proteger a conexão. Configure o
PostgreSQL para exigir conexões SSL e use uma `DATABASE_URL` com o protocolo
`postgresqls://` (note o 's' para SSL).

### Broker MQTT

Configure um broker MQTT e defina as variáveis de ambiente `MQTT_HOST`,
`MQTT_PORT`, etc.

## Estrutura do Projeto

```
backend/
├── src/
│   ├── main.rs               # API principal em Rust (Rocket)
│   └── bin/
│       └── add_passphrase.rs # Utilitário para provisionamento de dispositivos
├── speechbrain_service.py    # Serviço de reconhecimento de voz (FastAPI)
├── models/                   # Modelos treinados do SpeechBrain
├── samples/                  # Amostras de áudio para teste
├── Cargo.toml                # Dependências Rust
├── requirements.txt          # Dependências Python
├── .env.example              # Exemplo de variáveis de ambiente
└── README.md                 # Este arquivo
```

## Configuração

### 1. Variáveis de Ambiente

Copie `.env.example` para `.env` e configure:

```bash
DATABASE_URL=postgresql://user:password@postgres.meu-lindo-site.com/lockwise
MQTT_HOST=mqtt.meu-lindo-site.com
MQTT_PORT=8883
MQTT_TLS=true
MQTT_USERNAME=back-end-do-lockwise
MQTT_PASSWORD=senha-do-back-end-do-lockwise
PORT=12345
SPEECHBRAIN_URL=http://speechbrain.meu-lindo-site.com:5008
HOMEPAGE_URL=https://example.com
```

### 2. Banco de Dados

O back-end cria automaticamente as tabelas necessárias na inicialização.
Certifique-se de que o usuário do banco tem permissões para criar tabelas.

### 3. Modelos de Voz

Os modelos do SpeechBrain são baixados automaticamente na primeira execução.
Para uso offline, os modelos ficam em `models/spkrec/`.

## Compilação e Execução

### Serviço Principal (Rust)

Compile e execute o serviço principal:

```bash
# Executar em modo release (otimizado)
cargo run --release
```

O serviço estará disponível em `http://localhost:8000` (ou porta configurada).

### Serviço de Voz (Python)

Execute o serviço de reconhecimento de voz:

```bash
uvicorn speechbrain_service:app --port 5008 --workers 1
```

O serviço estará disponível em `http://localhost:5008`.

### Utilitário de Provisionamento

Para provisionar um novo dispositivo durante a configuração inicial:

```bash
cargo run --bin add_passphrase
```

Note que o dispositivo já deve existir no banco de dados — para isso, é preciso
que o dispositivo já tenha se conectado (de forma autenticada) ao broker
enquanto o back-end estava online. Siga as instruções na tela para selecionar o
dispositivo e definir a senha. Consulte
[../embedded/README.md](../embedded/README.md) para detalhes sobre o processo
de pareamento de dispositivos.

### Execução com Docker

Como alternativa à instalação manual de Rust e Python, é possível executar o
back-end usando Docker.

#### Pré-requisitos para Docker

- **Docker** instalado e configurado
- **PostgreSQL** ainda deve ser instalado e configurado separadamente (veja
  seção PostgreSQL acima). **Importante**: Em produção, use TLS ou outra forma
  segura para conectar-se ao banco de dados PostgreSQL em outra máquina.

#### Usando Docker Compose (Recomendado)

Um exemplo de `docker-compose.yml` está incluído no repositório. Copie-o e
configure as variáveis de ambiente conforme necessário:

```bash
cp docker-compose.yml docker-compose.override.yml
# Edite docker-compose.override.yml com suas configurações
docker-compose up -d
```

**Nota**: Quando usando Docker Compose, o arquivo `.env` não é utilizado. Todas
as configurações devem ser definidas diretamente no `docker-compose.yml` ou
em um arquivo de override.

#### Usando Docker Diretamente

Para construir e executar a imagem Docker manualmente:

```bash
# Construir a imagem
docker build -t lockwise-backend .

# Executar o container
docker run -p 12223:12223 \
    -e DATABASE_URL="postgresql://user:pass@host:port/db" \
    -e MQTT_HOST="mqtt.example.com" \
    -e MQTT_PORT=1883 \
    -e MQTT_TLS=false \
    -e MQTT_USERNAME="username" \
    -e MQTT_PASSWORD="password" \
    -e SPEECHBRAIN_URL="http://speechbrain:5008" \
    -e HOMEPAGE_URL="https://example.com" \
    -e PORT=12223 \
    -v $(pwd)/models:/app/models \
    lockwise-backend
```

O serviço estará disponível na porta especificada (padrão: 12223).

## API Endpoints

### Autenticação

- `POST /register` - Registrar novo usuário
- `POST /login` - Login de usuário
- `POST /logout` - Logout
- `POST /update_password` - Alterar senha
- `POST /verify_password` - Verificar senha atual

### Dispositivos

- `GET /devices` - Listar dispositivos do usuário
- `GET /device/<uuid>` - Detalhes de dispositivo
- `POST /register_device` - Registrar dispositivo
- `POST /control/<uuid>` - Controlar dispositivo (LOCK/UNLOCK)
- `POST /unpair/<uuid>` - Desparear dispositivo
- `POST /ping/<uuid>` - Ping no dispositivo
- `POST /update_config/<uuid>` - Atualizar configuração
- `POST /reboot/<uuid>` - Reinicializar dispositivo
- `POST /lockdown/<uuid>` - Bloquear dispositivo

### Voz

- `POST /register_voice` - Registrar voz do usuário
- `POST /verify_voice` - Verificar voz
- `DELETE /delete_voice` - Remover registro de voz
- `GET /voice_status` - Status do registro de voz

### Convites

- `POST /create_invite` - Criar convite
- `GET /get_invites` - Listar convites
- `POST /accept_invite` - Aceitar convite
- `POST /reject_invite` - Rejeitar convite
- `POST /cancel_invite` - Cancelar convite
- `POST /update_invite` - Atualizar convite

### Logs e Notificações

- `GET /logs/<uuid>` - Logs do dispositivo
- `GET /notifications` - Notificações do usuário

### Acesso Temporário

- `GET /temp_devices_status` - Dispositivos com acesso temporário
- `GET /temp_device/<uuid>` - Detalhes de dispositivo temporário
- `POST /temp_control/<uuid>` - Controlar dispositivo temporário
- `POST /temp_ping/<uuid>` - Ping em dispositivo temporário

## Solução de Problemas

### Conexão com Banco de Dados

- Verifique se PostgreSQL está rodando e acessível
- Confirme formato da `DATABASE_URL`: `postgresql://user:pass@host:port/db` (ou `postgresqls://` para SSL)
- Certifique-se de que o banco permite conexões SSL em produção
- Para bancos remotos, use TLS/SSL para segurança

### Problemas MQTT

- Verifique conectividade com o broker: `telnet MQTT_HOST MQTT_PORT`
- Confirme credenciais se autenticação estiver habilitada
- Monitore logs para erros de conexão

### Serviço de Voz Não Responde

- Verifique se o modelo SpeechBrain foi carregado (logs na inicialização)
- Confirme porta 5008 não está em uso
- Teste endpoint: `curl http://localhost:5008/embed -X POST -H "Content-Type: application/json" -d '{"pcm_base64":""}'`

### Erros de Autenticação

- Verifique token JWT no header `Authorization: Bearer <token>`
- Confirme usuário existe no banco de dados
- Valide formato do Firebase UID

### Dispositivo Não Responde

- Verifique se dispositivo está online (campo `last_heard`)
- Confirme conectividade MQTT do dispositivo
- Monitore logs do dispositivo embarcado

## Dicas de Desenvolvimento

1. **Logs Detalhados**: Use `RUST_LOG=debug` para logs verbosos do serviço Rust
2. **Teste Local**: Use `cargo test` para executar testes unitários
3. **Monitoramento**: Implemente health checks em `/health`
4. **Segurança**: Sempre use HTTPS em produção e valide inputs
5. **Desempenho**: Monitore uso de memória e conexões de banco
6. **Backup**: Faça backup regular do banco de dados PostgreSQL

## Licença

Este projeto é licenciado sob [Apache License 2.0](LICENSE).
