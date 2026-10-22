/**
 * Flujo unificado de planes: checkout demo/Stripe para pagos, change-plan solo para gratis.
 */
(function initArchitectBilling(global) {
  const SUB_KEY = "plano_ia_subscription";

  function getErrorMessage(data, fallback) {
    if (!data) return fallback;
    if (typeof data.detail === "string") return data.detail;
    if (data.detail && typeof data.detail.message === "string") return data.detail.message;
    if (typeof data.message === "string") return data.message;
    return fallback;
  }

  function isFreePlanSlug(slug) {
    return !slug || slug === "free";
  }

  /** Evita saltar a otro puerto (p. ej. 3000) si APP_BASE_URL no coincide con la pestaña actual. */
  function resolveInAppUrl(url) {
    if (!url) return url;
    if (url.startsWith("/")) return url;
    if (url.startsWith("https://checkout.stripe.com")) return url;
    try {
      const parsed = new URL(url, global.location.origin);
      return parsed.pathname + parsed.search + parsed.hash;
    } catch {
      return url;
    }
  }

  async function requestPlanChange(planSlug, options) {
    const slug = String(planSlug || "").trim().toLowerCase();
    const token = options?.token;
    const returnUrl = options?.returnUrl || "/legacy-app";
    const apiFetch = options?.apiFetch;

    if (!token) {
      throw new Error("Debes iniciar sesión para cambiar de plan");
    }

    if (isFreePlanSlug(slug)) {
      const res = apiFetch
        ? await apiFetch("/api/billing/change-plan", {
            method: "POST",
            body: JSON.stringify({ plan_slug: "free" }),
          })
        : await fetch("/api/billing/change-plan", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${token}`,
            },
            body: JSON.stringify({ plan_slug: "free" }),
          });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(getErrorMessage(data, "No se pudo cambiar al plan gratis"));
      localStorage.setItem(SUB_KEY, JSON.stringify(data));
      return { status: "completed", subscription: data };
    }

    const res = apiFetch
      ? await apiFetch("/api/billing/checkout", {
          method: "POST",
          body: JSON.stringify({ plan_slug: slug, return_url: returnUrl }),
        })
      : await fetch("/api/billing/checkout", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({ plan_slug: slug, return_url: returnUrl }),
        });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(getErrorMessage(data, "No se pudo iniciar el checkout"));

    if (data.status === "completed" || data.status === "already_active") {
      if (data.subscription) localStorage.setItem(SUB_KEY, JSON.stringify(data.subscription));
      return data;
    }

    if (data.checkout_url) {
      global.location.href = resolveInAppUrl(data.checkout_url);
      return { status: "redirecting", ...data };
    }

    throw new Error("Respuesta de checkout inválida");
  }

  async function applySelectedPlanAfterAuth(accessToken, returnUrl) {
    const selectedKey = "plano_ia_selected_plan";
    const planSlug = localStorage.getItem(selectedKey);
    if (!planSlug || isFreePlanSlug(planSlug)) return null;

    try {
      const result = await requestPlanChange(planSlug, {
        token: accessToken,
        returnUrl: returnUrl || "/legacy-app",
      });
      localStorage.removeItem(selectedKey);
      return result;
    } catch {
      return null;
    }
  }

  global.ArchitectBilling = {
    SUB_KEY,
    requestPlanChange,
    applySelectedPlanAfterAuth,
    isFreePlanSlug,
    getErrorMessage,
    resolveInAppUrl,
    async openBillingPortal(options) {
      const token = options?.token;
      const returnUrl = options?.returnUrl || "/legacy-app";
      const apiFetch = options?.apiFetch;
      if (!token) throw new Error("Debes iniciar sesión");

      const res = apiFetch
        ? await apiFetch("/api/billing/portal", {
            method: "POST",
            body: JSON.stringify({ return_url: returnUrl }),
          })
        : await fetch("/api/billing/portal", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${token}`,
            },
            body: JSON.stringify({ return_url: returnUrl }),
          });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(getErrorMessage(data, "No se pudo abrir el portal de Stripe"));
      }
      if (data.url) {
        global.location.href = data.url;
        return { status: "redirecting" };
      }
      throw new Error("Portal sin URL");
    },
    async fetchBillingConfig() {
      const res = await fetch("/api/billing/config");
      if (!res.ok) return { mode: "demo" };
      return res.json();
    },
  };
})(window);
