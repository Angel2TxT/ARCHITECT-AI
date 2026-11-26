import React, { useEffect, useRef, useState } from "react";
import { ArrowLeft, Clock, Eye, EyeOff, Mail, RefreshCw, ShieldCheck } from "lucide-react";

const DIGITS_COUNT = 6;

function formatCountdown(seconds) {
  const safe = Math.max(0, Number(seconds) || 0);
  const mins = Math.floor(safe / 60);
  const secs = safe % 60;
  return `${String(mins).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
}

export default function VerifyEmailView({
  initialEmail,
  onVerified,
  onEmailUpdated,
  onBackToLogin,
  formatApiError,
  ThemeToggleComponent,
}) {
  const [email, setEmail] = useState(() => (initialEmail || "").trim().toLowerCase());
  const [digits, setDigits] = useState(() => Array(DIGITS_COUNT).fill(""));
  const [expiresIn, setExpiresIn] = useState(0);
  const [resendIn, setResendIn] = useState(0);
  const [attemptsRemaining, setAttemptsRemaining] = useState(5);
  const [statusLoading, setStatusLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [resending, setResending] = useState(false);
  const [changingEmail, setChangingEmail] = useState(false);
  const [showChangeForm, setShowChangeForm] = useState(false);
  const [newEmail, setNewEmail] = useState("");
  const [changePassword, setChangePassword] = useState("");
  const [showChangePassword, setShowChangePassword] = useState(false);
  const [error, setError] = useState("");
  const [successMsg, setSuccessMsg] = useState("");
  const inputRefs = useRef([]);

  async function syncStatusFromBackend(targetEmail) {
    const clean = (targetEmail || "").trim().toLowerCase();
    if (!clean) {
      setStatusLoading(false);
      onBackToLogin();
      return;
    }
    setStatusLoading(true);
    try {
      const res = await fetch(
        `/api/auth/verification-status?email=${encodeURIComponent(clean)}`
      );
      const data = await res.json().catch(() => ({}));
      if (!res.ok || !data.requires_verification) {
        onBackToLogin();
        return;
      }
      setExpiresIn(Math.max(0, Number(data.expires_in_seconds) || 0));
      setResendIn(Math.max(0, Number(data.resend_available_in_seconds) || 0));
      setAttemptsRemaining(
        typeof data.attempts_remaining === "number" ? data.attempts_remaining : 5
      );
    } catch {
      setError("No se pudo consultar el estado de verificación.");
    } finally {
      setStatusLoading(false);
    }
  }

  useEffect(() => {
    syncStatusFromBackend(email);
  }, [email]);

  useEffect(() => {
    if (expiresIn <= 0 && resendIn <= 0) return undefined;
    const timer = window.setInterval(() => {
      setExpiresIn((prev) => (prev > 0 ? prev - 1 : 0));
      setResendIn((prev) => (prev > 0 ? prev - 1 : 0));
    }, 1000);
    return () => window.clearInterval(timer);
  }, [expiresIn > 0, resendIn > 0]);

  useEffect(() => {
    if (!statusLoading && inputRefs.current[0]) {
      inputRefs.current[0].focus();
    }
  }, [statusLoading]);

  function handleDigitChange(index, rawValue) {
    const clean = rawValue.replace(/\D/g, "");
    setError("");
    if (!clean) {
      setDigits((prev) => {
        const next = [...prev];
        next[index] = "";
        return next;
      });
      return;
    }

    if (clean.length > 1) {
      const pasted = clean.slice(0, DIGITS_COUNT).split("");
      setDigits((prev) => {
        const next = [...prev];
        for (let i = 0; i < DIGITS_COUNT; i++) {
          next[i] = pasted[i] || "";
        }
        return next;
      });
      const focusIdx = Math.min(pasted.length - 1, DIGITS_COUNT - 1);
      inputRefs.current[focusIdx]?.focus();
      return;
    }

    setDigits((prev) => {
      const next = [...prev];
      next[index] = clean;
      return next;
    });
    if (index < DIGITS_COUNT - 1) {
      inputRefs.current[index + 1]?.focus();
    }
  }

  function handleDigitKeyDown(index, event) {
    if (event.key === "Backspace" && !digits[index] && index > 0) {
      event.preventDefault();
      setDigits((prev) => {
        const next = [...prev];
        next[index - 1] = "";
        return next;
      });
      inputRefs.current[index - 1]?.focus();
    } else if (event.key === "ArrowLeft" && index > 0) {
      event.preventDefault();
      inputRefs.current[index - 1]?.focus();
    } else if (event.key === "ArrowRight" && index < DIGITS_COUNT - 1) {
      event.preventDefault();
      inputRefs.current[index + 1]?.focus();
    }
  }

  function handlePaste(event) {
    const text = event.clipboardData?.getData("text") || "";
    const clean = text.replace(/\D/g, "").slice(0, DIGITS_COUNT);
    if (!clean) return;
    event.preventDefault();
    setError("");
    const next = Array(DIGITS_COUNT).fill("");
    for (let i = 0; i < clean.length; i++) {
      next[i] = clean[i];
    }
    setDigits(next);
    const focusIdx = Math.min(clean.length - 1, DIGITS_COUNT - 1);
    inputRefs.current[focusIdx]?.focus();
  }

  async function handleVerify(event) {
    event.preventDefault();
    const code = digits.join("");
    if (!/^\d{6}$/.test(code)) {
      setError("Ingresa el código numérico completo de 6 dígitos.");
      return;
    }

    setBusy(true);
    setError("");
    setSuccessMsg("");
    try {
      const res = await fetch("/api/auth/verify-email", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, code }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(formatApiError(data, "No se pudo verificar el código."));
        await syncStatusFromBackend(email);
        setBusy(false);
        return;
      }
      await onVerified(data);
    } catch {
      setError("No se pudo conectar con el servidor.");
      setBusy(false);
    }
  }

  async function handleResend() {
    if (resendIn > 0 || resending) return;
    setResending(true);
    setError("");
    setSuccessMsg("");
    try {
      const res = await fetch("/api/auth/resend-verification", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(formatApiError(data, "No se pudo reenviar el código."));
        if (typeof data?.detail?.retry_after_seconds === "number") {
          setResendIn(data.detail.retry_after_seconds);
        }
        return;
      }
      setDigits(Array(DIGITS_COUNT).fill(""));
      setExpiresIn(Number(data.expires_in_seconds) || 300);
      setResendIn(Number(data.cooldown_seconds) || 60);
      setAttemptsRemaining(5);
      setSuccessMsg(`Enviamos un nuevo código de verificación a ${email}.`);
      inputRefs.current[0]?.focus();
    } catch {
      setError("No se pudo conectar con el servidor.");
    } finally {
      setResending(false);
    }
  }

  async function handleChangeEmail(event) {
    event.preventDefault();
    const cleanNew = newEmail.trim().toLowerCase();
    if (!cleanNew || /[<>/\s]/.test(cleanNew)) {
      setError("Ingresa un correo electrónico válido.");
      return;
    }
    if (!changePassword) {
      setError("Ingresa tu contraseña para confirmar el cambio de correo.");
      return;
    }

    setChangingEmail(true);
    setError("");
    setSuccessMsg("");
    try {
      const res = await fetch("/api/auth/update-unverified-email", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          current_email: email,
          new_email: cleanNew,
          password: changePassword,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(formatApiError(data, "No se pudo actualizar el correo."));
        return;
      }
      const updated = (data.email || cleanNew).trim().toLowerCase();
      setEmail(updated);
      onEmailUpdated(updated);
      setDigits(Array(DIGITS_COUNT).fill(""));
      setExpiresIn(Number(data.expires_in_seconds) || 300);
      setResendIn(Number(data.cooldown_seconds) || 60);
      setAttemptsRemaining(5);
      setShowChangeForm(false);
      setNewEmail("");
      setChangePassword("");
      setSuccessMsg(`Correo actualizado. Enviamos un nuevo código a ${updated}.`);
    } catch {
      setError("No se pudo conectar con el servidor.");
    } finally {
      setChangingEmail(false);
    }
  }

  const codeComplete = digits.every((d) => /^\d$/.test(d));

  return (
    <main className="auth-view auth-view--verify">
      <div className="auth-bg-motion" aria-hidden="true">
        <span className="auth-orbit auth-orbit-one" />
        <span className="auth-orbit auth-orbit-two" />
        <span className="auth-grid-line auth-grid-line-one" />
        <span className="auth-grid-line auth-grid-line-two" />
      </div>

      <button className="back-link" type="button" onClick={onBackToLogin}>
        <ArrowLeft size={16} />
        Volver a iniciar sesión
      </button>

      {ThemeToggleComponent && (
        <div className="auth-theme-toggle">
          <ThemeToggleComponent />
        </div>
      )}

      <section className="auth-panel verify-panel" aria-live="polite">
        <div className="verify-icon-wrap" aria-hidden="true">
          <Mail size={26} />
        </div>

        <div className="auth-heading verify-heading">
          <span>ARCHITECT Studio</span>
          <h1>Verifica tu correo electrónico</h1>
          <p>
            Hemos enviado un código de 6 dígitos a{" "}
            <strong className="verify-email-chip" data-testid="verify-email-label">
              {email}
            </strong>
          </p>
        </div>

        <div className="verify-meta-bar">
          <span className={`verify-timer ${expiresIn === 0 && !statusLoading ? "is-expired" : ""}`}>
            <Clock size={14} />
            {statusLoading
              ? "Consultando vigencia…"
              : expiresIn > 0
              ? `Expira en ${formatCountdown(expiresIn)}`
              : "Código expirado"}
          </span>
          <span className="verify-attempts" data-testid="verify-attempts-label">
            Intentos restantes: {attemptsRemaining}
          </span>
        </div>

        <form onSubmit={handleVerify} className="auth-form verify-form">
          <div className="otp-grid" onPaste={handlePaste} role="group" aria-label="Código de 6 dígitos">
            {digits.map((digit, index) => (
              <input
                key={index}
                ref={(el) => {
                  inputRefs.current[index] = el;
                }}
                type="text"
                inputMode="numeric"
                autoComplete={index === 0 ? "one-time-code" : "off"}
                maxLength={6}
                value={digit}
                aria-label={`Dígito ${index + 1}`}
                data-testid={`otp-input-${index}`}
                className="otp-box"
                onChange={(e) => handleDigitChange(index, e.target.value)}
                onKeyDown={(e) => handleDigitKeyDown(index, e)}
                disabled={busy || statusLoading}
              />
            ))}
          </div>

          {error && (
            <p className="form-error" role="alert" data-testid="verify-error">
              {error}
            </p>
          )}
          {successMsg && (
            <p className="form-success" role="status" data-testid="verify-success">
              {successMsg}
            </p>
          )}

          <button
            className="auth-submit"
            type="submit"
            disabled={busy || statusLoading || !codeComplete}
            data-testid="verify-submit-btn"
          >
            {busy ? "Verificando..." : "Verificar correo"}
            <ShieldCheck size={18} />
          </button>
        </form>

        <div className="verify-actions">
          <button
            type="button"
            className="verify-secondary-btn"
            onClick={handleResend}
            disabled={resendIn > 0 || resending || statusLoading}
            data-testid="verify-resend-btn"
          >
            <RefreshCw size={15} className={resending ? "spin" : ""} />
            {resending
              ? "Reenviando..."
              : resendIn > 0
              ? `Reenviar código (${resendIn}s)`
              : "Reenviar código"}
          </button>

          <button
            type="button"
            className="verify-link-btn"
            onClick={() => {
              setShowChangeForm((prev) => !prev);
              setError("");
              setSuccessMsg("");
              setNewEmail(email);
            }}
            data-testid="verify-change-email-toggle"
          >
            Cambiar correo electrónico
          </button>
        </div>

        {showChangeForm && (
          <form onSubmit={handleChangeEmail} className="verify-change-form" data-testid="verify-change-email-form">
            <label>
              Nuevo correo electrónico
              <input
                type="email"
                required
                value={newEmail}
                onChange={(e) => setNewEmail(e.target.value)}
                placeholder="nuevo@correo.com"
                data-testid="verify-new-email-input"
              />
            </label>
            <label>
              Contraseña de tu cuenta
              <div className="password-field">
                <input
                  type={showChangePassword ? "text" : "password"}
                  required
                  value={changePassword}
                  onChange={(e) => setChangePassword(e.target.value)}
                  placeholder="Tu contraseña"
                  data-testid="verify-change-password-input"
                />
                <button
                  type="button"
                  onClick={() => setShowChangePassword((v) => !v)}
                  aria-label="Mostrar contraseña"
                >
                  {showChangePassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
            </label>
            <div className="verify-change-actions">
              <button
                type="button"
                className="verify-link-btn"
                onClick={() => setShowChangeForm(false)}
                disabled={changingEmail}
              >
                Cancelar
              </button>
              <button
                type="submit"
                className="verify-save-email-btn"
                disabled={changingEmail}
                data-testid="verify-save-email-btn"
              >
                {changingEmail ? "Guardando..." : "Guardar y reenviar"}
              </button>
            </div>
          </form>
        )}
      </section>
    </main>
  );
}

