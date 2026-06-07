const TOKEN_KEY = "plano_ia_token";
const USER_KEY = "plano_ia_user";
const SUB_KEY = "plano_ia_subscription";
const SELECTED_PLAN_KEY = "plano_ia_selected_plan";

function getToken() {
  return localStorage.getItem(TOKEN_KEY);
}

function setSession(data) {
  localStorage.setItem(TOKEN_KEY, data.access_token);
  localStorage.setItem(USER_KEY, JSON.stringify(data.user));
  localStorage.setItem(SUB_KEY, JSON.stringify(data.subscription));
}

async function applySelectedPlan(accessToken) {
  const planSlug = localStorage.getItem(SELECTED_PLAN_KEY);
  if (!planSlug || planSlug === "free") return;

  try {
    const res = await fetch("/api/billing/change-plan", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ plan_slug: planSlug }),
    });
    if (res.ok) {
      const subscription = await res.json();
      localStorage.setItem(SUB_KEY, JSON.stringify(subscription));
      localStorage.removeItem(SELECTED_PLAN_KEY);
    }
  } catch {
    // El registro no depende del cambio de plan; se puede cambiar dentro de la app.
  }
}

function clearSession() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
  localStorage.removeItem(SUB_KEY);
}

function getUser() {
  try {
    return JSON.parse(localStorage.getItem(USER_KEY) || "null");
  } catch {
    return null;
  }
}

function getSubscription() {
  try {
    return JSON.parse(localStorage.getItem(SUB_KEY) || "null");
  } catch {
    return null;
  }
}

async function apiFetch(url, options = {}) {
  const headers = { ...(options.headers || {}) };
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  if (options.body && !(options.body instanceof FormData)) {
    headers["Content-Type"] = headers["Content-Type"] || "application/json";
  }
  const res = await fetch(url, { ...options, headers });
  if (res.status === 401) {
    clearSession();
    if (!window.location.pathname.includes("login")) {
      window.location.href = "/login";
    }
    throw new Error("Sesión expirada");
  }
  return res;
}

async function refreshMe() {
  const res = await apiFetch("/api/auth/me");
  if (!res.ok) return null;
  const data = await res.json();
  localStorage.setItem(USER_KEY, JSON.stringify(data.user));
  localStorage.setItem(SUB_KEY, JSON.stringify(data.subscription));
  return data;
}

function formatApiError(data, fallback) {
  if (!data) return fallback;
  if (typeof data.detail === "string") return data.detail;
  if (Array.isArray(data.detail)) {
    return data.detail.map((d) => d.msg || d.message || JSON.stringify(d)).join(". ");
  }
  return fallback;
}

function showAppLoader(text) {
  const el = document.getElementById("appLoader");
  if (!el) return;
  const textEl = document.getElementById("appLoaderText");
  if (textEl && text) textEl.textContent = text;
  document.body.classList.add("app-loading");
  el.classList.add("app-loader--visible");
  el.setAttribute("aria-busy", "true");
}

function hideAppLoader() {
  const el = document.getElementById("appLoader");
  if (!el) return;
  el.classList.remove("app-loader--visible");
  el.setAttribute("aria-busy", "false");
  document.body.classList.remove("app-loading");
}

function initLoginPageBootLoader() {
  if (!document.getElementById("loginForm")) return;
  const MIN_MS = 420;
  const t0 = performance.now();

  function tryHide() {
    if (document.body.dataset.authBusy === "1") return;
    const wait = Math.max(0, MIN_MS - (performance.now() - t0));
    window.setTimeout(() => {
      if (document.body.dataset.authBusy === "1") return;
      hideAppLoader();
    }, wait);
  }

  if (document.readyState === "complete") tryHide();
  else window.addEventListener("load", tryHide, { once: true });
}

function setAuthFormLoading(form, loading) {
  if (!form) return;
  form.querySelectorAll("input, button").forEach((node) => {
    if (loading) {
      if (!node.dataset.loaderLocked) {
        node.dataset.loaderWasDisabled = node.disabled ? "1" : "0";
        node.dataset.loaderLocked = "1";
      }
      node.disabled = true;
    } else if (node.dataset.loaderLocked) {
      node.disabled = node.dataset.loaderWasDisabled === "1";
      delete node.dataset.loaderWasDisabled;
      delete node.dataset.loaderLocked;
    }
  });
}

function requireAuth() {
  if (!getToken()) {
    window.location.href = "/login";
    return false;
  }
  return true;
}

function logout() {
  clearSession();
  window.location.href = "/login";
}

/* Login page */
if (document.getElementById("loginForm")) {
  if (getToken()) {
    showAppLoader("Ya tienes sesión activa…");
    window.location.href = "/app";
  }

  document.getElementById("loginForm").onsubmit = async (e) => {
    e.preventDefault();
    const form = e.target;
    const err = document.getElementById("loginError");
    err.classList.add("hidden");
    document.body.dataset.authBusy = "1";
    showAppLoader("Iniciando sesión…");
    setAuthFormLoading(form, true);
    try {
      const res = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: document.getElementById("loginEmail").value.trim(),
          password: document.getElementById("loginPassword").value,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        err.textContent = formatApiError(data, "Error al iniciar sesión");
        err.classList.remove("hidden");
        delete document.body.dataset.authBusy;
        hideAppLoader();
        setAuthFormLoading(form, false);
        return;
      }
      setSession(data);
      showAppLoader("Entrando al estudio…");
      window.location.href = "/app";
    } catch {
      err.textContent = "No se pudo conectar con el servidor.";
      err.classList.remove("hidden");
      delete document.body.dataset.authBusy;
      hideAppLoader();
      setAuthFormLoading(form, false);
    }
  };

  document.getElementById("registerForm").onsubmit = async (e) => {
    e.preventDefault();
    const form = e.target;
    const err = document.getElementById("regError");
    err.classList.add("hidden");
    document.body.dataset.authBusy = "1";
    showAppLoader("Creando tu cuenta…");
    setAuthFormLoading(form, true);
    try {
      const res = await fetch("/api/auth/register", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: document.getElementById("regEmail").value.trim(),
          password: document.getElementById("regPassword").value,
          full_name: document.getElementById("regName").value.trim(),
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        err.textContent = formatApiError(data, "Error al registrarse");
        err.classList.remove("hidden");
        delete document.body.dataset.authBusy;
        hideAppLoader();
        setAuthFormLoading(form, false);
        return;
      }
      setSession(data);
      await applySelectedPlan(data.access_token);
      showAppLoader("Preparando tu espacio…");
      window.location.href = "/app";
    } catch {
      err.textContent = "No se pudo conectar con el servidor.";
      err.classList.remove("hidden");
      delete document.body.dataset.authBusy;
      hideAppLoader();
      setAuthFormLoading(form, false);
    }
  };

  initLoginPageBootLoader();
}

function isLoggedIn() {
  return !!getToken();
}

window.PlanoLoader = {
  show: showAppLoader,
  hide: hideAppLoader,
};

window.PlanoAuth = {
  getToken,
  getUser,
  getSubscription,
  setSession,
  clearSession,
  apiFetch,
  refreshMe,
  requireAuth,
  logout,
  formatApiError,
  isLoggedIn,
};
