mod config;
mod handlers;
mod middleware;
mod models;
mod services;

use actix_cors::Cors;
use actix_web::{middleware::Logger, web, App, HttpServer};
use std::sync::Arc;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init_from_env(env_logger::Env::new().default_filter_or("info"));

    let config = config::Config::from_env().expect("Failed to load configuration");

    log::info!("Starting server in {:?} mode", config.environment);
    log::info!("Database: {} ({})", config.database_url, config.db_type());
    log::info!("Authentication enabled: {}", config.is_auth_enabled());

    let db = services::Database::new(&config)
        .await
        .expect("Failed to initialize database");

    let config_arc = Arc::new(config.clone());
    let auth_middleware = Arc::new(
        middleware::AuthMiddleware::new(config_arc.clone())
            .await
            .expect("Failed to initialize auth middleware"),
    );

    let bind_address = format!("{}:{}", config.server_host, config.server_port);
    log::info!("Server starting on http://{}", bind_address);

    HttpServer::new(move || {
        let cors = Cors::default()
            .allow_any_origin()
            .allow_any_method()
            .allow_any_header()
            .max_age(3600);

        App::new()
            .wrap(Logger::default())
            .wrap(cors)
            .app_data(web::Data::new(db.clone()))
            .app_data(web::Data::new(auth_middleware.clone()))
            .route("/health", web::get().to(handlers::health))
            .route("/api/auth/info", web::get().to(handlers::auth_info))
            .route("/api/users", web::get().to(handlers::list_users))
            .route("/api/users", web::post().to(handlers::create_user))
            .route("/api/users/{id}", web::get().to(handlers::get_user))
            .route("/api/users/{id}", web::delete().to(handlers::delete_user))
    })
    .bind(&bind_address)?
    .run()
    .await
}
