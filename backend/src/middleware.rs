use crate::config::{Config, Environment};
use crate::models::AuthInfo;
use actix_web::error::ErrorUnauthorized;
use actix_web::http::header::{HeaderMap, HeaderValue};
use actix_web::Error as ActixError;
use jsonwebtoken::{decode, decode_header, jwk::JwkSet, Algorithm, DecodingKey, Validation};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Debug, Serialize, Deserialize)]
#[allow(dead_code)]
pub struct Claims {
    pub sub: String,
    pub email: Option<String>,
    pub name: Option<String>,
    pub organization: Option<String>,
    pub exp: usize,
}

#[allow(dead_code)]
pub struct AuthMiddleware {
    config: Arc<Config>,
    jwks: Option<JwkSet>,
    http: Client,
}

impl AuthMiddleware {
    pub async fn new(config: Arc<Config>) -> Result<Self, anyhow::Error> {
        let insecure_ok = matches!(
            config.environment,
            Environment::Test | Environment::DisasterRecovery | Environment::Development
        );
        let http = Client::builder()
            .danger_accept_invalid_certs(insecure_ok)
            .build()?;

        let jwks = if config.is_auth_enabled() {
            let jwks_url_base = config
                .oidc_jwks_url
                .as_ref()
                .or(config.oidc_issuer_url.as_ref());
            if let Some(base_url) = jwks_url_base {
                let jwks_url = format!("{}/protocol/openid-connect/certs", base_url);
                log::info!("Fetching JWKS from: {}", jwks_url);
                match http.get(&jwks_url).send().await {
                    Ok(response) => match response.text().await {
                        Ok(body) => {
                            log::info!("JWKS response: {}", body);
                            match serde_json::from_str::<JwkSet>(&body) {
                                Ok(jwks) => Some(jwks),
                                Err(e) => {
                                    log::warn!(
                                        "Failed to parse JWKS JSON: {}. Response body: {}",
                                        e,
                                        body
                                    );
                                    None
                                }
                            }
                        }
                        Err(e) => {
                            log::warn!("Failed to read JWKS response body: {}", e);
                            None
                        }
                    },
                    Err(e) => {
                        log::warn!("Failed to fetch JWKS: {}. Authentication will fail.", e);
                        None
                    }
                }
            } else {
                log::warn!("OIDC issuer URL not configured. Authentication will fail.");
                None
            }
        } else {
            None
        };

        Ok(Self { config, jwks, http })
    }

    #[allow(dead_code)]
    pub async fn validate_token(&self, token: &str) -> Result<AuthInfo, ActixError> {
        // Development environment: always return dummy user
        if !self.config.is_auth_enabled() {
            return Ok(AuthInfo::default());
        }

        // Production/Test environment: validate JWT
        let jwks = self
            .jwks
            .as_ref()
            .ok_or_else(|| ErrorUnauthorized("JWKS not configured"))?;

        let header = decode_header(token)
            .map_err(|e| ErrorUnauthorized(format!("Invalid token header: {}", e)))?;

        let kid = header
            .kid
            .ok_or_else(|| ErrorUnauthorized("Token missing kid"))?;

        let jwk = jwks
            .find(&kid)
            .ok_or_else(|| ErrorUnauthorized("JWK not found"))?;

        let decoding_key = DecodingKey::from_jwk(jwk)
            .map_err(|e| ErrorUnauthorized(format!("Invalid JWK: {}", e)))?;

        let mut validation = Validation::new(Algorithm::RS256);
        if let Some(issuer) = &self.config.oidc_issuer_url {
            validation.set_issuer(&[issuer]);
        }
        if let Some(client_id) = &self.config.oidc_client_id {
            validation.set_audience(&[client_id]);
        }

        let token_data = decode::<Claims>(token, &decoding_key, &validation)
            .map_err(|e| ErrorUnauthorized(format!("Token validation failed: {}", e)))?;

        Ok(AuthInfo {
            user_id: token_data.claims.sub,
            email: token_data.claims.email.unwrap_or_default(),
            name: token_data.claims.name.unwrap_or_default(),
            organization: token_data
                .claims
                .organization
                .unwrap_or_else(|| "未設定".to_string()),
        })
    }

    pub async fn extract_from_request(
        &self,
        req: &actix_web::HttpRequest,
    ) -> Result<AuthInfo, ActixError> {
        self.extract_from_headers(req.headers()).await
    }

    async fn extract_from_headers(&self, headers: &HeaderMap) -> Result<AuthInfo, ActixError> {
        // Development mode: always return dummy user
        if !self.config.is_auth_enabled() {
            return Ok(AuthInfo::default());
        }

        let auth_header = headers
            .get("Authorization")
            .and_then(|h: &HeaderValue| h.to_str().ok())
            .ok_or_else(|| ErrorUnauthorized("Missing Authorization header"))?;

        if !auth_header.starts_with("Bearer ") {
            return Err(ErrorUnauthorized("Invalid Authorization header format"));
        }

        let token = &auth_header[7..];
        self.validate_token(token).await
    }
}
