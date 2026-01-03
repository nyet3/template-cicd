export interface User {
  id: string;
  email: string;
  name: string;
  created_at: string;
}

export interface CreateUserRequest {
  email: string;
  name: string;
}

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
}

export interface AuthInfo {
  user_id: string;
  email: string;
  name: string;
  organization: string;
}
