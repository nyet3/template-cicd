import { useState, useEffect, useCallback } from "react";
import { useAuth } from "react-oidc-context";
import { api } from "../services/api";
import type { User, CreateUserRequest } from "../types";

export const UserList = () => {
  const auth = useAuth();
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [newUser, setNewUser] = useState<CreateUserRequest>({
    email: "",
    name: "",
  });

  const loadUsers = useCallback(async () => {
    // Don't fetch if auth is loading or not authenticated
    if (!auth || auth.isLoading || !auth.isAuthenticated) {
      return;
    }

    try {
      setLoading(true);
      setError(null);
      const token = auth.user?.access_token;

      if (!token) {
        setError("トークンが見つかりません");
        setLoading(false);
        return;
      }

      const response = await api.getUsers(token);
      if (response.success && response.data) {
        setUsers(response.data);
      } else {
        setError(response.error || "Failed to load users");
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      if (errorMessage.includes("401")) {
        setError("認証が必要です。ログインしてください。");
      } else {
        setError(errorMessage);
      }
    } finally {
      setLoading(false);
    }
  }, [auth]);

  useEffect(() => {
    loadUsers();
  }, [loadUsers]);

  const handleCreateUser = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const token = auth?.user?.access_token;
      const response = await api.createUser(newUser, token);
      if (response.success) {
        setNewUser({ email: "", name: "" });
        loadUsers();
      } else {
        setError(response.error || "Failed to create user");
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      if (errorMessage.includes("401")) {
        setError("認証が必要です。ログインしてください。");
      } else {
        setError(errorMessage);
      }
    }
  };

  const handleDeleteUser = async (id: string) => {
    if (!confirm("本当に削除しますか？")) return;

    try {
      const token = auth?.user?.access_token;
      const response = await api.deleteUser(id, token);
      if (response.success) {
        loadUsers();
      } else {
        setError(response.error || "Failed to delete user");
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Unknown error";
      if (errorMessage.includes("401")) {
        setError("認証が必要です。ログインしてください。");
      } else {
        setError(errorMessage);
      }
    }
  };

  if (loading) return <div>Loading...</div>;
  if (error) return <div style={{ color: "red" }}>Error: {error}</div>;

  return (
    <div style={{ padding: "1rem" }}>
      <h2>User List</h2>

      <form onSubmit={handleCreateUser} style={{ marginBottom: "2rem" }}>
        <h3>新規ユーザー作成</h3>
        <div style={{ marginBottom: "0.5rem" }}>
          <input
            type="email"
            placeholder="Email"
            value={newUser.email}
            onChange={(e) => setNewUser({ ...newUser, email: e.target.value })}
            required
            style={{ marginRight: "0.5rem", padding: "0.5rem" }}
          />
          <input
            type="text"
            placeholder="Name"
            value={newUser.name}
            onChange={(e) => setNewUser({ ...newUser, name: e.target.value })}
            required
            style={{ marginRight: "0.5rem", padding: "0.5rem" }}
          />
          <button type="submit" style={{ padding: "0.5rem 1rem" }}>
            作成
          </button>
        </div>
      </form>

      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr style={{ borderBottom: "2px solid #ccc" }}>
            <th style={{ padding: "0.5rem", textAlign: "left" }}>ID</th>
            <th style={{ padding: "0.5rem", textAlign: "left" }}>Email</th>
            <th style={{ padding: "0.5rem", textAlign: "left" }}>Name</th>
            <th style={{ padding: "0.5rem", textAlign: "left" }}>Created</th>
            <th style={{ padding: "0.5rem", textAlign: "left" }}>Actions</th>
          </tr>
        </thead>
        <tbody>
          {users.map((user) => (
            <tr key={user.id} style={{ borderBottom: "1px solid #eee" }}>
              <td style={{ padding: "0.5rem" }}>{user.id}</td>
              <td style={{ padding: "0.5rem" }}>{user.email}</td>
              <td style={{ padding: "0.5rem" }}>{user.name}</td>
              <td style={{ padding: "0.5rem" }}>
                {new Date(user.created_at).toLocaleString()}
              </td>
              <td style={{ padding: "0.5rem" }}>
                <button
                  onClick={() => handleDeleteUser(user.id)}
                  style={{
                    padding: "0.25rem 0.5rem",
                    background: "#dc3545",
                    color: "white",
                    border: "none",
                    borderRadius: "4px",
                    cursor: "pointer",
                  }}
                >
                  削除
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {users.length === 0 && (
        <p style={{ textAlign: "center", padding: "2rem", color: "#666" }}>
          ユーザーがいません
        </p>
      )}
    </div>
  );
};
