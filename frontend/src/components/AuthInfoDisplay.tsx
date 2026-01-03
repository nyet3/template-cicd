import { useEffect, useState } from "react";
import { useAuth } from "react-oidc-context";
import { api } from "../services/api";
import { config } from "../config";

interface AuthInfoDisplayProps {
  // No props needed
}

export const AuthInfoDisplay: React.FC<AuthInfoDisplayProps> = () => {
  const auth = useAuth();
  const [authInfo, setAuthInfo] = useState<{
    user_id: string;
    email: string;
    name: string;
  } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Don't fetch if auth is loading or not authenticated
    if (!auth || auth.isLoading || !auth.isAuthenticated) {
      return;
    }

    const token = auth.user?.access_token;

    if (!token) {
      setError("トークンが見つかりません");
      return;
    }

    api
      .getAuthInfo(token)
      .then((data) => {
        if (data.success && data.data) {
          setAuthInfo(data.data);
          setError(null);
        }
      })
      .catch((err) => {
        console.error("Failed to fetch auth info:", err);
        setError("認証情報の取得に失敗しました");
      });
  }, [auth]);

  if (error) {
    return (
      <div
        style={{
          padding: "1rem",
          background: "#ffebee",
          borderRadius: "4px",
          color: "#c62828",
        }}
      >
        <h3>エラー</h3>
        <p>{error}</p>
      </div>
    );
  }

  if (!authInfo) {
    return <div>Loading...</div>;
  }

  return (
    <div
      style={{
        padding: "1.5rem",
        background: "#ffffff",
        borderRadius: "8px",
        boxShadow: "0 2px 8px rgba(0,0,0,0.1)",
        border: "1px solid #e0e0e0",
      }}
    >
      <h3 style={{ marginTop: 0, color: "#2e7d32", fontSize: "1.3rem" }}>
        👤 ユーザープロファイル
      </h3>
      <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem" }}>
        <div>
          <strong style={{ color: "#666" }}>User ID:</strong>{" "}
          <span style={{ color: "#333" }}>{authInfo.user_id}</span>
        </div>
        <div>
          <strong style={{ color: "#666" }}>Email:</strong>{" "}
          <span style={{ color: "#333" }}>{authInfo.email}</span>
        </div>
        <div>
          <strong style={{ color: "#666" }}>Name:</strong>{" "}
          <span style={{ color: "#333" }}>{authInfo.name}</span>
        </div>
        <div
          style={{
            marginTop: "0.5rem",
            paddingTop: "0.75rem",
            borderTop: "1px solid #e0e0e0",
          }}
        >
          <strong style={{ color: "#666" }}>認証モード:</strong>{" "}
          <span
            style={{
              color: config.authEnabled ? "#1976d2" : "#f57c00",
              fontWeight: "500",
            }}
          >
            {config.authEnabled ? "OIDC認証" : "開発モード（ダミー認証）"}
          </span>
        </div>
      </div>
    </div>
  );
};
