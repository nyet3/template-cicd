import { config } from "../config";
import type { User, CreateUserRequest, ApiResponse, AuthInfo } from "../types";

function getAuthHeader(token?: string): HeadersInit {
  // In development, no auth header needed
  if (!config.authEnabled) {
    return {};
  }

  // Use provided token or try to get from localStorage
  const authToken = token || localStorage.getItem("oidc_access_token");
  if (authToken) {
    return {
      Authorization: `Bearer ${authToken}`,
    };
  }

  return {};
}

async function fetchApi<T>(
  endpoint: string,
  options: RequestInit = {},
  token?: string
): Promise<ApiResponse<T>> {
  const headers = {
    "Content-Type": "application/json",
    ...getAuthHeader(token),
    ...options.headers,
  };

  const response = await fetch(`${config.apiUrl}${endpoint}`, {
    ...options,
    headers,
  });

  if (!response.ok) {
    throw new Error(`API Error: ${response.status} ${response.statusText}`);
  }

  return response.json();
}

export const api = {
  async getHealth() {
    const response = await fetch(`${config.apiUrl}/health`);
    return response.json();
  },

  async getAuthInfo(token?: string): Promise<ApiResponse<AuthInfo>> {
    return fetchApi<AuthInfo>("/api/auth/info", {}, token);
  },

  async getUsers(token?: string): Promise<ApiResponse<User[]>> {
    return fetchApi<User[]>("/api/users", {}, token);
  },

  async getUser(id: string, token?: string): Promise<ApiResponse<User>> {
    return fetchApi<User>(`/api/users/${id}`, {}, token);
  },

  async createUser(
    data: CreateUserRequest,
    token?: string
  ): Promise<ApiResponse<User>> {
    return fetchApi<User>(
      "/api/users",
      {
        method: "POST",
        body: JSON.stringify(data),
      },
      token
    );
  },

  async deleteUser(id: string, token?: string): Promise<ApiResponse<boolean>> {
    return fetchApi<boolean>(
      `/api/users/${id}`,
      {
        method: "DELETE",
      },
      token
    );
  },
};
