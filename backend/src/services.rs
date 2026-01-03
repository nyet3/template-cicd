use sqlx::{Pool, Sqlite, Postgres, migrate::MigrateDatabase};
use anyhow::Result;
use crate::config::Config;
use crate::models::User;

#[derive(Clone)]
pub enum Database {
    Sqlite(Pool<Sqlite>),
    Postgres(Pool<Postgres>),
}

impl Database {
    pub async fn new(config: &Config) -> Result<Self> {
        match config.db_type() {
            "sqlite" => {
                // Create database if it doesn't exist
                if !Sqlite::database_exists(&config.database_url).await.unwrap_or(false) {
                    log::info!("Creating SQLite database: {}", config.database_url);
                    Sqlite::create_database(&config.database_url).await?;
                }

                let pool = Pool::<Sqlite>::connect(&config.database_url).await?;
                
                // Run migrations
                sqlx::query(
                    r#"
                    CREATE TABLE IF NOT EXISTS users (
                        id TEXT PRIMARY KEY,
                        email TEXT NOT NULL UNIQUE,
                        name TEXT NOT NULL,
                        created_at TEXT NOT NULL
                    )
                    "#
                )
                .execute(&pool)
                .await?;

                Ok(Database::Sqlite(pool))
            }
            "postgres" => {
                let pool = Pool::<Postgres>::connect(&config.database_url).await?;
                
                // Run migrations
                sqlx::query(
                    r#"
                    CREATE TABLE IF NOT EXISTS users (
                        id TEXT PRIMARY KEY,
                        email TEXT NOT NULL UNIQUE,
                        name TEXT NOT NULL,
                        created_at TEXT NOT NULL
                    )
                    "#
                )
                .execute(&pool)
                .await?;

                Ok(Database::Postgres(pool))
            }
            _ => Err(anyhow::anyhow!("Unsupported database type")),
        }
    }

    pub async fn get_users(&self) -> Result<Vec<User>> {
        match self {
            Database::Sqlite(pool) => {
                let users = sqlx::query_as::<_, User>("SELECT * FROM users ORDER BY created_at DESC")
                    .fetch_all(pool)
                    .await?;
                Ok(users)
            }
            Database::Postgres(pool) => {
                let users = sqlx::query_as::<_, User>("SELECT * FROM users ORDER BY created_at DESC")
                    .fetch_all(pool)
                    .await?;
                Ok(users)
            }
        }
    }

    pub async fn get_user_by_id(&self, id: &str) -> Result<Option<User>> {
        match self {
            Database::Sqlite(pool) => {
                let user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = ?")
                    .bind(id)
                    .fetch_optional(pool)
                    .await?;
                Ok(user)
            }
            Database::Postgres(pool) => {
                let user = sqlx::query_as::<_, User>("SELECT * FROM users WHERE id = $1")
                    .bind(id)
                    .fetch_optional(pool)
                    .await?;
                Ok(user)
            }
        }
    }

    pub async fn create_user(&self, user: &User) -> Result<User> {
        match self {
            Database::Sqlite(pool) => {
                sqlx::query("INSERT INTO users (id, email, name, created_at) VALUES (?, ?, ?, ?)")
                    .bind(&user.id)
                    .bind(&user.email)
                    .bind(&user.name)
                    .bind(&user.created_at)
                    .execute(pool)
                    .await?;
                Ok(user.clone())
            }
            Database::Postgres(pool) => {
                sqlx::query("INSERT INTO users (id, email, name, created_at) VALUES ($1, $2, $3, $4)")
                    .bind(&user.id)
                    .bind(&user.email)
                    .bind(&user.name)
                    .bind(&user.created_at)
                    .execute(pool)
                    .await?;
                Ok(user.clone())
            }
        }
    }

    pub async fn delete_user(&self, id: &str) -> Result<bool> {
        match self {
            Database::Sqlite(pool) => {
                let result = sqlx::query("DELETE FROM users WHERE id = ?")
                    .bind(id)
                    .execute(pool)
                    .await?;
                Ok(result.rows_affected() > 0)
            }
            Database::Postgres(pool) => {
                let result = sqlx::query("DELETE FROM users WHERE id = $1")
                    .bind(id)
                    .execute(pool)
                    .await?;
                Ok(result.rows_affected() > 0)
            }
        }
    }
}
