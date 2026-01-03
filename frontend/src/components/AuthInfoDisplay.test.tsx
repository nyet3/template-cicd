import { describe, it, expect, vi } from "vitest";
import { render } from "@testing-library/react";
import { AuthInfoDisplay } from "./AuthInfoDisplay";

// Mock react-oidc-context
vi.mock("react-oidc-context", () => ({
  useAuth: () => ({
    isAuthenticated: false,
    isLoading: false,
    error: null,
    user: null,
  }),
}));

describe("AuthInfoDisplay", () => {
  it("renders without error", () => {
    const { container } = render(<AuthInfoDisplay />);
    expect(container).toBeTruthy();
  });
});
