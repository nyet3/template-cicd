import { useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "react-oidc-context";

export const CallbackPage = () => {
  const auth = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    if (auth.isAuthenticated) {
      navigate("/", { replace: true });
    } else if (auth.error) {
      console.error("OIDC callback error", auth.error);
      navigate("/", { replace: true });
    }
  }, [auth.isAuthenticated, auth.error, navigate]);

  return (
    <div style={{ textAlign: "center", padding: "4rem" }}>
      <h1>Authenticating...</h1>
      <p>Please wait while we complete the authentication process.</p>
    </div>
  );
};
