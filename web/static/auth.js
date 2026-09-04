const TOKEN_KEY = "plano_ia_token";
const USER_KEY = "plano_ia_user";
const SUB_KEY = "plano_ia_subscription";
const SELECTED_PLAN_KEY = "plano_ia_selected_plan";
const STAFF_BACKUP_KEY = "plano_ia_staff_backup";

function getToken() {
  return localStorage.getItem(TOKEN_KEY);
}

function setSession(data) {
  localStorage.setItem(TOKEN_KEY, data.access_token);
  localStorage.setItem(USER_KEY, JSON.stringify(data.user));
  localStorage.setItem(SUB_KEY, JSON.stringify(data.subscription));
}

function getStaffBackup() {
  try {
    return JSON.parse(localStorage.getItem(STAFF_BACKUP_KEY) || "null");
  } catch {
    return null;
  }
}

function isImpersonating() {
  return !!getStaffBackup();
}

function startImpersonation(data) {
  const backup = {
    access_token: getToken(),
    user: getUser(),
    subscription: getSubscription(),
    impersonator: data.impersonator || null,
  };
  if (!backup.access_token || !backup.user) {
    throw new Error("No hay sesión de soporte/admin para respaldar");
  }
  localStorage.setItem(STAFF_BACKUP_KEY, JSON.stringify(backup));
  setSession(data);
  const role = backup.user?.role;
  const backHash = role === "support" ? "#support/support-inbox" : "#accounts/users";
  sessionStorage.setItem("impersonation_return", `/app/admin${backHash}`);
  window.location.href = "/legacy-app?impersonating=1";
}

function stopImpersonation() {
  const backup = getStaffBackup();
  if (!backup?.access_token) {
    localStorage.removeItem(STAFF_BACKUP_KEY);
    window.location.href = "/app/admin";
    return;
  }
  localStorage.setItem(TOKEN_KEY, backup.access_token);
  localStorage.setItem(USER_KEY, JSON.stringify(backup.user || null));
  localStorage.setItem(SUB_KEY, JSON.stringify(backup.subscription || null));
  localStorage.removeItem(STAFF_BACKUP_KEY);
  const ret = sessionStorage.getItem("impersonation_return") || "/app/admin";
  sessionStorage.removeItem("impersonation_return");
  window.location.href = ret;
}

function defaultPostLoginPath(user) {
  if (user?.role === "support") return "/app/admin#support/support-inbox";
  if (user?.role === "admin") return "/app/admin";
  return "/legacy-app";
}

async function applySelectedPlan(accessToken) {
  const planSlug = localStorage.getItem(SELECTED_PLAN_KEY);
  if (!planSlug || planSlug === "free") return false;
  if (!window.ArchitectBilling) return false;

  try {
    const result = await window.ArchitectBilling.requestPlanChange(planSlug, {
      token: accessToken,
      returnUrl: "/legacy-app",
    });
    localStorage.removeItem(SELECTED_PLAN_KEY);
    return result?.status === "redirecting";
  } catch {
    return false;
  }
}

function clearSession() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
  localStorage.removeItem(SUB_KEY);
  localStorage.removeItem(STAFF_BACKUP_KEY);
  sessionStorage.removeItem("impersonation_return");
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
  let res;
  try {
    res = await fetch(url, { ...options, headers });
  } catch (err) {
    const offline = typeof navigator.onLine === "boolean" && !navigator.onLine;
    const msg = offline
      ? "Sin conexión. Puedes seguir trabajando en Casa hogar con los datos guardados."
      : err?.message || "Error de red";
    const e = new Error(msg);
    e.isNetworkError = true;
    e.isOffline = offline;
    throw e;
  }
  // Solo cerrar sesión con 401 si hay red real (evitar borrar JWT offline).
  if (res.status === 401 && navigator.onLine !== false) {
    clearSession();
    const loginUrl = "/login";
    if (window.top !== window.self) {
      window.top.location.href = loginUrl;
    } else if (!window.location.pathname.includes("login")) {
      window.location.href = loginUrl;
    }
    throw new Error("Sesión expirada");
  }
  return res;
}

function hasLocalSession() {
  return !!(getToken() && getUser());
}

function isOnline() {
  if (window.ArchitectOffline?.isOnline) return window.ArchitectOffline.isOnline();
  return typeof navigator.onLine === "boolean" ? navigator.onLine : true;
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
  if (isImpersonating()) {
    stopImpersonation();
    return;
  }
  clearSession();
  window.location.href = "/login";
}

/* Login page */
if (document.getElementById("loginForm")) {
  if (getToken()) {
    showAppLoader("Ya tienes sesión activa…");
    const pendingInvite = sessionStorage.getItem("pending_invite");
    if (pendingInvite) {
      window.location.href = `/legacy-app?invite=${encodeURIComponent(pendingInvite)}`;
    } else if (sessionStorage.getItem("open_home_projects") === "1") {
      window.location.href = "/legacy-app?home-projects=1";
    } else {
      window.location.href = defaultPostLoginPath(getUser());
    }
  }

  async function finishOAuthFromUrl() {
    const params = new URLSearchParams(window.location.search);
    const oauthError = params.get("oauth_error");
    const accessToken = params.get("access_token");
    if (!oauthError && !accessToken) return false;

    if (oauthError) {
      const err = document.getElementById("loginError");
      if (err) {
        err.textContent = decodeURIComponent(oauthError);
        err.classList.remove("hidden");
      }
      window.history.replaceState({}, "", "/login");
      return true;
    }

    document.body.dataset.authBusy = "1";
    showAppLoader("Completando acceso con Google…");
    try {
      localStorage.setItem(TOKEN_KEY, accessToken);
      const me = await refreshMe();
      if (!me) throw new Error("Sesión inválida");
      const checkoutRedirect = await applySelectedPlan(accessToken);
      if (checkoutRedirect) return true;
      window.history.replaceState({}, "", "/login");
      window.location.href = defaultPostLoginPath(me?.user || getUser());
    } catch {
      clearSession();
      const err = document.getElementById("loginError");
      if (err) {
        err.textContent = "No se pudo completar el acceso con Google";
        err.classList.remove("hidden");
      }
      delete document.body.dataset.authBusy;
      hideAppLoader();
      window.history.replaceState({}, "", "/login");
    }
    return true;
  }

  finishOAuthFromUrl();

  const inviteFromUrl = new URLSearchParams(window.location.search).get("invite");
  if (inviteFromUrl) sessionStorage.setItem("pending_invite", inviteFromUrl);

  function postAuthRedirect() {
    const params = new URLSearchParams(window.location.search);
    const next = params.get("next");
    const user = getUser();
    if (user?.role === "support" || user?.role === "admin") {
      window.location.href = defaultPostLoginPath(user);
      return;
    }
    if (next && next.startsWith("/")) {
      window.location.href = next;
      return;
    }
    const pendingInvite = sessionStorage.getItem("pending_invite");
    if (pendingInvite) {
      window.location.href = `/legacy-app?invite=${encodeURIComponent(pendingInvite)}`;
      return;
    }
    if (sessionStorage.getItem("open_home_projects") === "1") {
      window.location.href = "/legacy-app?home-projects=1";
      return;
    }
    window.location.href = "/legacy-app";
  }

  fetch("/api/auth/google/enabled")
    .then((r) => r.json())
    .then((data) => {
      if (!data.enabled) return;
      document.getElementById("googleLoginWrap")?.classList.remove("hidden");
      document.getElementById("googleRegisterWrap")?.classList.remove("hidden");
    })
    .catch(() => {});

  document.getElementById("btnGoogleLogin")?.addEventListener("click", () => {
    window.location.href = "/api/auth/google";
  });
  document.getElementById("btnGoogleRegister")?.addEventListener("click", () => {
    window.location.href = "/api/auth/google";
  });

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
      const checkoutRedirect = await applySelectedPlan(data.access_token);
      if (checkoutRedirect) return;
      showAppLoader("Entrando al estudio…");
      postAuthRedirect();
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
      const checkoutRedirect = await applySelectedPlan(data.access_token);
      if (checkoutRedirect) return;
      showAppLoader("Preparando tu espacio…");
      postAuthRedirect();
    } catch {
      err.textContent = "No se pudo conectar con el servidor.";
      err.classList.remove("hidden");
      delete document.body.dataset.authBusy;
      hideAppLoader();
      setAuthFormLoading(form, false);
    }
  };

  initLoginPageBootLoader();
  initAuthPageUi();
}

function initAuthPageUi() {
  if (!document.getElementById("loginForm")) return;

  document.querySelectorAll(".auth-toggle-pw").forEach((btn) => {
    btn.addEventListener("click", () => {
      const input = document.getElementById(btn.dataset.target);
      if (!input) return;
      const reveal = input.type === "password";
      input.type = reveal ? "text" : "password";
      btn.setAttribute("aria-label", reveal ? "Ocultar contraseña" : "Mostrar contraseña");
      const icon = btn.querySelector(".material-symbols-outlined");
      if (icon) icon.textContent = reveal ? "visibility_off" : "visibility";
    });
  });

  initAuthTabs();
  initForgotResetViews();

  fetch("/api/health")
    .then((r) => r.json())
    .then((h) => {
      if (h.ok) return;
      const el = document.getElementById("dbStatus");
      if (!el) return;
      el.classList.remove("hidden");
      el.textContent =
        "MySQL no conectado. Enciende el servicio, crea la base plano_ia y ejecuta: python scripts/init_db.py";
    })
    .catch(() => {});
}

function setAuthView(mode) {
  const main = document.getElementById("authMainViews");
  const forgot = document.getElementById("authForgotView");
  const reset = document.getElementById("authResetView");
  const title = document.getElementById("authViewTitle");
  const subtitle = document.getElementById("authViewSubtitle");
  const tabs = document.getElementById("authTabs");

  main?.classList.toggle("hidden", mode !== "main");
  forgot?.classList.toggle("hidden", mode !== "forgot");
  reset?.classList.toggle("hidden", mode !== "reset");
  tabs?.classList.toggle("hidden", mode !== "main");

  if (mode === "forgot") {
    if (title) title.textContent = "Recuperar contraseña";
    if (subtitle) subtitle.textContent = "Te enviaremos un enlace seguro a tu correo";
  } else if (mode === "reset") {
    if (title) title.textContent = "Nueva contraseña";
    if (subtitle) subtitle.textContent = "El enlace expira en 1 hora";
  } else {
    if (title) title.textContent = "Accede a tu cuenta";
    if (subtitle) subtitle.textContent = "Revisa planos con IA y normativa de referencia";
  }
}

function initForgotResetViews() {
  const params = new URLSearchParams(window.location.search);
  const resetToken = params.get("reset");

  document.getElementById("btnForgotPassword")?.addEventListener("click", () => {
    document.getElementById("forgotError")?.classList.add("hidden");
    document.getElementById("forgotSuccess")?.classList.add("hidden");
    const loginEmail = document.getElementById("loginEmail")?.value?.trim();
    const forgotEmail = document.getElementById("forgotEmail");
    if (forgotEmail && loginEmail) forgotEmail.value = loginEmail;
    setAuthView("forgot");
  });

  document.getElementById("btnBackFromForgot")?.addEventListener("click", () => setAuthView("main"));
  document.getElementById("btnBackFromReset")?.addEventListener("click", () => {
    window.history.replaceState({}, "", "/login");
    setAuthView("main");
  });

  document.getElementById("forgotForm")?.addEventListener("submit", async (e) => {
    e.preventDefault();
    const form = e.target;
    const err = document.getElementById("forgotError");
    const ok = document.getElementById("forgotSuccess");
    err?.classList.add("hidden");
    ok?.classList.add("hidden");
    setAuthFormLoading(form, true);
    try {
      const res = await fetch("/api/auth/forgot-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: document.getElementById("forgotEmail").value.trim() }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        err.textContent = formatApiError(data, "No se pudo enviar el enlace");
        err.classList.remove("hidden");
        return;
      }
      ok.textContent = data.message || "Revisa tu bandeja de entrada y spam.";
      ok.classList.remove("hidden");
    } catch {
      err.textContent = "No se pudo conectar con el servidor.";
      err.classList.remove("hidden");
    } finally {
      setAuthFormLoading(form, false);
    }
  });

  document.getElementById("resetForm")?.addEventListener("submit", async (e) => {
    e.preventDefault();
    const form = e.target;
    const err = document.getElementById("resetError");
    const ok = document.getElementById("resetSuccess");
    const token = form.dataset.token || "";
    const p1 = document.getElementById("resetPassword").value;
    const p2 = document.getElementById("resetPassword2").value;
    err?.classList.add("hidden");
    ok?.classList.add("hidden");
    if (p1 !== p2) {
      err.textContent = "Las contraseñas no coinciden";
      err.classList.remove("hidden");
      return;
    }
    setAuthFormLoading(form, true);
    try {
      const res = await fetch("/api/auth/reset-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, password: p1 }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        err.textContent = formatApiError(data, "No se pudo actualizar la contraseña");
        err.classList.remove("hidden");
        return;
      }
      ok.textContent = data.message || "Contraseña actualizada.";
      ok.classList.remove("hidden");
      document.getElementById("resetSubmitBtn").disabled = true;
      window.setTimeout(() => {
        window.history.replaceState({}, "", "/login");
        setAuthView("main");
      }, 1800);
    } catch {
      err.textContent = "No se pudo conectar con el servidor.";
      err.classList.remove("hidden");
    } finally {
      setAuthFormLoading(form, false);
    }
  });

  if (resetToken) {
    initResetFromToken(resetToken);
  }
}

async function initResetFromToken(token) {
  setAuthView("reset");
  const form = document.getElementById("resetForm");
  const err = document.getElementById("resetError");
  const intro = document.getElementById("resetIntro");
  if (form) form.dataset.token = token;
  try {
    const res = await fetch(`/api/auth/reset-password/validate?token=${encodeURIComponent(token)}`);
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(formatApiError(data, "Enlace inválido o expirado"));
    if (intro) intro.textContent = `Nueva contraseña para ${data.email}`;
  } catch (e) {
    if (err) {
      err.textContent = e.message || "Enlace inválido o expirado";
      err.classList.remove("hidden");
    }
    document.getElementById("resetSubmitBtn")?.setAttribute("disabled", "disabled");
  }
}

function initAuthTabs() {
  const tabsEl = document.getElementById("authTabs");
  const indicator = document.getElementById("authTabIndicator");
  const panelsEl = document.getElementById("authPanels");
  const loginForm = document.getElementById("loginForm");
  const registerForm = document.getElementById("registerForm");
  if (!tabsEl || !indicator || !panelsEl || !loginForm || !registerForm) return;

  let currentTab = "login";
  let animating = false;

  function syncIndicator(tab) {
    indicator.classList.toggle("auth-tab-indicator--register", tab === "register");
  }

  function panelHeight(el) {
    return el.offsetHeight;
  }

  function setPanelsHeight(px) {
    panelsEl.style.height = px ? px + "px" : "";
  }

  function hidePanel(panel) {
    panel.classList.remove(
      "auth-panel--active",
      "auth-panel--exit-left",
      "auth-panel--exit-right",
      "auth-panel--enter-left",
      "auth-panel--enter-right"
    );
    panel.hidden = true;
  }

  function switchTab(tab) {
    if (tab === currentTab || animating) return;
    const toRegister = tab === "register";
    const outgoing = toRegister ? loginForm : registerForm;
    const incoming = toRegister ? registerForm : loginForm;

    animating = true;
    document.querySelectorAll(".auth-tab").forEach((b) => {
      const on = b.dataset.tab === tab;
      b.classList.toggle("active", on);
      b.setAttribute("aria-selected", on ? "true" : "false");
    });
    syncIndicator(tab);
    panelsEl.dataset.tab = tab;
    document.getElementById("loginError")?.classList.add("hidden");
    document.getElementById("regError")?.classList.add("hidden");

    outgoing.classList.remove("auth-panel--active");
    outgoing.classList.add(toRegister ? "auth-panel--exit-left" : "auth-panel--exit-right");

    incoming.hidden = false;
    incoming.classList.add(
      "auth-panel--active",
      toRegister ? "auth-panel--enter-right" : "auth-panel--enter-left"
    );
    setPanelsHeight(panelHeight(incoming));

    requestAnimationFrame(() => {
      incoming.classList.remove("auth-panel--enter-right", "auth-panel--enter-left");
    });

    window.setTimeout(() => {
      hidePanel(outgoing);
      currentTab = tab;
      setPanelsHeight(panelHeight(incoming));
      animating = false;
    }, 380);
  }

  syncIndicator("login");
  setPanelsHeight(panelHeight(loginForm));
  window.addEventListener("resize", () => {
    const active = currentTab === "login" ? loginForm : registerForm;
    if (!active.hidden) setPanelsHeight(panelHeight(active));
  });

  document.querySelectorAll(".auth-tab").forEach((btn) => {
    btn.addEventListener("click", () => switchTab(btn.dataset.tab));
  });

  if (window.location.hash === "#register") switchTab("register");
  if (new URLSearchParams(window.location.search).get("tab") === "register") switchTab("register");
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
  hasLocalSession,
  isOnline,
  isImpersonating,
  getStaffBackup,
  startImpersonation,
  stopImpersonation,
  defaultPostLoginPath,
};
