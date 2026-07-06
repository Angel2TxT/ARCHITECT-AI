(function () {
  const TOKEN_KEY = "plano_ia_token";
  const SUB_KEY = "plano_ia_subscription";
  const RECEIPT_ALERT_KEY = "pending_receipt_alert";
  const params = new URLSearchParams(window.location.search);
  const sessionToken = params.get("token");
  const canceled = params.get("canceled") === "1";
  const returnUrl = params.get("return_url") || "/legacy-app";

  const loadingEl = document.getElementById("checkoutLoading");
  const formEl = document.getElementById("checkoutForm");
  const successEl = document.getElementById("checkoutSuccess");
  const errorOnlyEl = document.getElementById("checkoutErrorOnly");
  const errorEl = document.getElementById("checkoutError");
  const fatalMsgEl = document.getElementById("checkoutFatalMsg");
  const payBtn = document.getElementById("checkoutPayBtn");
  const cancelBtn = document.getElementById("checkoutCancelBtn");
  const downloadBtn = document.getElementById("checkoutDownloadBtn");
  const continueBtn = document.getElementById("checkoutContinueBtn");

  let pendingReturnUrl = returnUrl;
  let pendingReceipt = null;

  function showFatal(message) {
    loadingEl.classList.add("hidden");
    formEl.classList.add("hidden");
    successEl.classList.add("hidden");
    errorOnlyEl.classList.remove("hidden");
    fatalMsgEl.textContent = message;
  }

  function formatPrice(cents) {
    if (!cents) return "Gratis";
    return `$${(cents / 100).toFixed(0)}`;
  }

  function maskEmail(email) {
    if (!email || !email.includes("@")) return email || "";
    const [user, domain] = email.split("@");
    const masked = user.length <= 2 ? `${user[0]}*` : `${user.slice(0, 2)}***`;
    return `${masked}@${domain}`;
  }

  function getToken() {
    return localStorage.getItem(TOKEN_KEY);
  }

  async function downloadReceipt(receipt) {
    if (!receipt?.id) return;
    const token = getToken();
    const res = await fetch(`/api/billing/receipts/${receipt.id}/pdf?t=${Date.now()}`, {
      headers: token ? { Authorization: `Bearer ${token}` } : {},
    });
    if (!res.ok) throw new Error("No se pudo descargar el comprobante");
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `ARCHITECT-${receipt.receipt_number || receipt.id}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  function goToApp() {
    const target = pendingReturnUrl || returnUrl;
    const url = new URL(target, window.location.origin);
    url.searchParams.set("plan_activated", "1");
    if (pendingReceipt?.id) url.searchParams.set("receipt_id", String(pendingReceipt.id));
    window.location.href = url.pathname + url.search;
  }

  function sleep(ms) {
    return new Promise((resolve) => window.setTimeout(resolve, ms));
  }

  function formatApiError(detail, fallback) {
    if (typeof detail === "string" && detail.trim()) return detail;
    if (Array.isArray(detail)) {
      const msg = detail
        .map((item) => item?.msg || item?.message)
        .filter(Boolean)
        .join(". ");
      if (msg) return msg;
    }
    if (detail && typeof detail === "object" && typeof detail.message === "string") {
      return detail.message;
    }
    return fallback;
  }

  const processingEl = document.getElementById("checkoutProcessing");
  const processingStepEl = document.getElementById("checkoutProcessingStep");
  const confettiCanvas = document.getElementById("checkoutConfettiCanvas");

  function showProcessing() {
    processingEl?.classList.remove("hidden");
    if (processingStepEl) processingStepEl.textContent = "Verificando tarjeta";
  }

  function hideProcessing() {
    processingEl?.classList.add("hidden");
  }

  function runProcessingSteps() {
    const steps = [
      { at: 550, text: "Verificando tarjeta" },
      { at: 1100, text: "Autorizando pago simulado" },
      { at: 1650, text: "Activando tu plan" },
    ];
    const timers = steps.map(({ at, text }) =>
      window.setTimeout(() => {
        if (processingStepEl) processingStepEl.textContent = text;
      }, at)
    );
    return () => timers.forEach((id) => window.clearTimeout(id));
  }

  function playConfetti() {
    if (!confettiCanvas) return;
    const ctx = confettiCanvas.getContext("2d");
    if (!ctx) return;

    const resize = () => {
      confettiCanvas.width = window.innerWidth;
      confettiCanvas.height = window.innerHeight;
    };
    resize();

    const colors = ["#86efac", "#fde68a", "#ffffff", "#93c5fd", "#f9a8d4", "#fcd34d"];
    const particles = [];
    const count = 140;
    const cx = confettiCanvas.width / 2;
    const cy = confettiCanvas.height * 0.42;

    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 4 + Math.random() * 9;
      particles.push({
        x: cx,
        y: cy,
        w: 6 + Math.random() * 6,
        h: 4 + Math.random() * 5,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed - 3,
        rot: Math.random() * Math.PI,
        vr: (Math.random() - 0.5) * 0.25,
        color: colors[Math.floor(Math.random() * colors.length)],
        life: 1,
        decay: 0.008 + Math.random() * 0.012,
      });
    }

    let frame = 0;
    const maxFrames = 110;

    function tick() {
      ctx.clearRect(0, 0, confettiCanvas.width, confettiCanvas.height);
      let alive = 0;
      for (const p of particles) {
        if (p.life <= 0) continue;
        alive++;
        p.x += p.vx;
        p.y += p.vy;
        p.vy += 0.18;
        p.vx *= 0.99;
        p.rot += p.vr;
        p.life -= p.decay;

        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(p.rot);
        ctx.globalAlpha = Math.max(p.life, 0);
        ctx.fillStyle = p.color;
        ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
        ctx.restore();
      }

      frame++;
      if (frame < maxFrames && alive > 0) {
        requestAnimationFrame(tick);
      } else {
        ctx.clearRect(0, 0, confettiCanvas.width, confettiCanvas.height);
      }
    }

    tick();
    window.setTimeout(resize, 0);
  }

  function showSuccess(data) {
    hideProcessing();
    formEl.classList.add("hidden");
    loadingEl.classList.add("hidden");
    successEl.classList.remove("hidden");
    successEl.classList.remove("is-revealed");
    void successEl.offsetWidth;
    successEl.classList.add("is-revealed");
    playConfetti();

    pendingReturnUrl = data.return_url || returnUrl;
    pendingReceipt = data.receipt || null;

    const planName = data.subscription?.plan?.name || "Plan";
    document.getElementById("checkoutSuccessPlan").textContent = `Plan ${planName} activado.`;

    const metaEl = document.getElementById("checkoutReceiptMeta");
    const emailWarn = document.getElementById("checkoutEmailWarn");
    if (pendingReceipt) {
      const emailNote =
        pendingReceipt.email_status === "sent"
          ? "Te enviamos el comprobante a tu correo."
          : pendingReceipt.email_status === "not_configured"
            ? "Correo no configurado: descarga el PDF o revísalo en Mi cuenta."
            : "No pudimos enviar el correo: descarga el PDF aquí.";
      metaEl.textContent = `Folio ${pendingReceipt.receipt_number}. ${emailNote}`;
      downloadBtn.classList.remove("hidden");
      downloadBtn.onclick = async () => {
        downloadBtn.disabled = true;
        try {
          await downloadReceipt(pendingReceipt);
        } catch (err) {
          alert(err.message || "Error al descargar");
        } finally {
          downloadBtn.disabled = false;
        }
      };
      if (emailWarn && pendingReceipt.email_status === "failed") {
        emailWarn.textContent =
          "No se pudo enviar el comprobante por correo. Descárgalo ahora; también lo verás en Mi cuenta.";
        emailWarn.classList.remove("hidden");
        try {
          sessionStorage.setItem(RECEIPT_ALERT_KEY, JSON.stringify(pendingReceipt));
        } catch {
          /* ignore */
        }
      }
    } else {
      metaEl.textContent = "Puedes ver tu plan en Mi cuenta.";
      downloadBtn.classList.add("hidden");
      emailWarn?.classList.add("hidden");
    }

    continueBtn.onclick = goToApp;
  }

  async function loadSession() {
    if (canceled) {
      showFatal("Cancelaste el pago. Puedes elegir otro plan cuando quieras.");
      return;
    }
    if (!sessionToken) {
      showFatal("Falta el token de la sesión de pago.");
      return;
    }
    const token = getToken();
    if (!token) {
      const next = encodeURIComponent(`/checkout?token=${sessionToken}`);
      window.location.href = `/login?next=${next}`;
      return;
    }

    try {
      const res = await fetch(`/api/billing/checkout/session?token=${encodeURIComponent(sessionToken)}`);
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.detail || "Sesión inválida");

      document.getElementById("planName").textContent = data.plan?.name || "Plan";
      document.getElementById("planEmail").textContent = maskEmail(data.user_email);
      document.getElementById("planPrice").textContent = formatPrice(data.plan?.price_monthly_cents);
      document.getElementById("checkoutTitle").textContent =
        data.mode === "stripe" ? "Redirigiendo a Stripe…" : "Confirmar suscripción";

      loadingEl.classList.add("hidden");
      formEl.classList.remove("hidden");

      cancelBtn.onclick = () => {
        window.location.href = data.return_url || returnUrl;
      };

      if (data.mode === "stripe") {
        payBtn.disabled = true;
        payBtn.textContent = "Usa el enlace de Stripe desde la app";
      }
    } catch (err) {
      showFatal(err.message || "No se pudo cargar la sesión");
    }
  }

  function showFormError(message) {
    errorEl.textContent = message;
    errorEl.classList.remove("hidden");
  }

  function setupCardInputs() {
    const cardNumber = document.getElementById("cardNumber");
    const cardExpiry = document.getElementById("cardExpiry");
    const cardCvc = document.getElementById("cardCvc");

    cardNumber?.addEventListener("input", () => {
      const digits = cardNumber.value.replace(/\D/g, "").slice(0, 16);
      cardNumber.value = digits.replace(/(\d{4})(?=\d)/g, "$1 ").trim();
    });

    cardExpiry?.addEventListener("input", () => {
      const digits = cardExpiry.value.replace(/\D/g, "").slice(0, 4);
      if (digits.length <= 2) {
        cardExpiry.value = digits;
      } else {
        cardExpiry.value = `${digits.slice(0, 2)}/${digits.slice(2)}`;
      }
    });

    cardCvc?.addEventListener("input", () => {
      cardCvc.value = cardCvc.value.replace(/\D/g, "").slice(0, 4);
    });
  }

  function validateCardFields() {
    const cardNumber = document.getElementById("cardNumber");
    const cardExpiry = document.getElementById("cardExpiry");
    const cardCvc = document.getElementById("cardCvc");
    const digits = (cardNumber?.value || "").replace(/\D/g, "");
    if (digits.length !== 16) {
      showFormError("El número de tarjeta debe tener 16 dígitos.");
      cardNumber?.focus();
      return false;
    }
    const expiry = (cardExpiry?.value || "").trim();
    if (!/^(0[1-9]|1[0-2])\/\d{2}$/.test(expiry)) {
      showFormError("Vencimiento inválido. Usa formato MM/AA (ej. 12/28).");
      cardExpiry?.focus();
      return false;
    }
    const cvc = (cardCvc?.value || "").replace(/\D/g, "");
    if (cvc.length < 3 || cvc.length > 4) {
      showFormError("El CVC debe tener 3 o 4 dígitos.");
      cardCvc?.focus();
      return false;
    }
    return true;
  }

  setupCardInputs();

  document.getElementById("checkoutForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    errorEl.classList.add("hidden");
    if (!validateCardFields()) return;
    const token = getToken();
    if (!token || !sessionToken) {
      showFormError("Debes iniciar sesión para completar el pago.");
      return;
    }

    payBtn.disabled = true;
    payBtn.textContent = "Procesando…";
    showProcessing();
    const stopSteps = runProcessingSteps();

    try {
      const [res] = await Promise.all([
        fetch("/api/billing/checkout/complete", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({ session_token: sessionToken }),
        }),
        sleep(1800),
      ]);
      stopSteps();
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        hideProcessing();
        throw new Error(formatApiError(data.detail, "No se pudo completar el pago demo"));
      }
      if (data.subscription) {
        localStorage.setItem(SUB_KEY, JSON.stringify(data.subscription));
      }
      showSuccess(data);
    } catch (err) {
      stopSteps();
      hideProcessing();
      showFormError(err.message || "Error al procesar el pago");
      payBtn.disabled = false;
      payBtn.innerHTML =
        '<span class="material-symbols-outlined" style="font-size:1.1rem">lock</span> Pagar y activar plan';
    }
  });

  loadSession();
})();
