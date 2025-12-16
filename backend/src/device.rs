use anyhow::Result;
use argon2::{Argon2, PasswordHasher};
use base64::Engine;
use chrono::Utc;
use reqwest::Client;
use rocket::http::Status;
use rocket::{State, get, post};
use rumqttc::{AsyncClient, QoS};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use tokio::io::AsyncReadExt;
use uuid::Uuid;

use super::SpeechbrainUrl;
use super::Token;
use super::mqtt::publish_control_message;

/// Estrutura de requisição para control API endpoints
#[derive(Deserialize)]
pub struct ControlRequest {
    /// O comando a executar (LOCK/UNLOCK)
    command: String,
    /// ID do usuário fazendo a requisição
    user_id: String,
}

/// Estrutura de mensagem para atualizações de status de bloqueio dos dispositivos
#[derive(Deserialize)]
pub struct LockStatusMessage {
    /// Estado de bloqueio (LOCKED/UNLOCKED)
    pub lock: String,
    /// Motivo da mudança de bloqueio
    pub reason: String,
    /// Tempo de atividade do dispositivo em milissegundos
    #[allow(dead_code)]
    pub uptime_ms: u64,
    /// Timestamp do evento
    pub timestamp: u64,
}

/// Estrutura para entradas de log retornadas pela API
#[derive(Serialize)]
pub struct LogEntry {
    /// ID da entrada de log.
    id: i32,
    /// UUID do dispositivo como string.
    device_id: String,
    /// Timestamp da entrada de log.
    timestamp: chrono::DateTime<chrono::Utc>,
    /// Tipo de evento (LOCK/UNLOCK).
    event_type: String,
    /// Motivo do evento.
    reason: String,
    /// ID do usuário que acionou o evento.
    user_id: Option<String>,
    /// Nome do usuário que acionou o evento.
    user_name: Option<String>,
}

/// Estrutura de requisição para atualizar configuração do dispositivo.
#[derive(Deserialize)]
pub struct UpdateConfigRequest {
    /// Lista de itens de configuração a atualizar.
    configs: Vec<ConfigItem>,
}

/// Item de configuração individual.
#[derive(Deserialize, Debug)]
pub struct ConfigItem {
    /// Chave de configuração (ex.: wifi_ssid, lock_timeout).
    key: String,
    /// Valor de configuração.
    value: String,
}

/// Estrutura de requisição para registrar um dispositivo com uma senha.
#[derive(Deserialize)]
pub struct RegisterDeviceRequest {
    /// UUID do dispositivo.
    device_id: String,
    /// Senha para o dispositivo.
    user_key: String,
    /// ID do usuário proprietário do dispositivo.
    user_id: String,
}

/// Atualiza configuração do dispositivo via MQTT.
/// Valida a requisição, envia configuração ao dispositivo e aguarda confirmação.
#[post("/update_config/<uuid>", data = "<request>")]
pub async fn update_config(
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
            let updates_mutex = super::PENDING_CONFIG_UPDATES.get().unwrap();
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

/// Reinicializa um dispositivo remotamente.
#[post("/reboot/<uuid>")]
pub async fn reboot_device(
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

/// Bloqueia um dispositivo, impedindo controle adicional.
#[post("/lockdown/<uuid>")]
pub async fn lockdown_device(
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

/// Faz ping em um dispositivo para verificar conectividade.
#[post("/ping/<uuid>")]
pub async fn ping_device(
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
        let pings_mutex = super::PENDING_PINGS.get().unwrap();
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

/// Recupera lista de dispositivos pertencentes ao usuário autenticado.
#[get("/devices")]
pub async fn get_devices(token: Token, db_pool: &State<PgPool>) -> Result<String, Status> {
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

/// Registra um dispositivo com uma senha.
#[post("/register_device", data = "<request>")]
pub async fn register_device(
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

/// Envia um comando de controle a um dispositivo (LOCK/UNLOCK).
#[post("/control/<uuid>", data = "<request>")]
pub async fn control_device(
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
        let commands_mutex = super::RECENT_COMMANDS.get().unwrap();
        let mut commands = commands_mutex.lock().unwrap();
        commands.insert(uuid.to_string(), (firebase_uid.clone(), now));
    }

    publish_control_message(mqtt_client, uuid, request.command.clone())
        .await
        .map_err(|_| Status::InternalServerError)?;
    Ok(())
}

/// Despareia um dispositivo do usuário.
#[post("/unpair/<uuid>")]
pub async fn unpair_device(
    token: Token,
    uuid: &str,
    db_pool: &State<PgPool>,
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

/// Recupera detalhes de um dispositivo específico.
#[get("/device/<uuid>")]
pub async fn get_device(
    token: Token,
    uuid: &str,
    db_pool: &State<PgPool>,
) -> Result<String, Status> {
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

/// Recupera detalhes de um dispositivo acessível temporariamente.
#[get("/temp_device/<uuid>")]
pub async fn get_temp_device(
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

/// Envia comando de controle a um dispositivo acessível temporariamente.
#[post("/temp_control/<uuid>", data = "<request>")]
pub async fn control_temp_device(
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
        let commands_mutex = super::RECENT_COMMANDS.get().unwrap();
        let mut commands = commands_mutex.lock().unwrap();
        commands.insert(uuid.to_string(), (firebase_uid.clone(), now_ts));
    }

    publish_control_message(mqtt_client, uuid_parsed, request.command.clone())
        .await
        .map_err(|_| Status::InternalServerError)?;
    Ok(())
}

/// Faz ping em um dispositivo acessível temporariamente.
#[post("/temp_ping/<uuid>")]
pub async fn ping_temp_device(
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
        let pings_mutex = super::PENDING_PINGS.get().unwrap();
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

/// Lista dispositivos com acesso temporário.
#[get("/temp_devices_status")]
pub async fn get_temp_devices_status(
    token: Token,
    db_pool: &State<PgPool>,
) -> Result<String, Status> {
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

/// Recupera logs de acesso de um dispositivo.
#[get("/logs/<uuid>")]
pub async fn get_logs(token: Token, uuid: &str, db_pool: &State<PgPool>) -> Result<String, Status> {
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

/// Recupera notificações de dispositivos próprios.
#[get("/notifications?<devices>")]
pub async fn get_notifications(
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

/// Verifica voz contra embedding registrado para acesso ao dispositivo.
#[post("/verify_voice/<device_id>", data = "<audio_data>")]
pub async fn verify_voice(
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
            let commands_mutex = super::RECENT_COMMANDS.get().unwrap();
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

/// Lista dispositivos acessíveis ao usuário (próprios ou convidados).
#[get("/accessible_devices")]
pub async fn get_accessible_devices(
    token: Token,
    db_pool: &State<PgPool>,
) -> Result<String, Status> {
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
