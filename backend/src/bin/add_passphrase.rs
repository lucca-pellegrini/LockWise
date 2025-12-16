/// Ferramenta para adicionar uma senha a dispositivos que não possuem uma definida.
/// Esta ferramenta conecta ao banco de dados, lista dispositivos não pareados e permite definir uma senha para eles.
use anyhow::Result;
use argon2::password_hash::{SaltString, rand_core::OsRng};
use argon2::{Argon2, PasswordHasher};
use sqlx::ConnectOptions;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions, PgSslMode};
use std::env;
use std::io::{self, Write};
use url::Url;
use uuid::Uuid;

/// Função principal do utilitário add_passphrase.
/// Carrega variáveis de ambiente, conecta ao banco de dados, busca dispositivos sem senhas.
/// Solicita ao usuário selecionar um dispositivo e inserir uma senha, então faz hash e armazena.
#[tokio::main]
async fn main() -> Result<()> {
    dotenv::dotenv().ok();

    // Load DB URL
    let db_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set");

    // Setup DB
    let url = Url::parse(&db_url)?;
    let options = PgConnectOptions::from_url(&url)?.ssl_mode(PgSslMode::Require);
    let db_pool = PgPoolOptions::new()
        .max_connections(5)
        .connect_with(options)
        .await?;

    // Fetch devices with NULL hashed_passphrase
    let devices: Vec<(Uuid, String, i64)> = sqlx::query_as(
        "SELECT uuid, last_heard::text, uptime_ms FROM devices WHERE hashed_passphrase IS NULL ORDER BY last_heard DESC"
    )
    .fetch_all(&db_pool)
    .await?;

    if devices.is_empty() {
        println!("No devices without passphrases found.");
        return Ok(());
    }

    println!("Available devices (without passphrases set):");
    for (i, (uuid, last_heard, uptime_ms)) in devices.iter().enumerate() {
        println!(
            "{}. UUID: {}, Last heard: {}, Uptime: {} ms",
            i + 1,
            uuid,
            last_heard,
            uptime_ms
        );
    }

    // Prompt for selection
    print!("Enter the number of the device to set passphrase for: ");
    io::stdout().flush()?;
    let mut input = String::new();
    io::stdin().read_line(&mut input)?;
    let index: usize = input
        .trim()
        .parse()
        .map_err(|_| anyhow::anyhow!("Invalid number"))?;
    if index == 0 || index > devices.len() {
        return Err(anyhow::anyhow!("Invalid selection"));
    }
    let selected_uuid = devices[index - 1].0;

    // Prompt for passphrase
    print!("Enter the passphrase for device {}: ", selected_uuid);
    io::stdout().flush()?;
    let mut passphrase = String::new();
    io::stdin().read_line(&mut passphrase)?;
    let passphrase = passphrase.trim();

    // Hash the passphrase
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let password_hash = argon2
        .hash_password(passphrase.as_bytes(), &salt)
        .expect("Failed to hash password")
        .to_string();

    // Update DB
    sqlx::query("UPDATE devices SET hashed_passphrase = $1 WHERE uuid = $2")
        .bind(password_hash)
        .bind(selected_uuid)
        .execute(&db_pool)
        .await?;

    println!("Passphrase set for device {}.", selected_uuid);

    Ok(())
}
