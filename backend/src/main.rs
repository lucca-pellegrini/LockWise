/// # LockWise Back-end
///
/// Serviços de back-end para o sistema LockWise, construído com Rust (Rocket) para
/// a API principal e Python (FastAPI) para o serviço de reconhecimento de voz,
/// utilizando PostgreSQL para armazenamento e MQTT para comunicação em tempo real.
///
/// ## Funcionalidades
///
/// - **API REST**: Endpoints para gerenciamento de usuários, dispositivos e convites
/// - **Autenticação de Usuário**: Integração com Firebase Authentication e senhas locais
/// - **Gerenciamento de Dispositivos**: Registro, controle remoto e monitoramento via MQTT
/// - **Autenticação por Voz**: Registro e verificação de embeddings de voz usando SpeechBrain
/// - **Logs de Acesso**: Histórico detalhado de operações em dispositivos
/// - **Convites Temporários**: Compartilhamento de acesso a dispositivos com expiração
/// - **Heartbeat MQTT**: Monitoramento contínuo do estado dos dispositivos
/// - **Configuração Remota**: Atualização de parâmetros de dispositivos via MQTT
///
/// ## Arquitetura
///
/// O back-end utiliza uma arquitetura baseada em microserviços leves:
///
/// - **Serviço Principal (Rust)**: API REST com Rocket, gerenciamento de usuários e dispositivos
/// - **Serviço de Voz (Python)**: Reconhecimento de voz com SpeechBrain e FastAPI
/// - **Banco de Dados**: PostgreSQL para persistência de dados
/// - **Comunicação**: MQTT para controle em tempo real dos dispositivos
///
/// ## Configuração
///
/// Consulte o README.md para instruções detalhadas de configuração e execução.
use anyhow::Result;
use chrono::Utc;
use rocket::http::Status;
use rocket::request::{FromRequest, Outcome};
use rocket::{Request, State, get, routes};
use rumqttc::{AsyncClient, MqttOptions, QoS, Transport};
use sqlx::ConnectOptions;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions, PgSslMode};
use std::collections::HashMap;
use std::env;
use std::sync::{Mutex, OnceLock};
use url::Url;

mod device;
mod invite;
mod mqtt;
mod user;

/// Invólucro para a URL do serviço SpeechBrain
pub struct SpeechbrainUrl(pub String);
/// Invólucro para a URL da página inicial para redirecionamentos
pub struct HomepageUrl(pub String);

/// Invólucro para token JWT dos cabeçalhos da requisição.
#[derive(Clone)]
pub struct Token(pub String);

/// Implementação de FromRequest para Token para extrair token Bearer do cabeçalho Authorization.
#[rocket::async_trait]
impl<'r> FromRequest<'r> for Token {
    type Error = &'static str;

    async fn from_request(req: &'r Request<'_>) -> rocket::request::Outcome<Self, Self::Error> {
        let auth_header = req.headers().get_one("Authorization");
        match auth_header {
            Some(auth) if auth.starts_with("Bearer ") => {
                let token_str = &auth[7..];
                Outcome::Success(Token(token_str.to_string()))
            }
            _ => Outcome::Error((
                Status::Unauthorized,
                "Missing or invalid Authorization header",
            )),
        }
    }
}

/// Armazena comandos recentes enviados aos dispositivos com timestamp para desduplicação
type RecentCommands = Mutex<HashMap<String, (String, i64)>>;
/// Rastreia solicitações de ping pendentes com timestamp e canal de resposta
type PendingPings = Mutex<HashMap<String, (i64, tokio::sync::oneshot::Sender<()>)>>;
/// Rastreia solicitações de atualização de configuração pendentes com canal de resposta
type PendingConfigUpdates = Mutex<HashMap<String, tokio::sync::oneshot::Sender<()>>>;

/// Armazenamento global para comandos recentes
pub static RECENT_COMMANDS: OnceLock<RecentCommands> = OnceLock::new();
/// Armazenamento global para pings pendentes
pub static PENDING_PINGS: OnceLock<PendingPings> = OnceLock::new();
/// Armazenamento global para atualizações de configuração pendentes
pub static PENDING_CONFIG_UPDATES: OnceLock<PendingConfigUpdates> = OnceLock::new();

/// Ponto de entrada principal do serviço de back-end LockWise.
/// Inicializa banco de dados, cliente MQTT, configura tabelas, inicia manipulador de eventos MQTT,
/// tarefa de limpeza de logs e lança o servidor HTTP Rocket.
#[tokio::main]
async fn main() -> Result<()> {
    dotenv::dotenv().ok();

    // Load env vars
    let db_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    let mqtt_host = env::var("MQTT_HOST").expect("MQTT_HOST must be set");
    let mqtt_port: u16 = env::var("MQTT_PORT")
        .map(|s| s.parse().unwrap())
        .unwrap_or(1883);
    let mqtt_tls: bool = env::var("MQTT_TLS")
        .map(|s| s.parse().unwrap())
        .unwrap_or(false);
    let mqtt_username = env::var("MQTT_USERNAME").ok();
    let mqtt_password = env::var("MQTT_PASSWORD").ok();
    let port: u16 = env::var("PORT")
        .unwrap_or("8000".to_string())
        .parse()
        .unwrap();
    let speechbrain_url =
        SpeechbrainUrl(env::var("SPEECHBRAIN_URL").unwrap_or("http://localhost:5008".to_string()));
    let homepage_url =
        HomepageUrl(env::var("HOMEPAGE_URL").unwrap_or("https://example.com".to_string()));
    RECENT_COMMANDS.set(Mutex::new(HashMap::new())).unwrap();
    PENDING_PINGS.set(Mutex::new(HashMap::new())).unwrap();
    PENDING_CONFIG_UPDATES
        .set(Mutex::new(HashMap::new()))
        .unwrap();

    // Setup DB
    let url = Url::parse(&db_url)?;
    let options = PgConnectOptions::from_url(&url)?.ssl_mode(PgSslMode::Require);
    let db_pool = PgPoolOptions::new()
        .max_connections(5)
        .connect_with(options)
        .await?;

    // Create devices table if not exists
    sqlx::query("CREATE TABLE IF NOT EXISTS devices ( uuid uuid PRIMARY KEY, user_id VARCHAR(255), last_heard timestamptz NOT NULL, uptime_ms bigint NOT NULL, hashed_passphrase VARCHAR(255), locked_down_at timestamptz)")
    .execute(&db_pool)
    .await?;

    // Create users table if not exists
    sqlx::query("CREATE TABLE IF NOT EXISTS users ( firebase_uid VARCHAR(255) PRIMARY KEY, hashed_password VARCHAR(255) NOT NULL, email VARCHAR(255) NOT NULL, phone_number VARCHAR(255), name VARCHAR(255) NOT NULL, current_token VARCHAR(255), voice_embeddings BYTEA, created_at timestamptz NOT NULL DEFAULT NOW(), last_login timestamptz)")
    .execute(&db_pool)
    .await?;

    // Create logs table if not exists
    sqlx::query("CREATE TABLE IF NOT EXISTS logs ( id SERIAL PRIMARY KEY, device_id VARCHAR(255) NOT NULL, timestamp timestamptz NOT NULL DEFAULT NOW(), event_type VARCHAR(10) NOT NULL, reason VARCHAR(20) NOT NULL, user_id VARCHAR(255), created_at timestamptz NOT NULL DEFAULT NOW())")
        .execute(&db_pool)
        .await?;

    // Create invites table if not exists
    sqlx::query("CREATE TABLE IF NOT EXISTS invites ( id SERIAL PRIMARY KEY, device_id UUID NOT NULL, sender_id VARCHAR(255) NOT NULL, receiver_id VARCHAR(255) NOT NULL, status INTEGER NOT NULL DEFAULT 0, expiry_timestamp BIGINT NOT NULL, created_at timestamptz NOT NULL DEFAULT NOW(), FOREIGN KEY (device_id) REFERENCES devices(uuid) ON DELETE CASCADE)")
        .execute(&db_pool)
        .await?;

    // Add columns if not exists (for migration)
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS user_id VARCHAR(255)")
        .execute(&db_pool)
        .await?;
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS hashed_passphrase VARCHAR(255)")
        .execute(&db_pool)
        .await?;
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS wifi_ssid VARCHAR(255)")
        .execute(&db_pool)
        .await?;
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS backend_url VARCHAR(255)")
        .execute(&db_pool)
        .await?;
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS mqtt_broker_url VARCHAR(255)")
        .execute(&db_pool)
        .await?;
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS mqtt_heartbeat_enable BOOLEAN")
        .execute(&db_pool)
        .await?;
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS mqtt_heartbeat_interval_sec INTEGER")
        .execute(&db_pool)
        .await?;
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS audio_record_timeout_sec INTEGER")
        .execute(&db_pool)
        .await?;
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_timeout_ms INTEGER")
        .execute(&db_pool)
        .await?;
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_state VARCHAR(10)")
        .execute(&db_pool)
        .await?;
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS pairing_timeout_sec INTEGER")
        .execute(&db_pool)
        .await?;
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS locked_down_at timestamptz")
        .execute(&db_pool)
        .await?;
    sqlx::query(
        "ALTER TABLE devices ADD COLUMN IF NOT EXISTS voice_detection_enable BOOLEAN DEFAULT true",
    )
    .execute(&db_pool)
    .await?;
    sqlx::query(
        "ALTER TABLE devices ADD COLUMN IF NOT EXISTS voice_invite_enable BOOLEAN DEFAULT true",
    )
    .execute(&db_pool)
    .await?;
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS voice_threshold FLOAT8 DEFAULT 0.60")
        .execute(&db_pool)
        .await?;
    sqlx::query("ALTER TABLE users ADD COLUMN IF NOT EXISTS voice_embeddings BYTEA")
        .execute(&db_pool)
        .await?;

    // Setup MQTT
    let mut mqtt_options = MqttOptions::new("backend", mqtt_host, mqtt_port);
    if let Some(user) = mqtt_username {
        mqtt_options.set_credentials(user, mqtt_password.unwrap_or_default());
    }
    if mqtt_tls {
        mqtt_options.set_transport(Transport::tls_with_default_config());
    }

    let (mqtt_client, mut eventloop) = AsyncClient::new(mqtt_options, 10);

    // Subscribe to status topics
    mqtt_client
        .subscribe("lockwise/+/status", QoS::AtMostOnce)
        .await?;

    // Spawn MQTT event handler
    let db_pool_clone = db_pool.clone();
    tokio::spawn(async move {
        mqtt::handle_mqtt_events(&db_pool_clone, &mut eventloop).await;
    });

    // Spawn log cleanup task
    let db_pool_cleanup = db_pool.clone();
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(3600)).await; // 1 hour
            let one_month_ago = Utc::now() - chrono::Duration::days(30);
            let _ = sqlx::query("DELETE FROM logs WHERE timestamp < $1")
                .bind(one_month_ago)
                .execute(&db_pool_cleanup)
                .await;
        }
    });

    // Spawn Rocket HTTP server
    tokio::spawn(async move {
        rocket::build()
            .configure(
                rocket::Config::figment()
                    .merge(("port", port))
                    .merge(("address", "0.0.0.0"))
                    .merge(("workers", num_cpus::get())),
            )
            .manage(db_pool)
            .manage(mqtt_client)
            .manage(speechbrain_url)
            .manage(homepage_url)
            .mount(
                "/",
                routes![
                    index,
                    health,
                    device::control_device,
                    device::control_temp_device,
                    device::get_accessible_devices,
                    device::get_device,
                    device::get_devices,
                    device::get_logs,
                    device::get_notifications,
                    device::get_temp_device,
                    device::get_temp_devices_status,
                    device::lockdown_device,
                    device::ping_device,
                    device::ping_temp_device,
                    device::reboot_device,
                    device::register_device,
                    device::unpair_device,
                    device::update_config,
                    device::verify_voice,
                    invite::accept_invite,
                    invite::cancel_invite,
                    invite::create_invite,
                    invite::get_invites,
                    invite::reject_invite,
                    invite::update_invite,
                    user::delete_account,
                    user::delete_voice,
                    user::login_user,
                    user::logout_user,
                    user::register_user,
                    user::register_voice,
                    user::update_password,
                    user::update_phone,
                    user::verify_password,
                    user::voice_status
                ],
            )
            .launch()
            .await
            .unwrap();
    });

    // For now, just keep running
    tokio::signal::ctrl_c().await?;
    Ok(())
}

/// Endpoint raiz que redireciona para a página inicial configurada.
#[get("/")]
fn index(homepage_url: &State<HomepageUrl>) -> rocket::response::Redirect {
    rocket::response::Redirect::found(homepage_url.0.as_str().to_string())
}

/// Endpoint de verificação de saúde retornando "OK".
#[get("/health")]
fn health() -> &'static str {
    "OK"
}
