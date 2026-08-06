export const SUB_KEY = "plano_ia_subscription";

export function isPlanUnlimited(sub) {
  if (!sub) return false;
  if (sub.is_unlimited) return true;
  const limit = sub.plan?.analyses_limit_monthly ?? 0;
  return limit >= 9999;
}

export function formatUsage(sub) {
  if (!sub) {
    return {
      planName: "Plan",
      usageLabel: "—",
      pct: 0,
      limitReached: false,
      isUnlimited: false,
      remaining: null
    };
  }
  const plan = sub.plan || {};
  const usage = sub.usage || {};
  const used = usage.analyses_used ?? 0;
  const unlimited = isPlanUnlimited(sub);

  if (unlimited) {
    return {
      planName: plan.name || plan.slug || "Plan",
      usageLabel: `${used} análisis`,
      pct: 8,
      limitReached: false,
      isUnlimited: true,
      remaining: null
    };
  }

  const limit = plan.analyses_limit_monthly || 0;
  const pct = Math.min(100, Math.round((used / Math.max(limit, 1)) * 100));
  return {
    planName: plan.name || plan.slug || "Plan",
    usageLabel: `${used} / ${limit}`,
    pct,
    limitReached: !!usage.limit_reached,
    isUnlimited: false,
    remaining: usage.analyses_remaining
  };
}

function resolveInAppUrl(url) {
  if (!url) return url;
  if (url.startsWith("/")) return url;
  if (url.startsWith("https://checkout.stripe.com")) return url;
  try {
    const parsed = new URL(url, window.location.origin);
    return parsed.pathname + parsed.search + parsed.hash;
  } catch {
    return url;
  }
}

export function formatPlanPrice(cents) {
  if (!cents) return "Gratis";
  return `$${(cents / 100).toFixed(0)}/mes`;
}

export function formatPlanLimit(limit) {
  if (limit >= 9999) return "Análisis ilimitados";
  return `${limit} análisis/mes`;
}

export function formatPlanStorage(plan) {
  const gb = Number(plan?.storage_gb ?? plan?.features?.storage_gb ?? 0);
  if (!Number.isFinite(gb) || gb <= 0) return null;
  return `${gb} GB de documentación`;
}

export function planFeatureLines(plan) {
  const f = plan.features || {};
  const custom = Array.isArray(f.benefits)
    ? f.benefits.map((line) => String(line).trim()).filter(Boolean)
    : [];
  if (custom.length) return custom;

  const lines = [formatPlanLimit(plan.analyses_limit_monthly)];
  const storage = formatPlanStorage(plan);
  if (storage) lines.push(storage);
  lines.push(plan.allow_real_model ? "Modelo real" : "Modelo demo");
  lines.push(`Archivos hasta ${plan.max_file_mb} MB`);
  if (f.export) lines.push("Exportar reportes");
  if (f.mobile_app) lines.push("App móvil ARCHITECT");
  if (f.sla) lines.push("SLA dedicado");
  if (f.support) lines.push(`Soporte ${f.support}`);
  return lines;
}

function getErrorMessage(data, fallback) {
  if (!data) return fallback;
  if (typeof data.detail === "string") return data.detail;
  if (data.detail?.message) return data.detail.message;
  return fallback;
}

export async function fetchPlans() {
  const res = await fetch("/api/billing/plans");
  if (!res.ok) throw new Error("No se pudieron cargar los planes");
  return res.json();
}

export async function fetchBillingConfig() {
  const res = await fetch("/api/billing/config");
  if (!res.ok) return { mode: "demo", checkout_required_for_paid_plans: true };
  return res.json();
}

export async function openBillingPortal(token, returnUrl = "/app") {
  const res = await fetch("/api/billing/portal", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify({ return_url: returnUrl })
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(getErrorMessage(data, "No se pudo abrir el portal de Stripe"));
  }
  if (data.url) {
    window.location.href = data.url;
    return { status: "redirecting" };
  }
  throw new Error("Portal sin URL");
}

/** @deprecated Usa requestPlanChange — solo conservado para bajadas a gratis internas */
export async function changePlan(planSlug, token) {
  return requestPlanChange(planSlug, token);
}

export async function requestPlanChange(planSlug, token, returnUrl = "/app") {
  const slug = String(planSlug || "").trim().toLowerCase();
  if (!token) throw new Error("Debes iniciar sesión para cambiar de plan");

  if (!slug || slug === "free") {
    const res = await fetch("/api/billing/change-plan", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`
      },
      body: JSON.stringify({ plan_slug: "free" })
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(getErrorMessage(data, "No se pudo cambiar al plan gratis"));
    localStorage.setItem(SUB_KEY, JSON.stringify(data));
    return { status: "completed", subscription: data };
  }

  const res = await fetch("/api/billing/checkout", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify({ plan_slug: slug, return_url: returnUrl })
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(getErrorMessage(data, "No se pudo iniciar el checkout"));

  if (data.status === "completed" || data.status === "already_active") {
    if (data.subscription) localStorage.setItem(SUB_KEY, JSON.stringify(data.subscription));
    return data;
  }

  if (data.checkout_url) {
    window.location.href = resolveInAppUrl(data.checkout_url);
    return { status: "redirecting", ...data };
  }

  throw new Error("Respuesta de checkout inválida");
}

export function planActionLabel(plan, isCurrent) {
  if (isCurrent) return "Plan actual";
  if (!plan.price_monthly_cents) return "Bajar a gratis";
  return "Ir a pagar";
}
