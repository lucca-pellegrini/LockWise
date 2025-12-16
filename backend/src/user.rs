//! Módulo para gerenciamento de usuários.
//!
//! Este módulo contém funcionalidades para autenticação, registro de usuários,
//! gerenciamento de contas e integração com Firebase Authentication.
use anyhow::Result;
use argon2::password_hash::PasswordHash;
use argon2::{Argon2, PasswordHasher, PasswordVerifier};
use base64::Engine;
use reqwest::Client;
use rocket::http::Status;
use rocket::{State, get, post};
use serde::Deserialize;
use sqlx::PgPool;
use tokio::io::AsyncReadExt;
use uuid::Uuid;

use super::{SpeechbrainUrl, Token};

/// Estrutura de requisição para registro de usuário.
#[derive(Deserialize)]
pub struct RegisterRequest {
    /// UID do Firebase para autenticação.
    firebase_uid: String,
    /// Senha do usuário.
    password: String,
    /// Email do usuário.
    email: String,
    /// Número de telefone do usuário.
    phone_number: String,
    /// Nome do usuário.
    name: String,
}

/// Estrutura de requisição para login de usuário.
#[derive(Deserialize)]
pub struct LoginRequest {
    /// UID do Firebase.
    firebase_uid: String,
    password: String,
}

/// Estrutura de requisição para atualizar número de telefone do usuário.
#[derive(Deserialize)]
pub struct UpdatePhoneRequest {
    /// Novo número de telefone.
    phone_number: String,
}
/// Estrutura de requisição para atualizar senha do usuário.
#[derive(Deserialize)]
pub struct UpdatePasswordRequest {
    /// Nova senha.
    password: String,
}

/// Estrutura de requisição para verificar senha do usuário.
#[derive(Deserialize)]
pub struct VerifyPasswordRequest {
    /// Senha a verificar.
    password: String,
}

/// Registra um novo usuário com senha hashada.
#[post("/register", data = "<request>")]
pub async fn register_user(
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

/// Autentica usuário e retorna token JWT.
#[post("/login", data = "<request>")]
pub async fn login_user(
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

/// Faz logout do usuário invalidando o token.
#[post("/logout")]
pub async fn logout_user(token: Token, db_pool: &State<PgPool>) -> Result<(), Status> {
    sqlx::query("UPDATE users SET current_token = NULL WHERE firebase_uid = $1")
        .bind(token.0)
        .execute(&**db_pool)
        .await
        .map_err(|_| Status::InternalServerError)?;
    Ok(())
}

/// Atualiza número de telefone do usuário.
#[post("/update_phone", data = "<request>")]
pub async fn update_phone(
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

/// Atualiza senha do usuário.
#[post("/update_password", data = "<request>")]
pub async fn update_password(
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

/// Exclui conta do usuário e dados associados.
#[post("/delete_account")]
pub async fn delete_account(token: Token, db_pool: &State<PgPool>) -> Result<(), Status> {
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

/// Verifica senha atual do usuário.
#[post("/verify_password", data = "<request>")]
pub async fn verify_password(
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

/// Registra embedding de voz do usuário a partir de dados de áudio.
#[post("/register_voice", data = "<audio_data>")]
pub async fn register_voice(
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

/// Exclui embedding de voz do usuário.
#[post("/delete_voice")]
pub async fn delete_voice(token: Token, db_pool: &State<PgPool>) -> Result<(), Status> {
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

/// Verifica se o usuário tem voz registrada.
#[get("/voice_status")]
pub async fn voice_status(token: Token, db_pool: &State<PgPool>) -> Result<String, Status> {
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
