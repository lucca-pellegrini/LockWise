use argon2::password_hash::PasswordHash;
use argon2::{Argon2, PasswordHasher, PasswordVerifier};
use chrono::{TimeZone, Utc};
use jsonwebtoken::Algorithm;
use reqwest::Client;
use rocket::http::Status;
use rocket::request::{self, FromRequest, Outcome};
use rocket::{Request, State, get, post, routes};
use rumqttc::{AsyncClient, Event, Incoming, MqttOptions, QoS, Transport};
use serde::{Deserialize, Serialize};
use serde_json;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions, PgSslMode};
use sqlx::{ConnectOptions, PgPool};
use std::collections::HashMap;
use std::env;
use std::sync::{Mutex, OnceLock};
use url::Url;
use uuid::Uuid;

static RECENT_COMMANDS: OnceLock<Mutex<HashMap<String, (String, String, i64)>>> = OnceLock::new();

#[derive(Deserialize)]
struct StatusMessage {
    status: String,
    uptime_ms: u64,
    timestamp: u64,
    wifi_ssid: String,
    backend_url: String,
    mqtt_broker_url: String,
    mqtt_heartbeat_enable: bool,
    mqtt_heartbeat_interval_sec: i32,
    audio_record_timeout_sec: i32,
    lock_timeout_ms: i32,
    user_id: String,
    lock_state: Option<String>,
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
    status: String,
    reason: String,
    uptime_ms: u64,
    timestamp: u64,
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

struct AppState {
    db_pool: PgPool,
    mqtt_client: AsyncClient,
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
    let _ = RECENT_COMMANDS.set(Mutex::new(HashMap::new()));

    // Setup DB
    let url = Url::parse(&db_url)?;
    let options = PgConnectOptions::from_url(&url)?.ssl_mode(PgSslMode::Require);
    let db_pool = PgPoolOptions::new()
        .max_connections(5)
        .connect_with(options)
        .await?;

    // Create devices table if not exists
    sqlx::query("CREATE TABLE IF NOT EXISTS devices ( uuid uuid PRIMARY KEY, user_id VARCHAR(255), last_heard timestamptz NOT NULL, uptime_ms bigint NOT NULL, hashed_passphrase VARCHAR(255))")
    .execute(&db_pool)
    .await?;

    // Create users table if not exists
    sqlx::query("CREATE TABLE IF NOT EXISTS users ( firebase_uid VARCHAR(255) PRIMARY KEY, hashed_password VARCHAR(255) NOT NULL, email VARCHAR(255) NOT NULL, phone_number VARCHAR(255), name VARCHAR(255) NOT NULL, current_token VARCHAR(255), created_at timestamptz NOT NULL DEFAULT NOW(), last_login timestamptz)")
    .execute(&db_pool)
    .await?;

    // Create logs table if not exists
    sqlx::query("CREATE TABLE IF NOT EXISTS logs ( id SERIAL PRIMARY KEY, device_id VARCHAR(255) NOT NULL, timestamp timestamptz NOT NULL DEFAULT NOW(), event_type VARCHAR(10) NOT NULL, reason VARCHAR(20) NOT NULL, user_id VARCHAR(255), user_name VARCHAR(255), created_at timestamptz NOT NULL DEFAULT NOW())")
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

    // Setup MQTT
    println!("mqtt_host: {}, mqtt_port: {}", mqtt_host, mqtt_port);
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

    let state = AppState {
        db_pool: db_pool.clone(),
        mqtt_client: mqtt_client.clone(),
    };

    // Spawn MQTT event handler
    tokio::spawn(async move {
        handle_mqtt_events(&state.db_pool, &mut eventloop).await;
    });

    // Spawn Rocket HTTP server
    tokio::spawn(async move {
        rocket::build()
            .configure(
                rocket::Config::figment()
                    .merge(("port", port))
                    .merge(("address", "0.0.0.0")),
            )
            .manage(db_pool)
            .manage(mqtt_client)
            .mount(
                "/",
                routes![
                    health,
                    get_devices,
                    register_user,
                    login_user,
                    logout_user,
                    control_device,
                    unpair_device,
                    get_device,
                    get_logs,
                    register_device
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
                        // Try to parse as StatusMessage (HEARTBEAT)
                        if let Ok(heartbeat) =
                            serde_cbor::from_slice::<StatusMessage>(&publish.payload)
                        {
                            if heartbeat.status == "HEARTBEAT" {
                                let now = Utc::now();
                                let lock_state =
                                    heartbeat.lock_state.as_deref().unwrap_or("UNKNOWN");
                                let _ = sqlx::query(
                                      "INSERT INTO devices (uuid, user_id, last_heard, uptime_ms, wifi_ssid, backend_url, mqtt_broker_url, mqtt_heartbeat_enable, mqtt_heartbeat_interval_sec, audio_record_timeout_sec, lock_timeout_ms, lock_state, hashed_passphrase) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NULL)
                                       ON CONFLICT (uuid) DO UPDATE SET user_id = $2, last_heard = $3, uptime_ms = $4, wifi_ssid = $5, backend_url = $6, mqtt_broker_url = $7, mqtt_heartbeat_enable = $8, mqtt_heartbeat_interval_sec = $9, audio_record_timeout_sec = $10, lock_timeout_ms = $11, lock_state = $12"
                                  )
                                  .bind(uuid)
                                  .bind(&heartbeat.user_id)
                                  .bind(now)
                                  .bind(heartbeat.uptime_ms as i64)
                                  .bind(&heartbeat.wifi_ssid)
                                  .bind(&heartbeat.backend_url)
                                  .bind(&heartbeat.mqtt_broker_url)
                                  .bind(heartbeat.mqtt_heartbeat_enable)
                                  .bind(heartbeat.mqtt_heartbeat_interval_sec)
                                  .bind(heartbeat.audio_record_timeout_sec)
                                  .bind(heartbeat.lock_timeout_ms)
                                  .bind(lock_state)
                                  .execute(db_pool)
                                  .await;
                            }
                        } else if let Ok(lock_msg) =
                            serde_cbor::from_slice::<LockStatusMessage>(&publish.payload)
                        {
                            // LOCK/UNLOCK event
                            let event_type = if lock_msg.status == "LOCKED" {
                                "LOCK"
                            } else {
                                "UNLOCK"
                            };
                            let reason = &lock_msg.reason;
                            let timestamp = Utc
                                .timestamp_millis_opt(lock_msg.timestamp as i64 * 1000)
                                .unwrap();

                            // Check for recent command
                            let (user_id, user_name) = {
                                let commands_mutex = RECENT_COMMANDS.get().unwrap();
                                let mut commands = commands_mutex.lock().unwrap();
                                if let Some((uid, name, cmd_time)) =
                                    commands.get(&uuid_str.to_string())
                                {
                                    let now = Utc::now().timestamp();
                                    if now - cmd_time < 5 {
                                        // within 5 seconds
                                        let uid = uid.clone();
                                        let name = name.clone();
                                        commands.remove(&uuid_str.to_string());
                                        (Some(uid), Some(name))
                                    } else {
                                        (None, None)
                                    }
                                } else {
                                    (None, None)
                                }
                            };

                            // Insert log
                            let _ = sqlx::query(
                                "INSERT INTO logs (device_id, timestamp, event_type, reason, user_id, user_name) VALUES ($1, $2, $3, $4, $5, $6)"
                            )
                            .bind(uuid_str)
                            .bind(timestamp)
                            .bind(event_type)
                            .bind(reason)
                            .bind(&user_id)
                            .bind(&user_name)
                            .execute(db_pool)
                            .await;

                            // Update lock_state
                            let lock_state = if lock_msg.status == "LOCKED" {
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

#[get("/health")]
fn health() -> &'static str {
    "OK"
}

#[get("/devices")]
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

    let rows: Vec<(Uuid, Option<String>, chrono::DateTime<chrono::Utc>, Option<i64>, Option<String>, Option<String>, Option<String>, Option<bool>, Option<i32>, Option<i32>, Option<i32>, Option<String>)> = sqlx::query_as(
        "SELECT uuid, user_id, last_heard, uptime_ms, wifi_ssid, backend_url, mqtt_broker_url, mqtt_heartbeat_enable, mqtt_heartbeat_interval_sec, audio_record_timeout_sec, lock_timeout_ms, lock_state FROM devices WHERE user_id = $1",
    )
    .bind(&firebase_uid)
    .fetch_all(&**db_pool)
    .await
    .map_err(|_| Status::InternalServerError)?;

    let devices: Vec<serde_json::Value> = rows.into_iter().map(|(
        db_uuid,
        db_user_id_opt,
        last_heard,
        uptime_ms,
        wifi_ssid,
        backend_url,
        mqtt_broker_url,
        mqtt_heartbeat_enable,
        mqtt_heartbeat_interval_sec,
        audio_record_timeout_sec,
        lock_timeout_ms,
        lock_state,
    )| {
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
            "lock_state": lock_state
        })
    }).collect();

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

    // Fetch user_id for this uuid to ensure the user owns the device
    let row: Option<(Option<String>,)> =
        sqlx::query_as("SELECT user_id FROM devices WHERE uuid = $1")
            .bind(uuid)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    if let Some((Some(db_user_id),)) = row {
        if request.user_id != db_user_id {
            return Err(Status::Unauthorized);
        }
    } else {
        return Err(Status::Unauthorized); // Device not found
    }

    // Store recent command
    let now = chrono::Utc::now().timestamp();
    let user_name =
        sqlx::query_as::<_, (Option<String>,)>("SELECT name FROM users WHERE firebase_uid = $1")
            .bind(&firebase_uid)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?
            .and_then(|(name,)| name)
            .unwrap_or_else(|| "Unknown".to_string());
    {
        let commands_mutex = RECENT_COMMANDS.get().unwrap();
        let mut commands = commands_mutex.lock().unwrap();
        commands.insert(uuid.to_string(), (firebase_uid.clone(), user_name, now));
    }

    publish_control_message(&**mqtt_client, uuid, request.command.clone())
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

    // Check that the device belongs to this user
    let row: Option<(Uuid, Option<String>, chrono::DateTime<chrono::Utc>, Option<i64>, Option<String>, Option<String>, Option<String>, Option<bool>, Option<i32>, Option<i32>, Option<i32>, Option<String>)> =
        sqlx::query_as("SELECT uuid, user_id, last_heard, uptime_ms, wifi_ssid, backend_url, mqtt_broker_url, mqtt_heartbeat_enable, mqtt_heartbeat_interval_sec, audio_record_timeout_sec, lock_timeout_ms, lock_state FROM devices WHERE uuid = $1")
            .bind(uuid)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    if let Some((
        db_uuid,
        db_user_id_opt,
        last_heard,
        uptime_ms,
        wifi_ssid,
        backend_url,
        mqtt_broker_url,
        mqtt_heartbeat_enable,
        mqtt_heartbeat_interval_sec,
        audio_record_timeout_sec,
        lock_timeout_ms,
        lock_state,
    )) = row
    {
        if let Some(db_user_id) = db_user_id_opt {
            if firebase_uid != db_user_id {
                return Err(Status::Unauthorized);
            }
        } else {
            return Err(Status::NotFound); // Unpaired device
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
            "lock_state": lock_state
        });
        Ok(device.to_string())
    } else {
        Err(Status::NotFound)
    }
}

#[get("/logs/<uuid>")]
async fn get_logs(token: Token, uuid: &str, db_pool: &State<PgPool>) -> Result<String, Status> {
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

    // Get logs
    let logs: Vec<(i32, String, chrono::DateTime<Utc>, String, String, Option<String>, Option<String>)> =
        sqlx::query_as("SELECT id, device_id, timestamp, event_type, reason, user_id, user_name FROM logs WHERE device_id = $1 ORDER BY timestamp DESC")
            .bind(uuid.to_string())
            .fetch_all(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;

    Ok(serde_json::to_string(&logs).unwrap())
}
