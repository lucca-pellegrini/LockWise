use argon2::password_hash::PasswordHash;
use argon2::{Argon2, PasswordHasher, PasswordVerifier};
use base64::Engine;
use chrono::{TimeZone, Utc};
use reqwest::Client;
use rocket::http::Status;
use rocket::request::{self, FromRequest, Outcome};
use rocket::{Request, State, get, post, routes};
use rumqttc::{AsyncClient, Event, Incoming, MqttOptions, QoS, Transport};
use serde::{Deserialize, Serialize};
use sqlx::postgres::{PgConnectOptions, PgPoolOptions, PgSslMode};
use sqlx::{ConnectOptions, PgPool, Row};
use std::collections::HashMap;
use std::env;
use std::sync::{Mutex, OnceLock};
use tokio::io::AsyncReadExt;
use url::Url;
use uuid::Uuid;

struct SpeechbrainUrl(String);
struct HomepageUrl(String);

type RecentCommands = Mutex<HashMap<String, (String, i64)>>;
type PendingPings = Mutex<HashMap<String, (i64, tokio::sync::oneshot::Sender<()>)>>;
type PendingConfigUpdates = Mutex<HashMap<String, tokio::sync::oneshot::Sender<()>>>;

static RECENT_COMMANDS: OnceLock<RecentCommands> = OnceLock::new();
static PENDING_PINGS: OnceLock<PendingPings> = OnceLock::new();
static PENDING_CONFIG_UPDATES: OnceLock<PendingConfigUpdates> = OnceLock::new();

#[derive(Deserialize)]
struct HeartbeatMessage {
    heartbeat: String,
    uptime_ms: u64,
    #[allow(dead_code)]
    timestamp: u64,
    wifi_ssid: String,
    backend_url: String,
    mqtt_broker_url: String,
    mqtt_heartbeat_enable: bool,
    mqtt_heartbeat_interval_sec: i32,
    audio_record_timeout_sec: i32,
    lock_timeout_ms: i32,
    pairing_timeout_sec: i32,
    user_id: String,
    lock_state: Option<String>,
    voice_detection_enable: bool,
}

#[derive(Deserialize)]
struct EventMessage {
    event: String,
    #[allow(dead_code)]
    uptime_ms: u64,
    timestamp: u64,
}

#[derive(Serialize)]
struct ControlMessage {
    command: String,
    // Add other fields as needed
}

#[derive(Deserialize)]
struct ControlRequest {
    command: String,
    user_id: String,
}

#[derive(Deserialize)]
struct LockStatusMessage {
    lock: String,
    reason: String,
    #[allow(dead_code)]
    uptime_ms: u64,
    timestamp: u64,
}

#[derive(Serialize)]
struct LogEntry {
    id: i32,
    device_id: String,
    timestamp: chrono::DateTime<chrono::Utc>,
    event_type: String,
    reason: String,
    user_id: Option<String>,
    user_name: Option<String>,
}

#[derive(sqlx::FromRow, Serialize)]
struct SentInviteInfo {
    id: i32,
    device_id: uuid::Uuid,
    sender_id: String,
    receiver_id: String,
    receiver_name: String,
    receiver_email: String,
    status: i32,
    expiry_timestamp: i64,
    created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(sqlx::FromRow, Serialize)]
struct ReceivedInviteInfo {
    id: i32,
    device_id: uuid::Uuid,
    sender_id: String,
    receiver_id: String,
    sender_name: String,
    sender_email: String,
    status: i32,
    expiry_timestamp: i64,
    created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Deserialize)]
struct UpdateConfigRequest {
    configs: Vec<ConfigItem>,
}

#[derive(Deserialize, Debug)]
struct ConfigItem {
    key: String,
    value: String,
}

#[derive(Deserialize)]
struct RegisterRequest {
    firebase_uid: String,
    password: String,
    email: String,
    phone_number: String,
    name: String,
}

#[derive(Deserialize)]
struct LoginRequest {
    firebase_uid: String,
    password: String,
}

struct Token(String);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for Token {
    type Error = &'static str;

    async fn from_request(req: &'r Request<'_>) -> request::Outcome<Self, Self::Error> {
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

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
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
    let _ = RECENT_COMMANDS.set(Mutex::new(HashMap::new()));
    let _ = PENDING_PINGS.set(Mutex::new(HashMap::new()));
    let _ = PENDING_CONFIG_UPDATES.set(Mutex::new(HashMap::new()));

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
        handle_mqtt_events(&db_pool_clone, &mut eventloop).await;
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
                    get_devices,
                    register_user,
                    login_user,
                    logout_user,
                    control_device,
                    unpair_device,
                    get_device,
                    get_logs,
                    get_notifications,
                    register_device,
                    ping_device,
                    update_config,
                    reboot_device,
                    lockdown_device,
                    update_phone,
                    update_password,
                    delete_account,
                    verify_password,
                    create_invite,
                    get_invites,
                    accept_invite,
                    reject_invite,
                    cancel_invite,
                    update_invite,
                    get_accessible_devices,
                    get_temp_devices_status,
                    get_temp_device,
                    control_temp_device,
                    ping_temp_device,
                    register_voice,
                    delete_voice,
                    verify_voice,
                    voice_status
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

async fn handle_mqtt_events(db_pool: &PgPool, eventloop: &mut rumqttc::EventLoop) {
    loop {
        match eventloop.poll().await {
            Ok(Event::Incoming(Incoming::Publish(publish))) => {
                let topic = publish.topic;
                if topic.starts_with("lockwise/") && topic.ends_with("/status") {
                    let uuid_str = &topic[9..topic.len() - 7]; // extract UUID
                    if let Ok(uuid) = Uuid::parse_str(uuid_str) {
                        // Try to parse as HeartbeatMessage first (has heartbeat field)
                        if let Ok(heartbeat_msg) =
                            serde_cbor::from_slice::<HeartbeatMessage>(&publish.payload)
                        {
                            if heartbeat_msg.heartbeat == "HEARTBEAT" {
                                // Handle HEARTBEAT
                                let now = Utc::now();
                                let lock_state =
                                    heartbeat_msg.lock_state.as_deref().unwrap_or("UNKNOWN");

                                // Check if device is in lockdown and heartbeat is at least 10 seconds after lockdown
                                let should_clear_lockdown = {
                                    let row: Option<(Option<chrono::DateTime<chrono::Utc>>,)> =
                                        sqlx::query_as(
                                            "SELECT locked_down_at FROM devices WHERE uuid = $1",
                                        )
                                        .bind(uuid)
                                        .fetch_optional(db_pool)
                                        .await
                                        .unwrap_or(None);

                                    if let Some((Some(locked_down_at),)) = row {
                                        let duration_since_lockdown = now - locked_down_at;
                                        duration_since_lockdown.num_seconds() >= 10
                                    } else {
                                        false
                                    }
                                };

                                let update_query = if should_clear_lockdown {
                                    "INSERT INTO devices (uuid, user_id, last_heard, uptime_ms, wifi_ssid, backend_url, mqtt_broker_url, mqtt_heartbeat_enable, mqtt_heartbeat_interval_sec, audio_record_timeout_sec, lock_timeout_ms, pairing_timeout_sec, lock_state, voice_detection_enable, hashed_passphrase, locked_down_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, NULL, NULL)
                                          ON CONFLICT (uuid) DO UPDATE SET user_id = $2, last_heard = $3, uptime_ms = $4, wifi_ssid = $5, backend_url = $6, mqtt_broker_url = $7, mqtt_heartbeat_enable = $8, mqtt_heartbeat_interval_sec = $9, audio_record_timeout_sec = $10, lock_timeout_ms = $11, pairing_timeout_sec = $12, lock_state = $13, voice_detection_enable = $14, locked_down_at = NULL"
                                } else {
                                    "INSERT INTO devices (uuid, user_id, last_heard, uptime_ms, wifi_ssid, backend_url, mqtt_broker_url, mqtt_heartbeat_enable, mqtt_heartbeat_interval_sec, audio_record_timeout_sec, lock_timeout_ms, pairing_timeout_sec, lock_state, voice_detection_enable, hashed_passphrase) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, NULL)
                                          ON CONFLICT (uuid) DO UPDATE SET user_id = $2, last_heard = $3, uptime_ms = $4, wifi_ssid = $5, backend_url = $6, mqtt_broker_url = $7, mqtt_heartbeat_enable = $8, mqtt_heartbeat_interval_sec = $9, audio_record_timeout_sec = $10, lock_timeout_ms = $11, pairing_timeout_sec = $12, lock_state = $13, voice_detection_enable = $14"
                                };

                                let _ = sqlx::query(update_query)
                                    .bind(uuid)
                                    .bind(&heartbeat_msg.user_id)
                                    .bind(now)
                                    .bind(heartbeat_msg.uptime_ms as i64)
                                    .bind(&heartbeat_msg.wifi_ssid)
                                    .bind(&heartbeat_msg.backend_url)
                                    .bind(&heartbeat_msg.mqtt_broker_url)
                                    .bind(heartbeat_msg.mqtt_heartbeat_enable)
                                    .bind(heartbeat_msg.mqtt_heartbeat_interval_sec)
                                    .bind(heartbeat_msg.audio_record_timeout_sec)
                                    .bind(heartbeat_msg.lock_timeout_ms)
                                    .bind(heartbeat_msg.pairing_timeout_sec)
                                    .bind(lock_state)
                                    .bind(heartbeat_msg.voice_detection_enable)
                                    .execute(db_pool)
                                    .await;
                            }
                        } else if let Ok(event_msg) =
                            serde_cbor::from_slice::<EventMessage>(&publish.payload)
                        {
                            if event_msg.event == "PONG" {
                                // Handle PONG
                                let pings_mutex = PENDING_PINGS.get().unwrap();
                                let mut pings = pings_mutex.lock().unwrap();
                                if let Some((_, tx)) = pings.remove(&uuid_str.to_string()) {
                                    tx.send(()).ok();
                                }
                            } else if event_msg.event == "CONFIG_UPDATED" {
                                // Handle CONFIG_UPDATED
                                let updates_mutex = PENDING_CONFIG_UPDATES.get().unwrap();
                                let mut updates = updates_mutex.lock().unwrap();
                                if let Some(tx) = updates.remove(&uuid_str.to_string()) {
                                    tx.send(()).ok();
                                }
                            } else if event_msg.event == "LOCKING_DOWN" {
                                // LOCKING_DOWN event - set locked_down_at
                                let timestamp = Utc
                                    .timestamp_millis_opt(event_msg.timestamp as i64 * 1000)
                                    .unwrap();
                                let result = sqlx::query(
                                    "UPDATE devices SET locked_down_at = $1 WHERE uuid = $2",
                                )
                                .bind(timestamp)
                                .bind(uuid)
                                .execute(db_pool)
                                .await;
                                if result.is_ok() {}
                            }
                        } else if let Ok(lock_msg) =
                            serde_cbor::from_slice::<LockStatusMessage>(&publish.payload)
                        {
                            // LOCK/UNLOCK event
                            let event_type = if lock_msg.lock == "LOCKED" {
                                "LOCK"
                            } else {
                                "UNLOCK"
                            };
                            let reason = &lock_msg.reason;
                            let timestamp = Utc
                                .timestamp_millis_opt(lock_msg.timestamp as i64 * 1000)
                                .unwrap();

                            // Check for recent command
                            let user_id = {
                                let commands_mutex = RECENT_COMMANDS.get().unwrap();
                                let mut commands = commands_mutex.lock().unwrap();
                                if let Some((uid, cmd_time)) = commands.get(&uuid_str.to_string()) {
                                    let now = Utc::now().timestamp();
                                    if now - cmd_time < 5 {
                                        // within 5 seconds
                                        let uid = uid.clone();
                                        commands.remove(&uuid_str.to_string());
                                        Some(uid)
                                    } else {
                                        None
                                    }
                                } else {
                                    None
                                }
                            };

                            // Insert log
                            let _ = sqlx::query(
                                       "INSERT INTO logs (device_id, timestamp, event_type, reason, user_id) VALUES ($1, $2, $3, $4, $5)"
                                   )
                                   .bind(uuid_str)
                                   .bind(timestamp)
                                   .bind(event_type)
                                   .bind(reason)
                                   .bind(&user_id)
                                   .execute(db_pool)
                                   .await;

                            // Update lock_state
                            let lock_state = if lock_msg.lock == "LOCKED" {
                                "LOCKED"
                            } else {
                                "UNLOCKED"
                            };
                            let _ =
                                sqlx::query("UPDATE devices SET lock_state = $1 WHERE uuid = $2")
                                    .bind(lock_state)
                                    .bind(uuid_str)
                                    .execute(db_pool)
                                    .await;
                        }
                    }
                }
            }
            Ok(_) => {}
            Err(_) => {}
        }
    }
}

async fn publish_control_message(
    client: &AsyncClient,
    uuid: Uuid,
    command: String,
) -> Result<(), Box<dyn std::error::Error>> {
    let topic = format!("lockwise/{}/control", uuid);
    let msg = ControlMessage { command };
    let payload = serde_cbor::to_vec(&msg)?;
    client
        .publish(topic, QoS::AtMostOnce, false, payload)
        .await?;
    Ok(())
}

#[post("/update_config/<uuid>", data = "<request>")]
async fn update_config(
    token: Token,
    uuid: &str,
    request: rocket::serde::json::Json<UpdateConfigRequest>,
    db_pool: &State<PgPool>,
    mqtt_client: &State<AsyncClient>,
) -> Result<(), Status> {
    let uuid_parsed = Uuid::parse_str(uuid).map_err(|_| Status::BadRequest)?;

    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Check ownership
    let row: Option<(Option<String>,)> =
        sqlx::query_as("SELECT user_id FROM devices WHERE uuid = $1")
            .bind(uuid_parsed)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    if let Some((Some(owner_id),)) = row {
        if firebase_uid != owner_id {
            return Err(Status::Unauthorized);
        }
    } else {
        return Err(Status::NotFound);
    }

    // Validate configs
    for config in &request.configs {
        match config.key.as_str() {
            "wifi_ssid" => {
                if config.value.is_empty() {
                    return Err(Status::BadRequest);
                }
            }
            "wifi_pass" => {} // Allow empty to not change
            "audio_timeout" => {
                let val: i32 = config.value.parse().map_err(|_| Status::BadRequest)?;
                if !(3..=60).contains(&val) {
                    return Err(Status::BadRequest);
                }
            }
            "lock_timeout" => {
                let val: i32 = config.value.parse().map_err(|_| Status::BadRequest)?;
                if !(5000..=300000).contains(&val) {
                    // ms
                    return Err(Status::BadRequest);
                }
            }
            "pairing_timeout" => {
                let val: i32 = config.value.parse().map_err(|_| Status::BadRequest)?;
                if !(60..=600).contains(&val) {
                    return Err(Status::BadRequest);
                }
            }
            "voice_detection_enable" => {
                let val: i32 = config.value.parse().map_err(|_| Status::BadRequest)?;
                if !(0..=1).contains(&val) {
                    return Err(Status::BadRequest);
                }
            }
            "voice_invite_enable" => {
                let val: i32 = config.value.parse().map_err(|_| Status::BadRequest)?;
                if !(0..=1).contains(&val) {
                    return Err(Status::BadRequest);
                }
            }
            "voice_threshold" => {
                let val: f64 = config.value.parse().map_err(|_| Status::BadRequest)?;
                if !(0.20..=0.90).contains(&val) {
                    return Err(Status::BadRequest);
                }
            }
            _ => {
                return Err(Status::BadRequest);
            }
        }
    }

    // Separate backend-only configs from device configs
    let mut backend_configs = Vec::new();
    let mut device_configs = Vec::new();

    for config in &request.configs {
        match config.key.as_str() {
            "voice_threshold" | "voice_invite_enable" => {
                backend_configs.push(config);
            }
            _ => {
                device_configs.push(config);
            }
        }
    }

    // Update backend-only configs directly in database
    for config in backend_configs {
        match config.key.as_str() {
            "voice_threshold" => {
                let threshold: f64 = config.value.parse().map_err(|_| Status::BadRequest)?;
                sqlx::query("UPDATE devices SET voice_threshold = $1 WHERE uuid = $2")
                    .bind(threshold)
                    .bind(uuid_parsed)
                    .execute(&**db_pool)
                    .await
                    .map_err(|_| Status::InternalServerError)?;
            }
            "voice_invite_enable" => {
                let enable: i32 = config.value.parse().map_err(|_| Status::BadRequest)?;
                let enable_bool = enable == 1;
                sqlx::query("UPDATE devices SET voice_invite_enable = $1 WHERE uuid = $2")
                    .bind(enable_bool)
                    .bind(uuid_parsed)
                    .execute(&**db_pool)
                    .await
                    .map_err(|_| Status::InternalServerError)?;
            }
            _ => {} // Should not happen
        }
    }

    // Send device configs to the device
    for config in device_configs {
        let (tx, rx) = tokio::sync::oneshot::channel::<()>();
        {
            let updates_mutex = PENDING_CONFIG_UPDATES.get().unwrap();
            let mut updates = updates_mutex.lock().unwrap();
            updates.insert(uuid.to_string(), tx);
        }

        // Send update_config
        let topic = format!("lockwise/{}/control", uuid);
        let msg = serde_cbor::to_vec(&serde_json::json!({
            "command": "update_config",
            "key": config.key,
            "value": config.value
        }))
        .map_err(|_| Status::InternalServerError)?;
        mqtt_client
            .publish(topic, QoS::AtMostOnce, false, msg)
            .await
            .map_err(|_| Status::InternalServerError)?;

        // Wait for CONFIG_UPDATED, timeout 10s
        match tokio::time::timeout(std::time::Duration::from_secs(10), rx).await {
            Ok(Ok(())) => {}
            Ok(Err(_)) => {
                return Err(Status::InternalServerError);
            }
            Err(_) => {
                return Err(Status::RequestTimeout);
            }
        }
    }

    Ok(())
}

#[post("/reboot/<uuid>")]
async fn reboot_device(
    token: Token,
    uuid: &str,
    db_pool: &State<PgPool>,
    mqtt_client: &State<AsyncClient>,
) -> Result<(), Status> {
    let uuid_parsed = Uuid::parse_str(uuid).map_err(|_| Status::BadRequest)?;

    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Check ownership
    let row: Option<(Option<String>,)> =
        sqlx::query_as("SELECT user_id FROM devices WHERE uuid = $1")
            .bind(uuid_parsed)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    if let Some((Some(owner_id),)) = row {
        if firebase_uid != owner_id {
            return Err(Status::Unauthorized);
        }
    } else {
        return Err(Status::NotFound);
    }

    // Send REBOOT
    publish_control_message(mqtt_client, uuid_parsed, "REBOOT".to_string())
        .await
        .map_err(|_| Status::InternalServerError)?;

    Ok(())
}

#[post("/lockdown/<uuid>")]
async fn lockdown_device(
    token: Token,
    uuid: &str,
    db_pool: &State<PgPool>,
    mqtt_client: &State<AsyncClient>,
) -> Result<(), Status> {
    let uuid_parsed = Uuid::parse_str(uuid).map_err(|_| Status::BadRequest)?;

    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Check ownership
    let row: Option<(Option<String>,)> =
        sqlx::query_as("SELECT user_id FROM devices WHERE uuid = $1")
            .bind(uuid_parsed)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    if let Some((Some(owner_id),)) = row {
        if firebase_uid != owner_id {
            return Err(Status::Unauthorized);
        }
    } else {
        return Err(Status::NotFound);
    }

    // Send LOCKDOWN
    publish_control_message(mqtt_client, uuid_parsed, "LOCKDOWN".to_string())
        .await
        .map_err(|_| Status::InternalServerError)?;

    Ok(())
}

#[post("/ping/<uuid>")]
async fn ping_device(
    token: Token,
    uuid: &str,
    db_pool: &State<PgPool>,
    mqtt_client: &State<AsyncClient>,
) -> Result<(), Status> {
    let uuid_parsed = Uuid::parse_str(uuid).map_err(|_| Status::BadRequest)?;

    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Check ownership or accepted invite
    let row: Option<(Option<String>,)> =
        sqlx::query_as("SELECT user_id FROM devices WHERE uuid = $1")
            .bind(uuid_parsed)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    if let Some((db_user_id_opt,)) = row {
        let has_access = if let Some(db_user_id) = db_user_id_opt {
            // User owns the device
            if firebase_uid == db_user_id {
                true
            } else {
                // Check for accepted, non-expired invite
                let now = Utc::now().timestamp_millis();
                let invite_row: Option<(i32,)> = sqlx::query_as(
                    "SELECT id FROM invites WHERE device_id = $1 AND receiver_id = $2 AND status = 1 AND expiry_timestamp > $3"
                )
                .bind(uuid_parsed)
                .bind(&firebase_uid)
                .bind(now)
                .fetch_optional(&**db_pool)
                .await
                .map_err(|_| Status::InternalServerError)?;
                invite_row.is_some()
            }
        } else {
            false // Unpaired device
        };

        if !has_access {
            return Err(Status::Unauthorized);
        }
    } else {
        return Err(Status::NotFound);
    }

    // Send PING
    publish_control_message(mqtt_client, uuid_parsed, "PING".to_string())
        .await
        .map_err(|_| Status::InternalServerError)?;

    // Wait for PONG
    let (tx, rx) = tokio::sync::oneshot::channel::<()>();
    let start = chrono::Utc::now().timestamp_millis();
    {
        let pings_mutex = PENDING_PINGS.get().unwrap();
        let mut pings = pings_mutex.lock().unwrap();
        pings.insert(uuid.to_string(), (start, tx));
    }

    // Timeout after 10 seconds
    tokio::time::timeout(std::time::Duration::from_secs(10), rx)
        .await
        .map_err(|_| Status::RequestTimeout)?
        .map_err(|_| Status::InternalServerError)?;

    Ok(())
}

#[get("/")]
fn index(homepage_url: &State<HomepageUrl>) -> rocket::response::Redirect {
    rocket::response::Redirect::found(homepage_url.0.as_str().to_string())
}

#[get("/health")]
fn health() -> &'static str {
    "OK"
}

#[get("/devices")]
// Updated get_devices to include pairing_timeout_sec
async fn get_devices(token: Token, db_pool: &State<PgPool>) -> Result<String, Status> {
    // Validate token: get firebase_uid from current_token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    let rows = sqlx::query(
        "SELECT uuid, user_id, last_heard, uptime_ms, wifi_ssid, backend_url, mqtt_broker_url, mqtt_heartbeat_enable, mqtt_heartbeat_interval_sec, audio_record_timeout_sec, lock_timeout_ms, pairing_timeout_sec, lock_state, locked_down_at, voice_detection_enable, voice_invite_enable, voice_threshold FROM devices WHERE user_id = $1",
    )
    .bind(&firebase_uid)
    .fetch_all(&**db_pool)
    .await
    .map_err(|_| Status::InternalServerError)?;

    let devices: Vec<serde_json::Value> = rows
        .into_iter()
        .map(|row| {
            let db_uuid: Uuid = row.get(0);
            let last_heard: chrono::DateTime<chrono::Utc> = row.get(2);
            let uptime_ms: Option<i64> = row.get(3);
            let wifi_ssid: Option<String> = row.get(4);
            let backend_url: Option<String> = row.get(5);
            let mqtt_broker_url: Option<String> = row.get(6);
            let mqtt_heartbeat_enable: Option<bool> = row.get(7);
            let mqtt_heartbeat_interval_sec: Option<i32> = row.get(8);
            let audio_record_timeout_sec: Option<i32> = row.get(9);
            let lock_timeout_ms: Option<i32> = row.get(10);
            let pairing_timeout_sec: Option<i32> = row.get(11);
            let lock_state: Option<String> = row.get(12);
            let locked_down_at: Option<chrono::DateTime<chrono::Utc>> = row.get(13);
            let voice_detection_enable: Option<bool> = row.get(14);
            let voice_invite_enable: Option<bool> = row.get(15);
            let voice_threshold: Option<f64> = row.get(16);
            serde_json::json!({
                "uuid": db_uuid.to_string(),
                "user_id": firebase_uid,
                "last_heard": last_heard.timestamp_millis(),
                "uptime_ms": uptime_ms,
                "wifi_ssid": wifi_ssid,
                "backend_url": backend_url,
                "mqtt_broker_url": mqtt_broker_url,
                "mqtt_heartbeat_enable": mqtt_heartbeat_enable,
                "mqtt_heartbeat_interval_sec": mqtt_heartbeat_interval_sec,
                "audio_record_timeout_sec": audio_record_timeout_sec,
                "lock_timeout_ms": lock_timeout_ms,
                "pairing_timeout_sec": pairing_timeout_sec,
                "lock_state": lock_state,
                "locked_down_at": locked_down_at.map(|dt| dt.timestamp_millis()),
                "voice_detection_enable": voice_detection_enable,
                "voice_invite_enable": voice_invite_enable,
                "voice_threshold": voice_threshold
            })
        })
        .collect();

    Ok(serde_json::to_string(&devices).unwrap())
}

#[derive(Deserialize)]
struct RegisterDeviceRequest {
    device_id: String,
    user_key: String,
    user_id: String,
}

#[post("/register", data = "<request>")]
async fn register_user(
    request: rocket::serde::json::Json<RegisterRequest>,
    db_pool: &State<PgPool>,
) -> Result<(), Status> {
    // Hash the password
    let salt =
        argon2::password_hash::SaltString::generate(&mut argon2::password_hash::rand_core::OsRng);
    let argon2 = Argon2::default();
    let hashed_password = argon2
        .hash_password(request.password.as_bytes(), &salt)
        .map_err(|_| Status::InternalServerError)?
        .to_string();

    // Insert user
    sqlx::query(
        "INSERT INTO users (firebase_uid, hashed_password, email, phone_number, name, created_at) VALUES ($1, $2, $3, $4, $5, NOW())"
    )
    .bind(&request.firebase_uid)
    .bind(&hashed_password)
    .bind(&request.email)
    .bind(&request.phone_number)
    .bind(&request.name)
    .execute(&**db_pool)
    .await
    .map_err(|_| Status::InternalServerError)?;

    Ok(())
}

#[post("/login", data = "<request>")]
async fn login_user(
    request: rocket::serde::json::Json<LoginRequest>,
    db_pool: &State<PgPool>,
) -> Result<String, Status> {
    // Fetch user
    let row: Option<(String,)> =
        sqlx::query_as("SELECT hashed_password FROM users WHERE firebase_uid = $1")
            .bind(&request.firebase_uid)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;

    if let Some((hashed_password,)) = row {
        let parsed_hash = PasswordHash::new(&hashed_password);
        if let Ok(hash) = parsed_hash {
            let argon2 = Argon2::default();
            if argon2
                .verify_password(request.password.as_bytes(), &hash)
                .is_ok()
            {
                // Generate token
                let token = Uuid::new_v4().to_string();
                // Invalidate old token and set new
                sqlx::query("UPDATE users SET current_token = $1, last_login = NOW() WHERE firebase_uid = $2")
                    .bind(&token)
                    .bind(&request.firebase_uid)
                    .execute(&**db_pool)
                    .await
                    .map_err(|_| Status::InternalServerError)?;
                return Ok(token);
            }
        }
    }
    Err(Status::Unauthorized)
}

#[post("/logout")]
async fn logout_user(token: Token, db_pool: &State<PgPool>) -> Result<(), Status> {
    sqlx::query("UPDATE users SET current_token = NULL WHERE firebase_uid = $1")
        .bind(token.0)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;
    Ok(())
}

#[post("/register_device", data = "<request>")]
async fn register_device(
    request: rocket::serde::json::Json<RegisterDeviceRequest>,
    db_pool: &State<PgPool>,
) -> Result<(), Status> {
    let device_uuid = Uuid::parse_str(&request.device_id).map_err(|_| Status::BadRequest)?;

    // Hash the user key
    let salt =
        argon2::password_hash::SaltString::generate(&mut argon2::password_hash::rand_core::OsRng);
    let argon2 = Argon2::default();
    let hashed_key = argon2
        .hash_password(request.user_key.as_bytes(), &salt)
        .map_err(|_| Status::InternalServerError)?
        .to_string();

    // Insert or update device
    sqlx::query(
        "INSERT INTO devices (uuid, user_id, hashed_passphrase, last_heard, uptime_ms) VALUES ($1, $2, $3, NOW(), 0)
         ON CONFLICT (uuid) DO UPDATE SET user_id = $2, hashed_passphrase = $3, last_heard = NOW()"
    )
    .bind(device_uuid)
    .bind(&request.user_id)
    .bind(&hashed_key)
    .execute(&**db_pool)
    .await
    .map_err(|_| Status::InternalServerError)?;

    // Remove any logs from previous owners
    sqlx::query("DELETE FROM logs WHERE device_id = $1")
        .bind(device_uuid.to_string())
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    // Remove any invites from previous owners
    sqlx::query("DELETE FROM invites WHERE device_id = $1")
        .bind(device_uuid)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    Ok(())
}

#[post("/control/<uuid>", data = "<request>")]
async fn control_device(
    token: Token,
    uuid: &str,
    request: rocket::serde::json::Json<ControlRequest>,
    db_pool: &State<PgPool>,
    mqtt_client: &State<AsyncClient>,
) -> Result<(), Status> {
    let uuid = Uuid::parse_str(uuid).map_err(|_| Status::BadRequest)?;

    // Validate token: get firebase_uid from current_token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Check Firebase UID matches request user_id
    if firebase_uid != request.user_id {
        return Err(Status::Unauthorized);
    }

    // Check if user owns the device OR has an accepted, non-expired invite
    let device_row: Option<(Option<String>,)> =
        sqlx::query_as("SELECT user_id FROM devices WHERE uuid = $1")
            .bind(uuid)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;

    let has_access = if let Some((Some(owner_id),)) = device_row {
        // User owns the device
        if request.user_id == owner_id {
            true
        } else {
            // Check for accepted, non-expired invite
            let now = Utc::now().timestamp_millis();
            let invite_row: Option<(i32,)> = sqlx::query_as(
                "SELECT id FROM invites WHERE device_id = $1 AND receiver_id = $2 AND status = 1 AND expiry_timestamp > $3"
            )
            .bind(uuid)
            .bind(&request.user_id)
            .bind(now)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
            invite_row.is_some()
        }
    } else {
        false // Device not found
    };

    if !has_access {
        return Err(Status::Unauthorized);
    }

    // Store recent command
    let now = chrono::Utc::now().timestamp();
    {
        let commands_mutex = RECENT_COMMANDS.get().unwrap();
        let mut commands = commands_mutex.lock().unwrap();
        commands.insert(uuid.to_string(), (firebase_uid.clone(), now));
    }

    publish_control_message(mqtt_client, uuid, request.command.clone())
        .await
        .map_err(|_| Status::InternalServerError)?;
    Ok(())
}

#[post("/unpair/<uuid>")]
async fn unpair_device(token: Token, uuid: &str, db_pool: &State<PgPool>) -> Result<(), Status> {
    let uuid = Uuid::parse_str(uuid).map_err(|_| Status::BadRequest)?;

    // Validate token: get firebase_uid from current_token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Check that the device belongs to this user
    let row: Option<(Option<String>,)> =
        sqlx::query_as("SELECT user_id FROM devices WHERE uuid = $1")
            .bind(uuid)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    if let Some((Some(db_user_id),)) = row {
        if firebase_uid != db_user_id {
            return Err(Status::Unauthorized);
        }
    } else {
        return Err(Status::Unauthorized); // Device not found
    }

    // Unpair: set user_id to NULL
    sqlx::query("UPDATE devices SET user_id = NULL WHERE uuid = $1")
        .bind(uuid)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    // Remove all logs for this device
    sqlx::query("DELETE FROM logs WHERE device_id = $1")
        .bind(uuid.to_string())
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    // Remove all invites for this device
    sqlx::query("DELETE FROM invites WHERE device_id = $1")
        .bind(uuid)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    Ok(())
}

#[get("/device/<uuid>")]
async fn get_device(token: Token, uuid: &str, db_pool: &State<PgPool>) -> Result<String, Status> {
    let uuid = Uuid::parse_str(uuid).map_err(|_| Status::BadRequest)?;

    // Validate token: get firebase_uid from current_token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Check that the device belongs to this user or has accepted invite
    let row = sqlx::query("SELECT uuid, user_id, last_heard, uptime_ms, wifi_ssid, backend_url, mqtt_broker_url, mqtt_heartbeat_enable, mqtt_heartbeat_interval_sec, audio_record_timeout_sec, lock_timeout_ms, pairing_timeout_sec, lock_state, locked_down_at, voice_detection_enable, voice_invite_enable, voice_threshold FROM devices WHERE uuid = $1")
            .bind(uuid)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    if let Some(row) = row {
        let db_uuid: Uuid = row.get(0);
        let db_user_id_opt: Option<String> = row.get(1);
        let last_heard: chrono::DateTime<chrono::Utc> = row.get(2);
        let uptime_ms: Option<i64> = row.get(3);
        let wifi_ssid: Option<String> = row.get(4);
        let backend_url: Option<String> = row.get(5);
        let mqtt_broker_url: Option<String> = row.get(6);
        let mqtt_heartbeat_enable: Option<bool> = row.get(7);
        let mqtt_heartbeat_interval_sec: Option<i32> = row.get(8);
        let audio_record_timeout_sec: Option<i32> = row.get(9);
        let lock_timeout_ms: Option<i32> = row.get(10);
        let pairing_timeout_sec: Option<i32> = row.get(11);
        let lock_state: Option<String> = row.get(12);
        let locked_down_at: Option<chrono::DateTime<chrono::Utc>> = row.get(13);
        let voice_detection_enable: Option<bool> = row.get(14);
        let voice_invite_enable: Option<bool> = row.get(15);
        let voice_threshold: Option<f64> = row.get(16);

        let has_access = if let Some(db_user_id) = db_user_id_opt {
            // User owns the device
            if firebase_uid == db_user_id {
                true
            } else {
                // Check for accepted, non-expired invite
                let now = Utc::now().timestamp_millis();
                let invite_row: Option<(i32,)> = sqlx::query_as(
                    "SELECT id FROM invites WHERE device_id = $1 AND receiver_id = $2 AND status = 1 AND expiry_timestamp > $3"
                )
                .bind(uuid)
                .bind(&firebase_uid)
                .bind(now)
                .fetch_optional(&**db_pool)
                .await
                .map_err(|_| Status::InternalServerError)?;
                invite_row.is_some()
            }
        } else {
            false // Unpaired device
        };

        if !has_access {
            return Err(Status::Unauthorized);
        }
        let device = serde_json::json!({
            "uuid": db_uuid.to_string(),
            "user_id": firebase_uid,
            "last_heard": last_heard.timestamp_millis(),
            "uptime_ms": uptime_ms,
            "wifi_ssid": wifi_ssid,
            "backend_url": backend_url,
            "mqtt_broker_url": mqtt_broker_url,
            "mqtt_heartbeat_enable": mqtt_heartbeat_enable,
            "mqtt_heartbeat_interval_sec": mqtt_heartbeat_interval_sec,
            "audio_record_timeout_sec": audio_record_timeout_sec,
            "lock_timeout_ms": lock_timeout_ms,
            "pairing_timeout_sec": pairing_timeout_sec,
            "lock_state": lock_state,
            "locked_down_at": locked_down_at.map(|dt| dt.timestamp_millis()),
            "voice_detection_enable": voice_detection_enable,
            "voice_invite_enable": voice_invite_enable,
            "voice_threshold": voice_threshold
        });
        Ok(device.to_string())
    } else {
        Err(Status::NotFound)
    }
}

#[get("/temp_device/<uuid>")]
async fn get_temp_device(
    token: Token,
    uuid: &str,
    db_pool: &State<PgPool>,
) -> Result<String, Status> {
    let uuid_parsed = Uuid::parse_str(uuid).map_err(|_| Status::BadRequest)?;

    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Check for accepted, non-expired invite
    let now = Utc::now().timestamp_millis();
    let invite_row: Option<(i32,)> = sqlx::query_as(
        "SELECT id FROM invites WHERE device_id = $1 AND receiver_id = $2 AND status = 1 AND expiry_timestamp > $3"
    )
    .bind(uuid_parsed)
    .bind(&firebase_uid)
    .bind(now)
    .fetch_optional(&**db_pool)
    .await
    .map_err(|_| Status::InternalServerError)?;
    if invite_row.is_none() {
        return Err(Status::Unauthorized);
    }

    // Get device data
    let row = sqlx::query("SELECT uuid, user_id, last_heard, uptime_ms, wifi_ssid, backend_url, mqtt_broker_url, mqtt_heartbeat_enable, mqtt_heartbeat_interval_sec, audio_record_timeout_sec, lock_timeout_ms, pairing_timeout_sec, lock_state, locked_down_at, voice_detection_enable, voice_invite_enable, voice_threshold FROM devices WHERE uuid = $1")
            .bind(uuid_parsed)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    if let Some(row) = row {
        let db_uuid: Uuid = row.get(0);
        let last_heard: chrono::DateTime<chrono::Utc> = row.get(2);
        let uptime_ms: Option<i64> = row.get(3);
        let wifi_ssid: Option<String> = row.get(4);
        let backend_url: Option<String> = row.get(5);
        let mqtt_broker_url: Option<String> = row.get(6);
        let mqtt_heartbeat_enable: Option<bool> = row.get(7);
        let mqtt_heartbeat_interval_sec: Option<i32> = row.get(8);
        let audio_record_timeout_sec: Option<i32> = row.get(9);
        let lock_timeout_ms: Option<i32> = row.get(10);
        let pairing_timeout_sec: Option<i32> = row.get(11);
        let lock_state: Option<String> = row.get(12);
        let locked_down_at: Option<chrono::DateTime<chrono::Utc>> = row.get(13);
        let voice_detection_enable: Option<bool> = row.get(14);
        let voice_invite_enable: Option<bool> = row.get(15);
        let voice_threshold: Option<f64> = row.get(16);

        let device = serde_json::json!({
            "uuid": db_uuid.to_string(),
            "user_id": firebase_uid,
            "last_heard": last_heard.timestamp_millis(),
            "uptime_ms": uptime_ms,
            "wifi_ssid": wifi_ssid,
            "backend_url": backend_url,
            "mqtt_broker_url": mqtt_broker_url,
            "mqtt_heartbeat_enable": mqtt_heartbeat_enable,
            "mqtt_heartbeat_interval_sec": mqtt_heartbeat_interval_sec,
            "audio_record_timeout_sec": audio_record_timeout_sec,
            "lock_timeout_ms": lock_timeout_ms,
            "pairing_timeout_sec": pairing_timeout_sec,
            "lock_state": lock_state,
            "locked_down_at": locked_down_at.map(|dt| dt.timestamp_millis()),
            "voice_detection_enable": voice_detection_enable,
            "voice_invite_enable": voice_invite_enable,
            "voice_threshold": voice_threshold
        });
        Ok(device.to_string())
    } else {
        Err(Status::NotFound)
    }
}

#[post("/temp_control/<uuid>", data = "<request>")]
async fn control_temp_device(
    token: Token,
    uuid: &str,
    request: rocket::serde::json::Json<ControlRequest>,
    db_pool: &State<PgPool>,
    mqtt_client: &State<AsyncClient>,
) -> Result<(), Status> {
    let uuid_parsed = Uuid::parse_str(uuid).map_err(|_| Status::BadRequest)?;

    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Check Firebase UID matches request user_id
    if firebase_uid != request.user_id {
        return Err(Status::Unauthorized);
    }

    // Check for accepted, non-expired invite
    let now = Utc::now().timestamp_millis();
    let invite_row: Option<(i32,)> = sqlx::query_as(
        "SELECT id FROM invites WHERE device_id = $1 AND receiver_id = $2 AND status = 1 AND expiry_timestamp > $3"
    )
    .bind(uuid_parsed)
    .bind(&request.user_id)
    .bind(now)
    .fetch_optional(&**db_pool)
    .await
    .map_err(|_| Status::InternalServerError)?;
    if invite_row.is_none() {
        return Err(Status::Unauthorized);
    }

    // Store recent command
    let now_ts = chrono::Utc::now().timestamp();
    {
        let commands_mutex = RECENT_COMMANDS.get().unwrap();
        let mut commands = commands_mutex.lock().unwrap();
        commands.insert(uuid.to_string(), (firebase_uid.clone(), now_ts));
    }

    publish_control_message(mqtt_client, uuid_parsed, request.command.clone())
        .await
        .map_err(|_| Status::InternalServerError)?;
    Ok(())
}

#[post("/temp_ping/<uuid>")]
async fn ping_temp_device(
    token: Token,
    uuid: &str,
    db_pool: &State<PgPool>,
    mqtt_client: &State<AsyncClient>,
) -> Result<(), Status> {
    let uuid_parsed = Uuid::parse_str(uuid).map_err(|_| Status::BadRequest)?;

    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Check for accepted, non-expired invite
    let now = Utc::now().timestamp_millis();
    let invite_row: Option<(i32,)> = sqlx::query_as(
        "SELECT id FROM invites WHERE device_id = $1 AND receiver_id = $2 AND status = 1 AND expiry_timestamp > $3"
    )
    .bind(uuid_parsed)
    .bind(&firebase_uid)
    .bind(now)
    .fetch_optional(&**db_pool)
    .await
    .map_err(|_| Status::InternalServerError)?;
    if invite_row.is_none() {
        return Err(Status::Unauthorized);
    }

    // Send PING
    publish_control_message(mqtt_client, uuid_parsed, "PING".to_string())
        .await
        .map_err(|_| Status::InternalServerError)?;

    // Wait for PONG
    let (tx, rx) = tokio::sync::oneshot::channel::<()>();
    let start = chrono::Utc::now().timestamp_millis();
    {
        let pings_mutex = PENDING_PINGS.get().unwrap();
        let mut pings = pings_mutex.lock().unwrap();
        pings.insert(uuid.to_string(), (start, tx));
    }

    // Timeout after 10 seconds
    tokio::time::timeout(std::time::Duration::from_secs(10), rx)
        .await
        .map_err(|_| Status::RequestTimeout)?
        .map_err(|_| Status::InternalServerError)?;
    Ok(())
}

#[get("/temp_devices_status")]
async fn get_temp_devices_status(token: Token, db_pool: &State<PgPool>) -> Result<String, Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    let rows = sqlx::query(
        "SELECT d.uuid, d.user_id, d.last_heard, d.uptime_ms, d.wifi_ssid, d.backend_url, d.mqtt_broker_url, d.mqtt_heartbeat_enable, d.mqtt_heartbeat_interval_sec, d.audio_record_timeout_sec, d.lock_timeout_ms, d.pairing_timeout_sec, d.lock_state, d.locked_down_at, d.voice_detection_enable, d.voice_invite_enable, d.voice_threshold FROM devices d JOIN invites i ON d.uuid = i.device_id WHERE i.receiver_id = $1 AND i.status = 1 AND i.expiry_timestamp > $2"
    )
    .bind(&firebase_uid)
    .bind(Utc::now().timestamp_millis())
    .fetch_all(&**db_pool)
    .await
    .map_err(|_| Status::InternalServerError)?;

    let devices: Vec<serde_json::Value> = rows
        .into_iter()
        .map(|row| {
            let db_uuid: Uuid = row.get(0);
            let last_heard: chrono::DateTime<chrono::Utc> = row.get(2);
            let uptime_ms: Option<i64> = row.get(3);
            let wifi_ssid: Option<String> = row.get(4);
            let backend_url: Option<String> = row.get(5);
            let mqtt_broker_url: Option<String> = row.get(6);
            let mqtt_heartbeat_enable: Option<bool> = row.get(7);
            let mqtt_heartbeat_interval_sec: Option<i32> = row.get(8);
            let audio_record_timeout_sec: Option<i32> = row.get(9);
            let lock_timeout_ms: Option<i32> = row.get(10);
            let pairing_timeout_sec: Option<i32> = row.get(11);
            let lock_state: Option<String> = row.get(12);
            let locked_down_at: Option<chrono::DateTime<chrono::Utc>> = row.get(13);
            let voice_detection_enable: Option<bool> = row.get(14);
            let voice_invite_enable: Option<bool> = row.get(15);
            let voice_threshold: Option<f64> = row.get(16);
            serde_json::json!({
                "uuid": db_uuid.to_string(),
                "user_id": firebase_uid,
                "last_heard": last_heard.timestamp_millis(),
                "uptime_ms": uptime_ms,
                "wifi_ssid": wifi_ssid,
                "backend_url": backend_url,
                "mqtt_broker_url": mqtt_broker_url,
                "mqtt_heartbeat_enable": mqtt_heartbeat_enable,
                "mqtt_heartbeat_interval_sec": mqtt_heartbeat_interval_sec,
                "audio_record_timeout_sec": audio_record_timeout_sec,
                "lock_timeout_ms": lock_timeout_ms,
                "pairing_timeout_sec": pairing_timeout_sec,
                "lock_state": lock_state,
                "locked_down_at": locked_down_at.map(|dt| dt.timestamp_millis()),
                "voice_detection_enable": voice_detection_enable,
                "voice_invite_enable": voice_invite_enable,
                "voice_threshold": voice_threshold
            })
        })
        .collect();

    Ok(serde_json::to_string(&devices).unwrap())
}

#[get("/logs/<uuid>")]
async fn get_logs(token: Token, uuid: &str, db_pool: &State<PgPool>) -> Result<String, Status> {
    let uuid_parsed = Uuid::parse_str(uuid).map_err(|_| Status::BadRequest)?;

    // Validate token: get firebase_uid from current_token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => {
            return Err(Status::Unauthorized);
        }
    };

    // Check that the device belongs to this user (logs only for owners)
    let row: Option<(Option<String>,)> =
        sqlx::query_as("SELECT user_id FROM devices WHERE uuid = $1")
            .bind(uuid_parsed)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    if let Some((Some(db_user_id),)) = row {
        if firebase_uid != db_user_id {
            return Err(Status::Unauthorized);
        }
    } else {
        return Err(Status::Unauthorized); // Device not found or not owned
    }

    // Get logs, limit to 1000
    let rows = sqlx::query("SELECT l.id, l.device_id, l.timestamp, l.event_type, l.reason, l.user_id, u.name as user_name FROM logs l LEFT JOIN users u ON l.user_id = u.firebase_uid WHERE l.device_id = $1 ORDER BY l.timestamp DESC LIMIT 1000")
        .bind(uuid_parsed.to_string())
        .fetch_all(&**db_pool)
        .await
        .map_err(|_| {
            Status::InternalServerError
        })?;
    let logs: Vec<LogEntry> = rows
        .into_iter()
        .map(|row| LogEntry {
            id: row.get(0),
            device_id: row.get(1),
            timestamp: row.get(2),
            event_type: row.get(3),
            reason: row.get(4),
            user_id: row.get(5),
            user_name: row.get(6),
        })
        .collect();

    Ok(serde_json::to_string(&logs).unwrap())
}

#[get("/notifications?<devices>")]
async fn get_notifications(
    token: Token,
    devices: Option<String>,
    db_pool: &State<PgPool>,
) -> Result<String, Status> {
    // Validate token: get firebase_uid from current_token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => {
            return Err(Status::Unauthorized);
        }
    };

    // Get logs for owned devices, optionally filtered by devices list
    let logs: Vec<LogEntry> = if let Some(devices_str) = devices {
        let device_uuids: Vec<Uuid> = devices_str
            .split(',')
            .filter_map(|s| Uuid::parse_str(s.trim()).ok())
            .collect();
        if device_uuids.is_empty() {
            let rows = sqlx::query("SELECT l.id, l.device_id, l.timestamp, l.event_type, l.reason, l.user_id, u.name as user_name FROM logs l LEFT JOIN users u ON l.user_id = u.firebase_uid WHERE l.device_id IN (SELECT uuid::text FROM devices WHERE user_id = $1) ORDER BY l.timestamp DESC LIMIT 1000")
                .bind(firebase_uid)
                .fetch_all(&**db_pool)
                .await
                .map_err(|_| {
                    Status::InternalServerError
                })?;
            rows.into_iter()
                .map(|row| LogEntry {
                    id: row.get(0),
                    device_id: row.get(1),
                    timestamp: row.get(2),
                    event_type: row.get(3),
                    reason: row.get(4),
                    user_id: row.get(5),
                    user_name: row.get(6),
                })
                .collect()
        } else {
            let device_strings: Vec<String> = device_uuids.iter().map(|u| u.to_string()).collect();
            let rows = sqlx::query("SELECT l.id, l.device_id, l.timestamp, l.event_type, l.reason, l.user_id, u.name as user_name FROM logs l LEFT JOIN users u ON l.user_id = u.firebase_uid WHERE l.device_id IN (SELECT uuid::text FROM devices WHERE user_id = $1) AND l.device_id = ANY($2) ORDER BY l.timestamp DESC LIMIT 1000")
                .bind(firebase_uid)
                .bind(&device_strings)
                .fetch_all(&**db_pool)
                .await
                .map_err(|_| {
                    Status::InternalServerError
                })?;
            rows.into_iter()
                .map(|row| LogEntry {
                    id: row.get(0),
                    device_id: row.get(1),
                    timestamp: row.get(2),
                    event_type: row.get(3),
                    reason: row.get(4),
                    user_id: row.get(5),
                    user_name: row.get(6),
                })
                .collect()
        }
    } else {
        let rows = sqlx::query("SELECT l.id, l.device_id, l.timestamp, l.event_type, l.reason, l.user_id, u.name as user_name FROM logs l LEFT JOIN users u ON l.user_id = u.firebase_uid WHERE l.device_id IN (SELECT uuid::text FROM devices WHERE user_id = $1) ORDER BY l.timestamp DESC LIMIT 1000")
            .bind(firebase_uid)
            .fetch_all(&**db_pool)
            .await
            .map_err(|_| {
                Status::InternalServerError
            })?;
        rows.into_iter()
            .map(|row| LogEntry {
                id: row.get(0),
                device_id: row.get(1),
                timestamp: row.get(2),
                event_type: row.get(3),
                reason: row.get(4),
                user_id: row.get(5),
                user_name: row.get(6),
            })
            .collect()
    };

    Ok(serde_json::to_string(&logs).unwrap())
}

#[derive(Deserialize)]
struct UpdatePhoneRequest {
    phone_number: String,
}

#[post("/update_phone", data = "<request>")]
async fn update_phone(
    token: Token,
    request: rocket::serde::json::Json<UpdatePhoneRequest>,
    db_pool: &State<PgPool>,
) -> Result<(), Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Update phone number
    sqlx::query("UPDATE users SET phone_number = $1 WHERE firebase_uid = $2")
        .bind(&request.phone_number)
        .bind(&firebase_uid)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    Ok(())
}

#[derive(Deserialize)]
struct UpdatePasswordRequest {
    password: String,
}

#[post("/update_password", data = "<request>")]
async fn update_password(
    token: Token,
    request: rocket::serde::json::Json<UpdatePasswordRequest>,
    db_pool: &State<PgPool>,
) -> Result<(), Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Hash the new password
    let salt =
        argon2::password_hash::SaltString::generate(&mut argon2::password_hash::rand_core::OsRng);
    let argon2 = Argon2::default();
    let hashed_password = argon2
        .hash_password(request.password.as_bytes(), &salt)
        .map_err(|_| Status::InternalServerError)?
        .to_string();

    // Update password
    sqlx::query("UPDATE users SET hashed_password = $1 WHERE firebase_uid = $2")
        .bind(&hashed_password)
        .bind(&firebase_uid)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    Ok(())
}

#[post("/delete_account")]
async fn delete_account(token: Token, db_pool: &State<PgPool>) -> Result<(), Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Unpair all devices owned by this user
    sqlx::query("UPDATE devices SET user_id = NULL WHERE user_id = $1")
        .bind(&firebase_uid)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    // Delete all logs for devices owned by this user
    sqlx::query("DELETE FROM logs WHERE user_id = $1")
        .bind(&firebase_uid)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    // Delete all invites sent or received by this user
    sqlx::query("DELETE FROM invites WHERE sender_id = $1 OR receiver_id = $1")
        .bind(&firebase_uid)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    // Delete the user
    sqlx::query("DELETE FROM users WHERE firebase_uid = $1")
        .bind(&firebase_uid)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    Ok(())
}

#[derive(Deserialize)]
struct VerifyPasswordRequest {
    password: String,
}

#[post("/verify_password", data = "<request>")]
async fn verify_password(
    token: Token,
    request: rocket::serde::json::Json<VerifyPasswordRequest>,
    db_pool: &State<PgPool>,
) -> Result<(), Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Get hashed password
    let password_row: Option<(String,)> =
        sqlx::query_as("SELECT hashed_password FROM users WHERE firebase_uid = $1")
            .bind(&firebase_uid)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;

    if let Some((hashed_password,)) = password_row {
        let parsed_hash = PasswordHash::new(&hashed_password);
        if let Ok(hash) = parsed_hash {
            let argon2 = Argon2::default();
            if argon2
                .verify_password(request.password.as_bytes(), &hash)
                .is_ok()
            {
                return Ok(());
            }
        }
    }

    Err(Status::Unauthorized)
}

#[post("/register_voice", data = "<audio_data>")]
async fn register_voice(
    token: Token,
    audio_data: rocket::data::Data<'_>,
    db_pool: &State<PgPool>,
    speechbrain_url: &State<SpeechbrainUrl>,
) -> Result<(), Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => {
            return Err(Status::Unauthorized);
        }
    };

    // Read audio data
    let mut data = Vec::new();
    audio_data
        .open(rocket::data::ByteUnit::max_value())
        .read_to_end(&mut data)
        .await
        .map_err(|_| Status::BadRequest)?;

    if data.is_empty() {
        return Err(Status::BadRequest);
    }

    // Call speechbrain service
    let client = Client::new();
    let base64_data = base64::engine::general_purpose::STANDARD.encode(&data);

    let response = client
        .post(format!("{}/embed", speechbrain_url.0.as_str()))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({
            "pcm_base64": base64_data
        }))
        .send()
        .await
        .map_err(|_| Status::InternalServerError)?;

    if !response.status().is_success() {
        return Err(Status::InternalServerError);
    }

    let embed_response: serde_json::Value = response
        .json()
        .await
        .map_err(|_| Status::InternalServerError)?;

    let embedding_b64 = embed_response["embedding"]
        .as_str()
        .ok_or(Status::InternalServerError)?;

    // Decode base64 to binary data
    let embedding_bytes = base64::engine::general_purpose::STANDARD
        .decode(embedding_b64)
        .map_err(|_| Status::InternalServerError)?;

    println!(
        "DEBUG: Embedding binary length: {} bytes",
        embedding_bytes.len()
    );

    // Store in database
    println!(
        "DEBUG: Storing embedding in database for user {}",
        firebase_uid
    );
    sqlx::query("UPDATE users SET voice_embeddings = $1 WHERE firebase_uid = $2")
        .bind(&embedding_bytes)
        .bind(&firebase_uid)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    Ok(())
}

#[post("/delete_voice")]
async fn delete_voice(token: Token, db_pool: &State<PgPool>) -> Result<(), Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => {
            return Err(Status::Unauthorized);
        }
    };

    // Delete voice embeddings
    sqlx::query("UPDATE users SET voice_embeddings = NULL WHERE firebase_uid = $1")
        .bind(&firebase_uid)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    Ok(())
}

#[post("/verify_voice/<device_id>", data = "<audio_data>")]
async fn verify_voice(
    device_id: &str,
    audio_data: rocket::data::Data<'_>,
    db_pool: &State<PgPool>,
    speechbrain_url: &State<SpeechbrainUrl>,
) -> Result<rocket::serde::json::Json<serde_json::Value>, Status> {
    let device_uuid = Uuid::parse_str(device_id).map_err(|_| Status::BadRequest)?;

    // Get device info including voice_invite_enable and voice_threshold
    let device_row: Option<(Option<String>, Option<bool>, Option<f64>)> = sqlx::query_as(
        "SELECT user_id, voice_invite_enable, voice_threshold FROM devices WHERE uuid = $1",
    )
    .bind(device_uuid)
    .fetch_optional(&**db_pool)
    .await
    .map_err(|_| Status::InternalServerError)?;

    let (user_id, voice_invite_enable, voice_threshold) = match device_row {
        Some((Some(uid), Some(vie), Some(vt))) => {
            println!(
                "DEBUG: Device found, user_id: {}, voice_invite_enable: {}, voice_threshold: {}",
                uid, vie, vt
            );
            (uid, vie, vt)
        }
        _ => {
            return Err(Status::BadRequest);
        }
    };

    // Collect embeddings
    let mut user_embeddings = Vec::new();
    let mut user_ids = Vec::new();

    // Always include owner
    let owner_row: Option<(Option<Vec<u8>>,)> =
        sqlx::query_as("SELECT voice_embeddings FROM users WHERE firebase_uid = $1")
            .bind(&user_id)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;

    if let Some((Some(emb),)) = owner_row {
        println!(
            "DEBUG: Found voice embeddings for owner {} ({} bytes)",
            user_id,
            emb.len()
        );
        user_embeddings.push(base64::engine::general_purpose::STANDARD.encode(&emb));
        user_ids.push(user_id.clone());
    } else {
        return Err(Status::BadRequest); // Owner must have voice registered
    }

    // If voice_invite_enable, include invited users
    if voice_invite_enable {
        let now = Utc::now().timestamp_millis();
        let invite_rows: Vec<(String, Vec<u8>)> = sqlx::query_as(
            "SELECT u.firebase_uid, u.voice_embeddings FROM users u JOIN invites i ON u.firebase_uid = i.receiver_id WHERE i.device_id = $1 AND i.status = 1 AND i.expiry_timestamp > $2 AND u.voice_embeddings IS NOT NULL"
        )
        .bind(device_uuid)
        .bind(now)
        .fetch_all(&**db_pool)
        .await
        .map_err(|_| {
            Status::InternalServerError
        })?;

        for (invite_user_id, emb) in invite_rows {
            println!(
                "DEBUG: Found voice embeddings for invited user {} ({} bytes)",
                invite_user_id,
                emb.len()
            );
            user_embeddings.push(base64::engine::general_purpose::STANDARD.encode(&emb));
            user_ids.push(invite_user_id);
        }
    }

    if user_embeddings.is_empty() {
        return Err(Status::BadRequest);
    }

    println!(
        "DEBUG: Collected {} embeddings from users: {:?}",
        user_embeddings.len(),
        user_ids
    );

    // Read audio data
    let mut data = Vec::new();
    audio_data
        .open(rocket::data::ByteUnit::max_value())
        .read_to_end(&mut data)
        .await
        .map_err(|_| Status::BadRequest)?;

    if data.is_empty() {
        return Err(Status::BadRequest);
    }

    // Call speechbrain service
    println!(
        "DEBUG: Calling speechbrain verify service at {}/verify",
        speechbrain_url.0.as_str()
    );
    let client = Client::new();
    let base64_data = base64::engine::general_purpose::STANDARD.encode(&data);

    let response = client
        .post(format!("{}/verify", speechbrain_url.0.as_str()))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({
            "pcm_base64": base64_data,
            "candidates": user_embeddings
        }))
        .send()
        .await
        .map_err(|_| Status::InternalServerError)?;

    println!(
        "DEBUG: Speechbrain verify response status: {}",
        response.status()
    );

    if !response.status().is_success() {
        return Err(Status::InternalServerError);
    }

    let verify_response: serde_json::Value = response.json().await.map_err(|e| {
        println!(
            "DEBUG: Failed to parse speechbrain verify response: {:?}",
            e
        );
        Status::InternalServerError
    })?;

    let best_index = verify_response["best_index"]
        .as_u64()
        .ok_or(Status::InternalServerError)? as usize;

    let score = verify_response["score"]
        .as_f64()
        .ok_or(Status::InternalServerError)?;

    println!(
        "DEBUG: Verification best_index: {}, score: {}",
        best_index, score
    );

    if score > voice_threshold && best_index < user_ids.len() {
        println!(
            "DEBUG: Score {} > {}, allowing unlock for user at index {}",
            score, voice_threshold, best_index
        );

        let matched_user_id = &user_ids[best_index];

        // Store recent voice verification
        let now = chrono::Utc::now().timestamp();
        {
            let commands_mutex = RECENT_COMMANDS.get().unwrap();
            let mut commands = commands_mutex.lock().unwrap();
            commands.insert(device_id.to_string(), (matched_user_id.clone(), now));
        }

        println!(
            "DEBUG: Stored recent voice verification for user {}",
            matched_user_id
        );
        Ok(rocket::serde::json::Json(
            serde_json::json!({"index": best_index}),
        ))
    } else {
        println!(
            "DEBUG: Score {} <= {} or invalid index {}, denying unlock",
            score, voice_threshold, best_index
        );
        Err(Status::Forbidden)
    }
}

#[derive(Deserialize)]
struct CreateInviteRequest {
    receiver_email: String,
    device_id: String,
    expiry_duration: String, // "2_dias", "1_semana", etc.
}

#[post("/create_invite", data = "<request>")]
async fn create_invite(
    token: Token,
    request: rocket::serde::json::Json<CreateInviteRequest>,
    db_pool: &State<PgPool>,
) -> Result<String, Status> {
    println!(
        "DEBUG: create_invite called with receiver_email: {}, device_id: {}",
        request.receiver_email, request.device_id
    );

    // Parse device_id to UUID
    let device_uuid = match Uuid::parse_str(&request.device_id) {
        Ok(uuid) => uuid,
        Err(_) => {
            return Err(Status::BadRequest);
        }
    };

    // Validate token and get sender
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let sender_id = match user_row {
        Some((uid,)) => uid,
        None => {
            return Err(Status::Unauthorized);
        }
    };

    // Check if sender owns the device
    let device_row: Option<(Option<String>,)> =
        sqlx::query_as("SELECT user_id FROM devices WHERE uuid = $1")
            .bind(device_uuid)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let owner_id = if let Some((Some(owner),)) = device_row {
        owner
    } else {
        return Err(Status::NotFound);
    };
    if owner_id != sender_id {
        println!(
            "DEBUG: User {} does not own device {} (owned by {})",
            sender_id, request.device_id, owner_id
        );
        return Err(Status::Forbidden);
    }

    // Find receiver by email
    let receiver_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE email = $1")
            .bind(&request.receiver_email)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let receiver_id = if let Some((uid,)) = receiver_row {
        uid
    } else {
        println!(
            "DEBUG: Receiver not found for email: {}",
            request.receiver_email
        );
        return Err(Status::NotFound);
    };

    // Check if invite already exists and is pending
    let existing_invite: Option<(i32,)> = sqlx::query_as(
        "SELECT id FROM invites WHERE device_id = $1 AND receiver_id = $2 AND status = 0",
    )
    .bind(device_uuid) // UUID for invites table
    .bind(&receiver_id)
    .fetch_optional(&**db_pool)
    .await
    .map_err(|_| Status::InternalServerError)?;
    if existing_invite.is_some() {
        return Err(Status::Conflict);
    }

    // Calculate expiry timestamp
    let now = Utc::now();
    let expiry_timestamp = calculate_expiry_timestamp(now, &request.expiry_duration);

    // Create invite
    let invite_id: i32 = sqlx::query_scalar(
        "INSERT INTO invites (device_id, sender_id, receiver_id, expiry_timestamp) VALUES ($1, $2, $3, $4) RETURNING id"
    )
    .bind(device_uuid)  // UUID for invites table
    .bind(&sender_id)
    .bind(&receiver_id)
    .bind(expiry_timestamp)
    .fetch_one(&**db_pool)
    .await
    .map_err(|_| {
        Status::InternalServerError
    })?;

    Ok(serde_json::json!({
        "invite_id": invite_id,
        "message": "Invite created successfully"
    })
    .to_string())
}

#[get("/invites")]
async fn get_invites(token: Token, db_pool: &State<PgPool>) -> Result<String, Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let user_id = match user_row {
        Some((uid,)) => uid,
        None => {
            return Err(Status::Unauthorized);
        }
    };

    // Get sent invites with receiver info
    let sent_invites: Vec<SentInviteInfo> =
        sqlx::query_as("SELECT i.id, i.device_id, i.sender_id, i.receiver_id, ru.name as receiver_name, ru.email as receiver_email, i.status, i.expiry_timestamp, i.created_at FROM invites i LEFT JOIN users ru ON i.receiver_id = ru.firebase_uid WHERE i.sender_id = $1")
            .bind(&user_id)
            .fetch_all(&**db_pool)
            .await
            .map_err(|_| {
                Status::InternalServerError
            })?;

    // Get received invites with sender info
    let received_invites: Vec<ReceivedInviteInfo> =
        sqlx::query_as("SELECT i.id, i.device_id, i.sender_id, i.receiver_id, su.name as sender_name, su.email as sender_email, i.status, i.expiry_timestamp, i.created_at FROM invites i LEFT JOIN users su ON i.sender_id = su.firebase_uid WHERE i.receiver_id = $1")
            .bind(&user_id)
            .fetch_all(&**db_pool)
            .await
            .map_err(|_| {
                Status::InternalServerError
            })?;

    let sent: Vec<serde_json::Value> = sent_invites
        .into_iter()
        .map(|invite| serde_json::to_value(invite).unwrap())
        .collect();

    let received: Vec<serde_json::Value> = received_invites
        .into_iter()
        .map(|invite| serde_json::to_value(invite).unwrap())
        .collect();

    Ok(serde_json::json!({
        "sent": sent,
        "received": received
    })
    .to_string())
}

#[post("/accept_invite/<invite_id>")]
async fn accept_invite(
    token: Token,
    invite_id: i32,
    db_pool: &State<PgPool>,
) -> Result<(), Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let user_id = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Update invite status to accepted (1)
    let rows_affected = sqlx::query(
        "UPDATE invites SET status = 1 WHERE id = $1 AND receiver_id = $2 AND status = 0",
    )
    .bind(invite_id)
    .bind(&user_id)
    .execute(&**db_pool)
    .await
    .map_err(|_| Status::InternalServerError)?
    .rows_affected();

    if rows_affected == 0 {
        return Err(Status::NotFound);
    }

    Ok(())
}

#[post("/reject_invite/<invite_id>")]
async fn reject_invite(
    token: Token,
    invite_id: i32,
    db_pool: &State<PgPool>,
) -> Result<(), Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let user_id = match user_row {
        Some((uid,)) => uid,
        None => {
            return Err(Status::Unauthorized);
        }
    };

    // Delete the invite
    println!(
        "DEBUG: Deleting invite with id: {}, receiver_id: {}",
        invite_id, user_id
    );
    let rows_affected = sqlx::query("DELETE FROM invites WHERE id = $1 AND receiver_id = $2")
        .bind(invite_id)
        .bind(&user_id)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?
        .rows_affected();

    if rows_affected == 0 {
        return Err(Status::NotFound);
    }

    println!(
        "DEBUG: Invite deleted successfully, rows affected: {}",
        rows_affected
    );
    Ok(())
}

#[post("/cancel_invite/<invite_id>")]
async fn cancel_invite(
    token: Token,
    invite_id: i32,
    db_pool: &State<PgPool>,
) -> Result<(), Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let user_id = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Delete the invite
    let rows_affected = sqlx::query("DELETE FROM invites WHERE id = $1 AND sender_id = $2")
        .bind(invite_id)
        .bind(&user_id)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;

    if rows_affected.rows_affected() == 0 {
        return Err(Status::NotFound);
    }

    Ok(())
}

#[derive(Deserialize)]
struct UpdateInviteRequest {
    expiry_duration: String,
}

#[post("/update_invite/<invite_id>", data = "<request>")]
async fn update_invite(
    token: Token,
    invite_id: i32,
    request: rocket::serde::json::Json<UpdateInviteRequest>,
    db_pool: &State<PgPool>,
) -> Result<(), Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let user_id = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Calculate new expiry timestamp
    let now = Utc::now();
    let new_expiry_timestamp = calculate_expiry_timestamp(now, &request.expiry_duration);

    // Update invite expiry
    let rows_affected =
        sqlx::query("UPDATE invites SET expiry_timestamp = $1 WHERE id = $2 AND sender_id = $3")
            .bind(new_expiry_timestamp)
            .bind(invite_id)
            .bind(&user_id)
            .execute(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;

    if rows_affected.rows_affected() == 0 {
        return Err(Status::NotFound);
    }

    Ok(())
}

#[get("/accessible_devices")]
async fn get_accessible_devices(token: Token, db_pool: &State<PgPool>) -> Result<String, Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let user_id = match user_row {
        Some((uid,)) => uid,
        None => return Err(Status::Unauthorized),
    };

    // Get accepted invites that haven't expired
    let invites: Vec<(i32, uuid::Uuid, String, i64)> =
        sqlx::query_as("SELECT id, device_id, sender_id, expiry_timestamp FROM invites WHERE receiver_id = $1 AND status = 1 AND expiry_timestamp > $2")
            .bind(&user_id)
            .bind(Utc::now().timestamp_millis())
            .fetch_all(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;

    let devices: Vec<serde_json::Value> = invites
        .into_iter()
        .map(|(id, device_id, sender_id, expiry)| {
            serde_json::json!({
                "id": id,
                "device_id": device_id.to_string(),
                "sender_id": sender_id,
                "expiry_timestamp": expiry
            })
        })
        .collect();

    Ok(serde_json::to_string(&devices).unwrap())
}

#[get("/voice_status")]
async fn voice_status(token: Token, db_pool: &State<PgPool>) -> Result<String, Status> {
    // Validate token
    let user_row: Option<(String,)> =
        sqlx::query_as("SELECT firebase_uid FROM users WHERE current_token = $1")
            .bind(&token.0)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    let firebase_uid = match user_row {
        Some((uid,)) => uid,
        None => {
            return Err(Status::Unauthorized);
        }
    };

    // Check if user has voice embeddings
    let voice_row: Option<(Option<Vec<u8>>,)> =
        sqlx::query_as("SELECT voice_embeddings FROM users WHERE firebase_uid = $1")
            .bind(&firebase_uid)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;

    let has_voice = match voice_row {
        Some((Some(_),)) => true,
        _ => {
            println!(
                "DEBUG: User {} does not have voice embeddings",
                firebase_uid
            );
            false
        }
    };

    Ok(has_voice.to_string())
}

fn calculate_expiry_timestamp(base_time: chrono::DateTime<chrono::Utc>, duration: &str) -> i64 {
    let duration = match duration {
        "2_dias" => chrono::Duration::days(2),
        "1_semana" => chrono::Duration::days(7),
        "2_semanas" => chrono::Duration::days(14),
        "1_mes" => chrono::Duration::days(30),
        "permanente" => chrono::Duration::days(36500), // 100 years
        _ => chrono::Duration::days(7),
    };
    (base_time + duration).timestamp_millis()
}
