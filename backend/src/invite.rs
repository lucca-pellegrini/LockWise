//! Módulo para gerenciamento de convites.
//!
//! Este módulo implementa a funcionalidade de convites temporários para compartilhamento
//! de acesso a dispositivos LockWise entre usuários.
use anyhow::Result;
use chrono::Utc;
use rocket::http::Status;
use rocket::{State, get, post};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use super::Token;

/// Informações sobre convites enviados.
#[derive(sqlx::FromRow, Serialize)]
pub struct SentInviteInfo {
    /// ID do convite.
    id: i32,
    /// UUID do dispositivo.
    device_id: uuid::Uuid,
    /// ID do usuário remetente.
    sender_id: String,
    /// ID do usuário destinatário.
    receiver_id: String,
    /// Nome do destinatário.
    receiver_name: String,
    /// Email do destinatário.
    receiver_email: String,
    /// Status do convite (0: pendente, 1: aceito).
    status: i32,
    /// Timestamp de expiração.
    expiry_timestamp: i64,
    /// Timestamp de criação.
    created_at: chrono::DateTime<chrono::Utc>,
}

/// Informações sobre convites recebidos.
#[derive(sqlx::FromRow, Serialize)]
pub struct ReceivedInviteInfo {
    /// ID do convite.
    id: i32,
    /// UUID do dispositivo.
    device_id: uuid::Uuid,
    /// ID do usuário remetente.
    sender_id: String,
    /// ID do usuário destinatário.
    receiver_id: String,
    /// Nome do remetente.
    sender_name: String,
    /// Email do remetente.
    sender_email: String,
    /// Status do convite.
    status: i32,
    /// Timestamp de expiração.
    expiry_timestamp: i64,
    /// Timestamp de criação.
    created_at: chrono::DateTime<chrono::Utc>,
}

/// Estrutura de requisição para criar um convite.
#[derive(Deserialize)]
pub struct CreateInviteRequest {
    /// Email do destinatário do convite.
    receiver_email: String,
    /// UUID do dispositivo a convidar.
    device_id: String,
    /// String de duração de expiração (ex.: "2_dias", "1_semana").
    expiry_duration: String,
}

/// Estrutura de requisição para atualizar um convite.
#[derive(Deserialize)]
pub struct UpdateInviteRequest {
    /// Nova string de duração de expiração.
    expiry_duration: String,
}

/// Cria convite para acesso temporário ao dispositivo.
#[post("/create_invite", data = "<request>")]
pub async fn create_invite(
    token: Token,
    request: rocket::serde::json::Json<CreateInviteRequest>,
    db_pool: &State<PgPool>,
) -> Result<String, Status> {
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
    .bind(device_uuid) // UUID for invites table
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

/// Recupera convites enviados e recebidos do usuário.
#[get("/invites")]
pub async fn get_invites(token: Token, db_pool: &State<PgPool>) -> Result<String, Status> {
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

/// Aceita convite para acesso ao dispositivo.
#[post("/accept_invite/<invite_id>")]
pub async fn accept_invite(
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
        Err(Status::NotFound)
    } else {
        Ok(())
    }
}

/// Rejeita convite.
#[post("/reject_invite/<invite_id>")]
pub async fn reject_invite(
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

    Ok(())
}

/// Cancela convite enviado.
#[post("/cancel_invite/<invite_id>")]
pub async fn cancel_invite(
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

/// Atualiza um convite (ex.: estender expiração).
#[post("/update_invite/<invite_id>", data = "<request>")]
pub async fn update_invite(
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

/// Calcula timestamp de expiração a partir de string de duração (ex.: "1h", "30m").
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
