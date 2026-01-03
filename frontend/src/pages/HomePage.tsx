import { useAuth } from "react-oidc-context";
import { useEffect, useState } from "react";
import { config } from "../config";

interface UserProfile {
  name?: string;
  preferred_username?: string;
  organization?: string;
  [key: string]: unknown;
}

export const HomePage = () => {
  const auth = useAuth();
  const [showProfileOverlay, setShowProfileOverlay] = useState(false);

  // Save access token to localStorage when authenticated
  useEffect(() => {
    if (auth?.user?.access_token) {
      localStorage.setItem("oidc_access_token", auth.user.access_token);
    }
  }, [auth?.user?.access_token]);

  const handleLogin = () => {
    if (auth) {
      auth.signinRedirect();
    }
  };

  const handleLogout = () => {
    if (auth && config.authEnabled) {
      localStorage.removeItem("oidc_access_token");
      auth.signoutRedirect({
        post_logout_redirect_uri: window.location.origin,
      });
    }
  };

  // In development mode without auth, show as authenticated with dummy data
  const isAuthenticated = config.authEnabled
    ? auth?.isAuthenticated ?? false
    : true;

  // Dummy user for development mode
  const dummyUser = {
    sub: "dev-user-123",
    email: "dev@example.com",
    name: "開発ユーザー",
    organization: "開発組織",
  };

  const userProfile = config.authEnabled ? auth?.user?.profile : dummyUser;

  return (
    <div style={{ maxWidth: "1200px", margin: "0 auto", padding: "2rem" }}>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          marginBottom: "2rem",
        }}
      >
        <div>
          <h1>Template CICD - Home</h1>
          <p>React + Rust + Kubernetes CI/CD Template</p>
        </div>

        <div
          style={{
            display: "flex",
            gap: "1rem",
            alignItems: "center",
            position: "relative",
          }}
        >
          {isAuthenticated ? (
            <div
              onMouseEnter={() => setShowProfileOverlay(true)}
              onMouseLeave={() => setShowProfileOverlay(false)}
              style={{
                padding: "0.5rem 1rem",
                background: config.authEnabled ? "#e8f5e9" : "#fff3e0",
                borderRadius: "4px",
                fontSize: "0.9rem",
                cursor: "pointer",
                transition: "background 0.2s",
                position: "relative",
              }}
            >
              <span
                style={{
                  color: config.authEnabled ? "#2e7d32" : "#e65100",
                  fontWeight: "bold",
                }}
              >
                ✓ {config.authEnabled ? "ログイン済み" : "開発モード"}
              </span>
              {userProfile?.email && (
                <div style={{ fontSize: "0.85rem", color: "#555" }}>
                  {userProfile.email}
                </div>
              )}

              {showProfileOverlay && (
                <div
                  style={{
                    position: "absolute",
                    top: "100%",
                    right: 0,
                    marginTop: "0.5rem",
                    minWidth: "320px",
                    background: "#ffffff",
                    borderRadius: "8px",
                    boxShadow: "0 4px 12px rgba(0,0,0,0.15)",
                    border: "1px solid #e0e0e0",
                    zIndex: 1000,
                    padding: "1.5rem",
                  }}
                >
                  <h3
                    style={{
                      marginTop: 0,
                      marginBottom: "1rem",
                      color: "#2e7d32",
                      fontSize: "1.1rem",
                    }}
                  >
                    👤 ユーザープロファイル
                  </h3>
                  <div
                    style={{
                      display: "flex",
                      flexDirection: "column",
                      gap: "0.75rem",
                    }}
                  >
                    <div>
                      <strong style={{ color: "#666", fontSize: "0.85rem" }}>
                        User ID:
                      </strong>
                      <div
                        style={{
                          color: "#333",
                          marginTop: "0.25rem",
                          wordBreak: "break-all",
                        }}
                      >
                        {userProfile?.sub || "N/A"}
                      </div>
                    </div>
                    <div>
                      <strong style={{ color: "#666", fontSize: "0.85rem" }}>
                        Email:
                      </strong>
                      <div style={{ color: "#333", marginTop: "0.25rem" }}>
                        {userProfile?.email || "N/A"}
                      </div>
                    </div>
                    <div>
                      <strong style={{ color: "#666", fontSize: "0.85rem" }}>
                        Name:
                      </strong>
                      <div style={{ color: "#333", marginTop: "0.25rem" }}>
                        {userProfile?.name ||
                          (userProfile as UserProfile)?.preferred_username ||
                          "N/A"}
                      </div>
                    </div>
                    <div>
                      <strong style={{ color: "#666", fontSize: "0.85rem" }}>
                        所属:
                      </strong>
                      <div style={{ color: "#333", marginTop: "0.25rem" }}>
                        {(userProfile as UserProfile)?.organization || "未設定"}
                      </div>
                    </div>
                    <div
                      style={{
                        marginTop: "0.5rem",
                        paddingTop: "0.75rem",
                        borderTop: "1px solid #e0e0e0",
                      }}
                    >
                      <strong style={{ color: "#666", fontSize: "0.85rem" }}>
                        認証モード:
                      </strong>
                      <div style={{ marginTop: "0.25rem" }}>
                        <span
                          style={{
                            color: config.authEnabled ? "#1976d2" : "#e65100",
                            fontWeight: "500",
                            fontSize: "0.9rem",
                          }}
                        >
                          {config.authEnabled
                            ? "OIDC認証"
                            : "開発モード（認証なし）"}
                        </span>
                      </div>
                    </div>
                    {config.authEnabled && (
                      <div
                        style={{
                          marginTop: "1rem",
                          paddingTop: "0.75rem",
                          borderTop: "1px solid #e0e0e0",
                        }}
                      >
                        <button
                          onClick={handleLogout}
                          style={{
                            width: "100%",
                            padding: "0.75rem",
                            background: "#d32f2f",
                            color: "white",
                            border: "none",
                            borderRadius: "4px",
                            cursor: "pointer",
                            fontSize: "1rem",
                            fontWeight: "bold",
                            transition: "background 0.2s",
                          }}
                          onMouseEnter={(e) =>
                            (e.currentTarget.style.background = "#c62828")
                          }
                          onMouseLeave={(e) =>
                            (e.currentTarget.style.background = "#d32f2f")
                          }
                        >
                          🚪 ログアウト
                        </button>
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          ) : config.authEnabled ? (
            <button
              onClick={handleLogin}
              style={{
                padding: "0.5rem 1.5rem",
                background: "#2196f3",
                color: "white",
                border: "none",
                borderRadius: "4px",
                cursor: "pointer",
                fontSize: "1rem",
                fontWeight: "bold",
              }}
            >
              ログイン
            </button>
          ) : null}
        </div>
      </div>

      {config.authEnabled && !isAuthenticated && (
        <div
          style={{
            padding: "2rem",
            background: "#fff3e0",
            borderRadius: "8px",
            border: "2px solid #ff9800",
            textAlign: "center",
            marginTop: "2rem",
          }}
        >
          <h2 style={{ color: "#e65100", marginTop: 0 }}>認証が必要です</h2>
          <p style={{ fontSize: "1.1rem", marginBottom: "1.5rem" }}>
            このアプリケーションを使用するには、ログインしてください。
          </p>
          <button
            onClick={handleLogin}
            style={{
              padding: "1rem 2rem",
              background: "#2196f3",
              color: "white",
              border: "none",
              borderRadius: "4px",
              cursor: "pointer",
              fontSize: "1.2rem",
              fontWeight: "bold",
            }}
          >
            Keycloakでログイン
          </button>
        </div>
      )}
    </div>
  );
};
