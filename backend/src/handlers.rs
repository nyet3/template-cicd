use crate::middleware::AuthMiddleware;
use crate::models::{ApiResponse, AuthInfo, CreateUserRequest, User};
use crate::services::Database;
use actix_web::{web, HttpRequest, HttpResponse, Responder};
use std::sync::Arc;

pub async fn health() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "healthy",
        "timestamp": chrono::Utc::now().to_rfc3339(),
    }))
}

pub async fn auth_info(req: HttpRequest, auth: web::Data<Arc<AuthMiddleware>>) -> impl Responder {
    match auth.extract_from_request(&req).await {
        Ok(auth_info) => HttpResponse::Ok().json(ApiResponse::success(auth_info)),
        Err(e) => HttpResponse::Unauthorized().json(ApiResponse::<AuthInfo>::error(e.to_string())),
    }
}

pub async fn list_users(
    db: web::Data<Database>,
    req: HttpRequest,
    auth: web::Data<Arc<AuthMiddleware>>,
) -> impl Responder {
    if let Err(e) = auth.extract_from_request(&req).await {
        return HttpResponse::Unauthorized().json(ApiResponse::<Vec<User>>::error(e.to_string()));
    }

    match db.get_users().await {
        Ok(users) => HttpResponse::Ok().json(ApiResponse::success(users)),
        Err(e) => {
            HttpResponse::InternalServerError().json(ApiResponse::<Vec<User>>::error(e.to_string()))
        }
    }
}

pub async fn get_user(
    db: web::Data<Database>,
    user_id: web::Path<String>,
    req: HttpRequest,
    auth: web::Data<Arc<AuthMiddleware>>,
) -> impl Responder {
    if let Err(e) = auth.extract_from_request(&req).await {
        return HttpResponse::Unauthorized().json(ApiResponse::<User>::error(e.to_string()));
    }

    match db.get_user_by_id(&user_id).await {
        Ok(Some(user)) => HttpResponse::Ok().json(ApiResponse::success(user)),
        Ok(None) => {
            HttpResponse::NotFound().json(ApiResponse::<User>::error("User not found".to_string()))
        }
        Err(e) => {
            HttpResponse::InternalServerError().json(ApiResponse::<User>::error(e.to_string()))
        }
    }
}

pub async fn create_user(
    db: web::Data<Database>,
    user_data: web::Json<CreateUserRequest>,
    req: HttpRequest,
    auth: web::Data<Arc<AuthMiddleware>>,
) -> impl Responder {
    if let Err(e) = auth.extract_from_request(&req).await {
        return HttpResponse::Unauthorized().json(ApiResponse::<User>::error(e.to_string()));
    }

    let user = User::new(user_data.email.clone(), user_data.name.clone());

    match db.create_user(&user).await {
        Ok(user) => HttpResponse::Created().json(ApiResponse::success(user)),
        Err(e) => {
            HttpResponse::InternalServerError().json(ApiResponse::<User>::error(e.to_string()))
        }
    }
}

pub async fn delete_user(
    db: web::Data<Database>,
    user_id: web::Path<String>,
    req: HttpRequest,
    auth: web::Data<Arc<AuthMiddleware>>,
) -> impl Responder {
    if let Err(e) = auth.extract_from_request(&req).await {
        return HttpResponse::Unauthorized().json(ApiResponse::<bool>::error(e.to_string()));
    }

    match db.delete_user(&user_id).await {
        Ok(true) => HttpResponse::Ok().json(ApiResponse::success(true)),
        Ok(false) => {
            HttpResponse::NotFound().json(ApiResponse::<bool>::error("User not found".to_string()))
        }
        Err(e) => {
            HttpResponse::InternalServerError().json(ApiResponse::<bool>::error(e.to_string()))
        }
    }
}
