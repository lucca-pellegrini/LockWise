//! Módulo para comunicação MQTT.
//!
//! Este módulo gerencia a conexão MQTT com dispositivos, incluindo publicação de comandos,
//! recebimento de mensagens de status e processamento de heartbeats.
use anyhow::Result;
use chrono::{TimeZone, Utc};
use rumqttc::{AsyncClient, Event, Incoming, QoS};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use super::device::LockStatusMessage;

/// Estrutura de mensagem para relatórios de heartbeat de dispositivos via MQTT
#[derive(Deserialize)]
struct HeartbeatMessage {
    /// Tipo de mensagem de heartbeat
    heartbeat: String,
    /// Tempo de atividade do dispositivo em milissegundos
    uptime_ms: u64,
    /// Timestamp da mensagem
    #[allow(dead_code)]
    timestamp: u64,
    /// SSID WiFi ao qual o dispositivo está conectado
    wifi_ssid: String,
    /// URL do back-end configurada no dispositivo
    backend_url: String,
    /// URL do broker MQTT configurada no dispositivo
    mqtt_broker_url: String,
    /// Se o heartbeat MQTT está habilitado
    mqtt_heartbeat_enable: bool,
    /// Intervalo de heartbeat em segundos
    mqtt_heartbeat_interval_sec: i32,
    /// Tempo limite de gravação de áudio em segundos
    audio_record_timeout_sec: i32,
    /// Tempo limite de bloqueio em milissegundos
    lock_timeout_ms: i32,
    /// Tempo limite de pareamento em segundos
    pairing_timeout_sec: i32,
    /// ID do usuário associado ao dispositivo
    user_id: String,
    /// Estado atual de bloqueio
    lock_state: Option<String>,
    /// Se a detecção de voz está habilitada
    voice_detection_enable: bool,
    /// Limiar RMS para detecção de atividade de voz
    vad_rms_threshold: i32,
}

/// Estrutura de mensagem para relatórios de eventos de dispositivos via MQTT
#[derive(Deserialize)]
struct EventMessage {
    /// Tipo de evento (ex.: PONG, CONFIG_UPDATED, LOCKING_DOWN)
    event: String,
    /// Tempo de atividade do dispositivo em milissegundos
    #[allow(dead_code)]
    uptime_ms: u64,
    /// Timestamp do evento
    timestamp: u64,
}

/// Estrutura de mensagem para enviar comandos de controle aos dispositivos via MQTT
#[derive(Serialize)]
struct ControlMessage {
    /// O comando a enviar (ex.: LOCK, UNLOCK, PING)
    command: String,
}

/// Manipula eventos MQTT recebidos dos dispositivos.
/// Processa mensagens de heartbeat, eventos (PONG, CONFIG_UPDATED, LOCKING_DOWN)
/// e atualizações de status de bloqueio, atualizando o banco de dados conforme necessário.
/// Também envia atualizações em tempo real via WebSocket para usuários conectados.
pub async fn handle_mqtt_events(db_pool: &PgPool, eventloop: &mut rumqttc::EventLoop) {
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
                                    "INSERT INTO devices (uuid, user_id, last_heard, uptime_ms, wifi_ssid, backend_url, mqtt_broker_url, mqtt_heartbeat_enable, mqtt_heartbeat_interval_sec, audio_record_timeout_sec, lock_timeout_ms, pairing_timeout_sec, lock_state, voice_detection_enable, vad_rms_threshold, hashed_passphrase, locked_down_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, NULL, NULL)
                                          ON CONFLICT (uuid) DO UPDATE SET user_id = $2, last_heard = $3, uptime_ms = $4, wifi_ssid = $5, backend_url = $6, mqtt_broker_url = $7, mqtt_heartbeat_enable = $8, mqtt_heartbeat_interval_sec = $9, audio_record_timeout_sec = $10, lock_timeout_ms = $11, pairing_timeout_sec = $12, lock_state = $13, voice_detection_enable = $14, vad_rms_threshold = $15, locked_down_at = NULL"
                                } else {
                                    "INSERT INTO devices (uuid, user_id, last_heard, uptime_ms, wifi_ssid, backend_url, mqtt_broker_url, mqtt_heartbeat_enable, mqtt_heartbeat_interval_sec, audio_record_timeout_sec, lock_timeout_ms, pairing_timeout_sec, lock_state, voice_detection_enable, vad_rms_threshold, hashed_passphrase) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, NULL)
                                          ON CONFLICT (uuid) DO UPDATE SET user_id = $2, last_heard = $3, uptime_ms = $4, wifi_ssid = $5, backend_url = $6, mqtt_broker_url = $7, mqtt_heartbeat_enable = $8, mqtt_heartbeat_interval_sec = $9, audio_record_timeout_sec = $10, lock_timeout_ms = $11, pairing_timeout_sec = $12, lock_state = $13, voice_detection_enable = $14, vad_rms_threshold = $15"
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
                                    .bind(heartbeat_msg.vad_rms_threshold)
                                    .execute(db_pool)
                                    .await;

                                // Broadcast device online update to owner and invited users
                                if let Some(user_broadcasts) = super::USER_BROADCASTS.get() {
                                    let update = serde_json::json!({
                                        "type": "device_online",
                                        "device_id": uuid_str,
                                        "last_heard": now.timestamp_millis(),
                                        "lock_state": lock_state,
                                        "locked_down_at": null
                                    })
                                    .to_string();
                                    eprintln!(
                                        "DEBUG: Broadcasting device_online for device {} with last_heard {} to recipients",
                                        uuid_str,
                                        now.timestamp_millis()
                                    );

                                    // Get owner
                                    let owner_row: Option<(String,)> = sqlx::query_as(
                                        "SELECT user_id FROM devices WHERE uuid = $1",
                                    )
                                    .bind(uuid)
                                    .fetch_optional(db_pool)
                                    .await
                                    .unwrap_or(None);

                                    let mut recipients = Vec::new();
                                    if let Some((owner_id,)) = owner_row {
                                        recipients.push(owner_id);
                                    }

                                    // Get invited users with status = 1
                                    let invited_rows: Vec<(String,)> = sqlx::query_as(
                                         "SELECT receiver_id FROM invites WHERE device_id = $1 AND status = 1"
                                     )
                                     .bind(uuid)
                                     .fetch_all(db_pool)
                                     .await
                                     .unwrap_or_default();

                                    for (receiver_id,) in invited_rows {
                                        recipients.push(receiver_id);
                                    }

                                    // Send to each recipient
                                    let broadcasts = user_broadcasts.lock().unwrap();
                                    for recipient in recipients {
                                        if let Some(tx) = broadcasts.get(&recipient) {
                                            let _ = tx.send(update.clone());
                                        }
                                    }
                                }
                            }
                        } else if let Ok(event_msg) =
                            serde_cbor::from_slice::<EventMessage>(&publish.payload)
                        {
                            if event_msg.event == "PONG" {
                                // Handle PONG
                                let pings_mutex = super::PENDING_PINGS.get().unwrap();
                                let mut pings = pings_mutex.lock().unwrap();
                                if let Some((_, tx)) = pings.remove(&uuid_str.to_string()) {
                                    tx.send(()).ok();
                                }
                            } else if event_msg.event == "CONFIG_UPDATED" {
                                // Handle CONFIG_UPDATED
                                let updates_mutex = super::PENDING_CONFIG_UPDATES.get().unwrap();
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
                                if result.is_ok() {
                                    // Broadcast device update to owner and invited users
                                    if let Some(user_broadcasts) = super::USER_BROADCASTS.get() {
                                        let update = serde_json::json!({
                                            "type": "device_update",
                                            "device_id": uuid_str,
                                            "lock_state": "LOCKED",
                                            "locked_down_at": timestamp.timestamp_millis()
                                        })
                                        .to_string();

                                        // Get owner
                                        let owner_row: Option<(String,)> = sqlx::query_as(
                                            "SELECT user_id FROM devices WHERE uuid = $1",
                                        )
                                        .bind(uuid)
                                        .fetch_optional(db_pool)
                                        .await
                                        .unwrap_or(None);

                                        let mut recipients = Vec::new();
                                        if let Some((owner_id,)) = owner_row {
                                            recipients.push(owner_id);
                                        }

                                        // Get invited users with status = 1
                                        let invited_rows: Vec<(String,)> = sqlx::query_as(
                                              "SELECT receiver_id FROM invites WHERE device_id = $1 AND status = 1"
                                          )
                                          .bind(uuid)
                                          .fetch_all(db_pool)
                                          .await
                                          .unwrap_or_default();

                                        for (receiver_id,) in invited_rows {
                                            recipients.push(receiver_id);
                                        }

                                        // Send to each recipient
                                        let broadcasts = user_broadcasts.lock().unwrap();
                                        for recipient in recipients {
                                            if let Some(tx) = broadcasts.get(&recipient) {
                                                let _ = tx.send(update.clone());
                                            }
                                        }
                                    }
                                }
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
                                let commands_mutex = super::RECENT_COMMANDS.get().unwrap();
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

                            // Broadcast log update to owner only
                            if let Some(user_broadcasts) = super::USER_BROADCASTS.get() {
                                // Get user name if user_id is present
                                let user_name = if let Some(ref uid) = user_id {
                                    let row: Option<(String,)> = sqlx::query_as(
                                        "SELECT name FROM users WHERE firebase_uid = $1",
                                    )
                                    .bind(uid)
                                    .fetch_optional(db_pool)
                                    .await
                                    .unwrap_or(None);
                                    row.map(|(name,)| name)
                                } else {
                                    None
                                };

                                let log_update = serde_json::json!({
                                    "type": "log_update",
                                    "device_id": uuid_str,
                                    "timestamp": timestamp.timestamp_millis(),
                                    "event_type": event_type,
                                    "reason": reason,
                                    "user_id": user_id,
                                    "user_name": user_name
                                })
                                .to_string();

                                // Get owner
                                let owner_row: Option<(String,)> =
                                    sqlx::query_as("SELECT user_id FROM devices WHERE uuid = $1")
                                        .bind(uuid)
                                        .fetch_optional(db_pool)
                                        .await
                                        .unwrap_or(None);

                                if let Some((owner_id,)) = owner_row {
                                    let broadcasts = user_broadcasts.lock().unwrap();
                                    if let Some(tx) = broadcasts.get(&owner_id) {
                                        let _ = tx.send(log_update);
                                    }
                                }
                            }

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

                            // Get locked_down_at
                            let locked_down_at: Option<i64> = {
                                let row: Option<(Option<chrono::DateTime<Utc>>,)> = sqlx::query_as(
                                    "SELECT locked_down_at FROM devices WHERE uuid = $1",
                                )
                                .bind(uuid)
                                .fetch_optional(db_pool)
                                .await
                                .unwrap_or(None);
                                row.and_then(|(dt,)| dt.map(|d| d.timestamp_millis()))
                            };

                            // Broadcast update to owner and invited users
                            if let Some(user_broadcasts) = super::USER_BROADCASTS.get() {
                                let update = serde_json::json!({
                                    "type": "device_update",
                                    "device_id": uuid_str,
                                    "lock_state": lock_state,
                                    "timestamp": timestamp.timestamp_millis(),
                                    "locked_down_at": locked_down_at
                                })
                                .to_string();

                                // Get owner
                                let owner_row: Option<(String,)> =
                                    sqlx::query_as("SELECT user_id FROM devices WHERE uuid = $1")
                                        .bind(uuid)
                                        .fetch_optional(db_pool)
                                        .await
                                        .unwrap_or(None);

                                let mut recipients = Vec::new();
                                if let Some((owner_id,)) = owner_row {
                                    recipients.push(owner_id);
                                }

                                // Get invited users with status = 1
                                let invited_rows: Vec<(String,)> = sqlx::query_as(
                                     "SELECT receiver_id FROM invites WHERE device_id = $1 AND status = 1"
                                 )
                                 .bind(uuid)
                                 .fetch_all(db_pool)
                                 .await
                                 .unwrap_or_default();

                                for (receiver_id,) in invited_rows {
                                    recipients.push(receiver_id);
                                }

                                // Send to each recipient
                                let broadcasts = user_broadcasts.lock().unwrap();
                                for recipient in recipients {
                                    if let Some(tx) = broadcasts.get(&recipient) {
                                        let _ = tx.send(update.clone());
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Ok(_) => {}
            Err(_) => {}
        }
    }
}

/// Publica uma mensagem de controle para um dispositivo via MQTT.
/// Envia um comando para o UUID do dispositivo especificado.
pub async fn publish_control_message(
    client: &AsyncClient,
    uuid: Uuid,
    command: String,
) -> Result<()> {
    let topic = format!("lockwise/{}/control", uuid);
    let msg = ControlMessage { command };
    let payload = serde_cbor::to_vec(&msg)?;
    client
        .publish(topic, QoS::AtMostOnce, false, payload)
        .await?;
    Ok(())
}
