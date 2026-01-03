use serde::Deserialize;
use std::env;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub database_url: String,
    pub environment: Environment,
    pub server_host: String,
    pub server_port: u16,
    pub oidc_issuer_url: Option<String>,
    pub oidc_jwks_url: Option<String>,
    pub oidc_client_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Environment {
    Development,
    Test,
    Production,
    DisasterRecovery,
}

impl Config {
    pub fn from_env() -> Result<Self, anyhow::Error> {
        dotenv::dotenv().ok();

        let environment = env::var("ENVIRONMENT")
            .unwrap_or_else(|_| "development".to_string())
            .to_lowercase();

        let environment = match environment.as_str() {
            "development" => Environment::Development,
            "test" => Environment::Test,
            "production" => Environment::Production,
            "disaster-recovery" | "dr" => Environment::DisasterRecovery,
            _ => Environment::Development,
        };

        let database_url = env::var("DATABASE_URL").unwrap_or_else(|_| match environment {
            Environment::Development => "sqlite://./dev.db".to_string(),
            _ => panic!("DATABASE_URL must be set for non-development environments"),
        });

        let server_host = env::var("SERVER_HOST").unwrap_or_else(|_| "0.0.0.0".to_string());

        let server_port = env::var("SERVER_PORT")
            .unwrap_or_else(|_| "8080".to_string())
            .parse()
            .unwrap_or(8080);

        let oidc_issuer_url = env::var("OIDC_ISSUER_URL").ok();
        let oidc_jwks_url = env::var("OIDC_JWKS_URL").ok();
        let oidc_client_id = env::var("OIDC_CLIENT_ID").ok();

        Ok(Config {
            database_url,
            environment,
            server_host,
            server_port,
            oidc_issuer_url,
            oidc_jwks_url,
            oidc_client_id,
        })
    }

    pub fn is_auth_enabled(&self) -> bool {
        self.environment != Environment::Development
    }

    #[allow(dead_code)]
    pub fn oidc_client_id(&self) -> Option<&String> {
        self.oidc_client_id.as_ref()
    }

    pub fn db_type(&self) -> &str {
        if self.database_url.starts_with("sqlite") {
            "sqlite"
        } else {
            "postgres"
        }
    }
}
