import { describe, it, expect, vi } from "vitest";
import { render } from "@testing-library/react";
import App from "./App";

// Mock react-oidc-context
vi.mock("react-oidc-context", () => ({
  AuthProvider: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
  useAuth: () => ({
    isAuthenticated: false,
    isLoading: false,
    error: null,
    user: null,
  }),
}));

describe("App", () => {
  it("renders without crashing", () => {
    const { container } = render(<App />);
    expect(container).toBeTruthy();
  });
});
