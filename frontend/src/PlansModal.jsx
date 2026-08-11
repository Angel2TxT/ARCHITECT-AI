import React, { useCallback, useEffect, useState } from "react";
import { Loader2, X } from "lucide-react";
import {
  fetchBillingConfig,
  fetchPlans,
  formatPlanLimit,
  formatPlanPrice,
  formatUsage,
  isPlanDowngrade,
  openBillingPortal,
  planActionLabel,
  planFeatureLines,
  requestPlanChange
} from "./subscription.js";

const TOKEN_KEY = "plano_ia_token";
const SUB_KEY = "plano_ia_subscription";

export default function PlansModal({ open, onClose, subscription, onSubscriptionChange }) {
  const [plans, setPlans] = useState([]);
  const [loading, setLoading] = useState(false);
  const [busySlug, setBusySlug] = useState(null);
  const [error, setError] = useState("");
  const [billingMode, setBillingMode] = useState("demo");
  const [portalBusy, setPortalBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [planRows, config] = await Promise.all([fetchPlans(), fetchBillingConfig()]);
      setPlans(planRows);
      setBillingMode(config.mode || "demo");
    } catch (err) {
      setError(err.message || "Error al cargar planes");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (open) load();
  }, [open, load]);

  async function selectPlan(slug) {
    const token = localStorage.getItem(TOKEN_KEY);
    if (!token) return;
    setBusySlug(slug);
    setError("");
    try {
      const next = await requestPlanChange(slug, token, "/app");
      if (next.status === "redirecting") return;
      const subscription = next.subscription || next;
      localStorage.setItem(SUB_KEY, JSON.stringify(subscription));
      onSubscriptionChange?.(subscription);
      await load();
    } catch (err) {
      setError(err.message || "No se pudo cambiar el plan");
    } finally {
      setBusySlug(null);
    }
  }

  async function openPortal() {
    const token = localStorage.getItem(TOKEN_KEY);
    if (!token) return;
    setPortalBusy(true);
    setError("");
    try {
      await openBillingPortal(token, "/app");
    } catch (err) {
      setError(err.message || "No se pudo abrir el portal de Stripe");
      setPortalBusy(false);
    }
  }

  if (!open) return null;

  const usage = formatUsage(subscription);
  const currentSlug = subscription?.plan?.slug;
  const currentPrice = Number(subscription?.plan?.price_monthly_cents || 0);
  const showPortal = billingMode === "stripe" && subscription?.has_active_payment;

  return (
    <div className="plans-overlay" role="presentation" onClick={onClose}>
      <div
        className="plans-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="plans-modal-title"
        onClick={(e) => e.stopPropagation()}
      >
        <header className="plans-modal-head">
          <div>
            <h2 id="plans-modal-title">Planes y suscripción</h2>
            <p className="plans-modal-sub">
              {usage.isUnlimited
                ? `Plan ${usage.planName}: uso ilimitado este mes (${subscription?.usage?.analyses_used ?? 0} análisis).`
                : `Plan ${usage.planName}: ${usage.usageLabel} análisis este mes${
                    usage.remaining != null ? ` (${usage.remaining} restantes).` : "."
                  }`}
            </p>
          </div>
          <button type="button" className="plans-modal-close" onClick={onClose} aria-label="Cerrar">
            <X size={18} />
          </button>
        </header>

        {error && <p className="plans-modal-error">{error}</p>}

        {loading ? (
          <div className="plans-modal-loading">
            <Loader2 className="spin" size={24} />
            <span>Cargando planes…</span>
          </div>
        ) : (
          <div className="plans-modal-grid">
            {plans.map((plan) => {
              const isCurrent = plan.slug === currentSlug;
              const isDowngrade = !isCurrent && isPlanDowngrade(plan, currentPrice);
              const isUpgrade =
                !isCurrent && currentPrice > 0 && Number(plan.price_monthly_cents || 0) > currentPrice;
              const dueCents = Math.max(0, Number(plan.price_monthly_cents || 0) - currentPrice);
              const isRecommended = !!(plan.features?.recommended || plan.slug === "pro");
              return (
                <article
                  key={plan.slug}
                  className={`plans-card${isCurrent ? " is-current" : ""}${
                    isDowngrade ? " is-locked" : ""
                  }${isRecommended && !isCurrent && !isDowngrade ? " is-recommended" : ""}`}
                >
                  <div className="plans-card-head">
                    <div>
                      <div className="plans-card-title-row">
                        <h3>{plan.name}</h3>
                        {isCurrent ? <span className="plans-card-badge">Actual</span> : null}
                        {isRecommended && !isCurrent && !isDowngrade ? (
                          <span className="plans-card-badge plans-card-badge--recommended">
                            Recomendado
                          </span>
                        ) : null}
                      </div>
                      <p>{plan.description}</p>
                      {plan.features?.ideal_for ? (
                        <p className="plans-card-ideal">Ideal para: {plan.features.ideal_for}</p>
                      ) : null}
                      {isUpgrade ? (
                        <p className="plans-card-due">Hoy pagas ${(dueCents / 100).toFixed(0)} (diferencia)</p>
                      ) : null}
                      {isDowngrade ? (
                        <p className="plans-card-due plans-card-due--locked">
                          No puedes bajar de plan aquí. Usa cancelar suscripción si aplica.
                        </p>
                      ) : null}
                    </div>
                    <strong>{formatPlanPrice(plan.price_monthly_cents)}</strong>
                  </div>
                  <ul className="plans-card-features">
                    {planFeatureLines(plan).map((line) => (
                      <li key={line}>{line}</li>
                    ))}
                  </ul>
                  <button
                    type="button"
                    className="hp-btn primary plans-card-btn"
                    disabled={isCurrent || isDowngrade || busySlug === plan.slug}
                    onClick={() => selectPlan(plan.slug)}
                  >
                    {busySlug === plan.slug
                      ? "Procesando…"
                      : planActionLabel(plan, isCurrent, currentPrice)}
                  </button>
                </article>
              );
            })}
          </div>
        )}

        <p className="plans-modal-foot">
          Al mejorar un plan solo pagas la diferencia. Las bajadas no están posibles desde aquí;
          cancela la suscripción si necesitas volver a Gratis.
        </p>
        {showPortal && (
          <button
            type="button"
            className="hp-btn secondary plans-card-btn"
            style={{ marginTop: "0.75rem", width: "100%" }}
            disabled={portalBusy}
            onClick={openPortal}
          >
            {portalBusy ? "Abriendo Stripe…" : "Gestionar suscripción en Stripe"}
          </button>
        )}
      </div>
    </div>
  );
}
