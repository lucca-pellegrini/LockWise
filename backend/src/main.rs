use argon2::password_hash::PasswordHash;
use argon2::{Argon2, PasswordHasher, PasswordVerifier};
use chrono::Utc;
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
use std::sync::OnceLock;
use url::Url;
use uuid::Uuid;

static PROJECT_ID: OnceLock<String> = OnceLock::new();

async fn verify_firebase_token(token: &str) -> Result<String, String> {
    let project_id = PROJECT_ID.get().ok_or("Project ID not set")?;
    let header = jsonwebtoken::decode_header(token).map_err(|_| "Invalid token header")?;
    let kid = header.kid.ok_or("No kid in header")?;
    let client = Client::new();
    let keys_text = client
        .get("https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com")
        .send()
        .await
        .map_err(|_| "Failed to fetch keys")?
        .text()
        .await
        .map_err(|_| "Failed to read keys response")?;
    let keys: HashMap<String, String> =
        serde_json::from_str(&keys_text).map_err(|_| "Invalid keys response")?;
    let pem = keys.get(&kid).ok_or("Key not found")?;
    let key = jsonwebtoken::DecodingKey::from_rsa_pem(pem.as_bytes()).map_err(|_| "Invalid key")?;
    let mut validation = jsonwebtoken::Validation::new(Algorithm::RS256);
    validation.set_issuer(&[format!("https://securetoken.google.com/{}", project_id)]);
    validation.set_audience(&[project_id]);
    let token_data = jsonwebtoken::decode::<serde_json::Value>(token, &key, &validation)
        .map_err(|_| "Invalid token")?;
    let uid = token_data.claims["sub"]
        .as_str()
        .ok_or("No sub in claims")?
        .to_string();
    Ok(uid)
}

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
    let firebase_project_id =
        env::var("FIREBASE_PROJECT_ID").expect("FIREBASE_PROJECT_ID must be set");
    let _ = PROJECT_ID.set(firebase_project_id);

    // Setup DB
    println!("db_url: {}", db_url);
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
                        if let Ok(msg) = serde_cbor::from_slice::<StatusMessage>(&publish.payload) {
                            let now = Utc::now();
                            let _ = sqlx::query(
                                  "INSERT INTO devices (uuid, user_id, last_heard, uptime_ms, wifi_ssid, backend_url, mqtt_broker_url, mqtt_heartbeat_enable, mqtt_heartbeat_interval_sec, audio_record_timeout_sec, lock_timeout_ms, hashed_passphrase) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NULL)
                                   ON CONFLICT (uuid) DO UPDATE SET user_id = $2, last_heard = $3, uptime_ms = $4, wifi_ssid = $5, backend_url = $6, mqtt_broker_url = $7, mqtt_heartbeat_enable = $8, mqtt_heartbeat_interval_sec = $9, audio_record_timeout_sec = $10, lock_timeout_ms = $11"
                              )
                              .bind(uuid)
                              .bind(&msg.user_id)
                              .bind(now)
                              .bind(msg.uptime_ms as i64)
                              .bind(&msg.wifi_ssid)
                              .bind(&msg.backend_url)
                              .bind(&msg.mqtt_broker_url)
                              .bind(msg.mqtt_heartbeat_enable)
                              .bind(msg.mqtt_heartbeat_interval_sec)
                              .bind(msg.audio_record_timeout_sec)
                              .bind(msg.lock_timeout_ms)
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
async fn get_devices(db_pool: &State<PgPool>) -> Result<String, Status> {
    let devices: Vec<(Uuid, Option<String>, String, i64)> =
        sqlx::query_as("SELECT uuid, user_id, last_heard, uptime_ms FROM devices")
            .fetch_all(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
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
