(function () {
  const TOKEN_KEY = "plano_ia_token";
  const SUB_KEY = "plano_ia_subscription";
  const params = new URLSearchParams(window.location.search);
  const sessionId = params.get("session_id");
  const returnUrl = params.get("return_url") || "/legacy-app";
  const titleEl = document.getElementById("successTitle");
  const msgEl = document.getElementById("successMsg");
  const linkEl = document.getElementById("successLink");

  async function run() {
    const token = localStorage.getItem(TOKEN_KEY);
    if (!token) {
      titleEl.textContent = "Inicia sesión";
      msgEl.textContent = "Necesitamos tu sesión para confirmar el pago.";
      linkEl.href = `/login?next=${encodeURIComponent(window.location.pathname + window.location.search)}`;
      linkEl.textContent = "Ingresar";
      linkEl.classList.remove("hidden");
      return;
    }
    if (!sessionId) {
      titleEl.textContent = "Sesión no encontrada";
      msgEl.textContent = "No recibimos el identificador de pago de Stripe.";
      linkEl.classList.remove("hidden");
      return;
    }

    try {
      const res = await fetch(
        `/api/billing/checkout/stripe/complete?session_id=${encodeURIComponent(sessionId)}`,
        { headers: { Authorization: `Bearer ${token}` } }
      );
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.detail || "No se pudo confirmar el pago");

      if (data.subscription) {
        localStorage.setItem(SUB_KEY, JSON.stringify(data.subscription));
      }
      titleEl.textContent = "¡Plan activado!";
      msgEl.textContent = `Tu plan ${data.subscription?.plan?.name || ""} ya está disponible en el workspace.`;
      linkEl.href = returnUrl;
      linkEl.textContent = "Ir al workspace";
      linkEl.classList.remove("hidden");
      setTimeout(() => {
        window.location.href = `${returnUrl}${returnUrl.includes("?") ? "&" : "?"}plan_activated=1`;
      }, 1200);
    } catch (err) {
      titleEl.textContent = "No se pudo confirmar";
      msgEl.textContent = err.message || "Intenta de nuevo desde la app.";
      linkEl.classList.remove("hidden");
    }
  }

  run();
})();
