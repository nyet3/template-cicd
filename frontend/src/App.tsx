import { BrowserRouter as Router, Routes, Route } from "react-router-dom";
import { AuthProvider } from "react-oidc-context";
import { oidcConfig } from "./config";
import { HomePage } from "./pages/HomePage";
import { CallbackPage } from "./pages/CallbackPage";

const AppContent = () => {
  return (
    <Router>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/callback" element={<CallbackPage />} />
      </Routes>
    </Router>
  );
};

function App() {
  // Always wrap with AuthProvider to prevent context undefined errors
  // In development mode without auth, use mock config
  const authConfig = oidcConfig || {
    authority: "http://localhost:8443",
    client_id: "mock-client",
    redirect_uri: `${window.location.origin}/callback`,
    response_type: "code",
    scope: "openid profile email",
  };

  return (
    <AuthProvider
      {...authConfig}
      onSigninCallback={(user) => {
        if (user?.access_token) {
          localStorage.setItem("oidc_access_token", user.access_token);
        }
        window.history.replaceState({}, document.title, "/");
      }}
    >
      <AppContent />
    </AuthProvider>
  );
}

export default App;
