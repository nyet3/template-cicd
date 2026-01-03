interface Config {
  apiUrl: string;
  authEnabled: boolean;
  oidcAuthority?: string;
  oidcClientId?: string;
  oidcRedirectUri?: string;
}

export const config: Config = {
  // Prefer env, otherwise same-origin to work with nginx reverse proxy (/api -> backend)
  apiUrl: (import.meta.env.VITE_API_URL || window.location.origin).replace(
    /\/$/,
    ""
  ),
  authEnabled: import.meta.env.VITE_AUTH_ENABLED === "true",
  oidcAuthority: import.meta.env.VITE_OIDC_AUTHORITY,
  oidcClientId: import.meta.env.VITE_OIDC_CLIENT_ID,
  oidcRedirectUri:
    import.meta.env.VITE_OIDC_REDIRECT_URI ||
    `${window.location.origin.replace(/\/$/, "")}/callback`,
};

export const oidcConfig =
  config.authEnabled && config.oidcAuthority && config.oidcClientId
    ? {
        authority: config.oidcAuthority,
        client_id: config.oidcClientId,
        redirect_uri: config.oidcRedirectUri!,
        response_type: "code",
        scope: "openid profile email",
        automaticSilentRenew: true,
        loadUserInfo: true,
      }
    : null;
