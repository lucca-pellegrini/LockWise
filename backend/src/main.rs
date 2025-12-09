use argon2::password_hash::PasswordHash;
use argon2::{Argon2, PasswordVerifier};
use chrono::Utc;
use rocket::http::Status;
use rocket::request::{self, FromRequest, Outcome};
use rocket::{Request, State, get, post, routes};
use rumqttc::{AsyncClient, Event, Incoming, MqttOptions, QoS, Transport};
use serde::{Deserialize, Serialize};
use serde_json;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions, PgSslMode};
use sqlx::{ConnectOptions, PgPool};
use std::env;
use url::Url;
use uuid::Uuid;

#[derive(Deserialize)]
struct StatusMessage {
    status: String,
    uptime_ms: u64,
}

#[derive(Serialize)]
struct ControlMessage {
    command: String,
    // Add other fields as needed
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
                Outcome::Success(Token(auth[7..].to_string()))
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

    // Setup DB
    println!("db_url: {}", db_url);
    let url = Url::parse(&db_url)?;
    let options = PgConnectOptions::from_url(&url)?.ssl_mode(PgSslMode::Require);
    let db_pool = PgPoolOptions::new()
        .max_connections(5)
        .connect_with(options)
        .await?;

    // Create devices table if not exists
    sqlx::query("CREATE TABLE IF NOT EXISTS devices ( uuid uuid PRIMARY KEY, last_heard timestamptz NOT NULL, uptime_ms bigint NOT NULL, hashed_passphrase VARCHAR(255))")
    .execute(&db_pool)
    .await?;

    // Add column if not exists (for migration)
    sqlx::query("ALTER TABLE devices ADD COLUMN IF NOT EXISTS hashed_passphrase VARCHAR(255)")
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
            .manage(db_pool)
            .manage(mqtt_client)
            .mount("/", routes![health, get_devices, control_device])
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
                                 "INSERT INTO devices (uuid, last_heard, uptime_ms, hashed_passphrase) VALUES ($1, $2, $3, NULL)
                                  ON CONFLICT (uuid) DO UPDATE SET last_heard = $2, uptime_ms = $3"
                             )
                             .bind(uuid)
                             .bind(now)
                             .bind(msg.uptime_ms as i64)
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
    let devices: Vec<(Uuid, String, i64)> =
        sqlx::query_as("SELECT uuid, last_heard, uptime_ms FROM devices")
            .fetch_all(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    Ok(serde_json::to_string(&devices).unwrap())
}

#[post("/control/<uuid>", data = "<command>")]
async fn control_device(
    token: Token,
    uuid: &str,
    command: String,
    db_pool: &State<PgPool>,
    mqtt_client: &State<AsyncClient>,
) -> Result<(), Status> {
    let uuid = Uuid::parse_str(uuid).map_err(|_| Status::BadRequest)?;

    // Fetch hashed passphrase for this uuid
    let row: Option<(Option<String>,)> =
        sqlx::query_as("SELECT hashed_passphrase FROM devices WHERE uuid = $1")
            .bind(uuid)
            .fetch_optional(&**db_pool)
            .await
            .map_err(|_| Status::InternalServerError)?;
    if let Some((Some(hashed),)) = row {
        let parsed_hash = PasswordHash::new(&hashed);
        if let Ok(hash) = parsed_hash {
            let argon2 = Argon2::default();
            if argon2.verify_password(token.0.as_bytes(), &hash).is_err() {
                return Err(Status::Unauthorized);
            }
        } else {
            return Err(Status::Unauthorized);
        }
    } else {
        return Err(Status::Unauthorized); // No hash set or device not found
    }

    publish_control_message(&**mqtt_client, uuid, command)
        .await
        .map_err(|_| Status::InternalServerError)?;
    Ok(())
}
