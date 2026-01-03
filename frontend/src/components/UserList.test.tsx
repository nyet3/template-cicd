import { describe, it, expect, vi } from "vitest";
import { render } from "@testing-library/react";
import { UserList } from "./UserList";

// Mock react-oidc-context
vi.mock("react-oidc-context", () => ({
  useAuth: () => ({
    isAuthenticated: false,
    isLoading: false,
    error: null,
    user: null,
  }),
}));

describe("UserList", () => {
  it("renders without error", () => {
    const { container } = render(<UserList />);
    expect(container).toBeTruthy();
  });
});
