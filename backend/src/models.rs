use chrono::Utc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct User {
    pub id: String,
    pub email: String,
    pub name: String,
    pub created_at: String,
}

impl User {
    pub fn new(email: String, name: String) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            email,
            name,
            created_at: Utc::now().to_rfc3339(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateUserRequest {
    pub email: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<String>,
}

impl<T> ApiResponse<T> {
    pub fn success(data: T) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
        }
    }

    pub fn error(error: String) -> Self {
        Self {
            success: false,
            data: None,
            error: Some(error),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthInfo {
    pub user_id: String,
    pub email: String,
    pub name: String,
    pub organization: String,
}

impl Default for AuthInfo {
    fn default() -> Self {
        Self {
            user_id: "dev-user-001".to_string(),
            email: "dev@example.com".to_string(),
            name: "Development User".to_string(),
            organization: "Development Org".to_string(),
        }
    }
}
