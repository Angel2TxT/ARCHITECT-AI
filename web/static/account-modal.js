/**
 * Modal «Mi cuenta» reutilizable (workspace y panel admin).
 * Requiere: #accountModal, #accountBody, PlanoAuth.
 */
(function () {
  const ACCOUNT_RECEIPTS_PAGE_SIZE = 4;
  let accountReceiptsExpanded = false;
  let accountReceiptsCache = [];
  let wiredChrome = false;

  const opts = {
    toast: (msg) => {
      if (typeof window.showToast === "function") window.showToast(msg);
      else if (typeof window.PlanoDialog?.toast === "function") window.PlanoDialog.toast(msg);
      else console.info(msg);
    },
    onUserUpdated: () => {
      if (typeof window.updateUserUI === "function") window.updateUserUI();
    },
    onOpenPlans: () => {
      if (typeof window.openPlans === "function") window.openPlans();
      else window.location.href = "/legacy-app";
    },
  };

  function configure(next) {
    Object.assign(opts, next || {});
  }

  function $(sel) {
    return document.querySelector(sel);
  }

  function escapeHtml(text) {
    return String(text ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function isPlanUnlimited(sub) {
    if (!sub) return false;
    if (sub.is_unlimited) return true;
    return (sub.plan?.analyses_limit_monthly ?? 0) >= 9999;
  }

  function formatReceiptDate(iso) {
    if (!iso) return "—";
    try {
      return new Date(iso).toLocaleString("es-MX", { dateStyle: "medium", timeStyle: "short" });
    } catch {
      return iso;
    }
  }

  function roleLabel(user) {
    if (user?.role === "admin") return "Administrador";
    if (user?.role === "support") return "Soporte";
    return "Usuario";
  }

  async function uploadProfileAvatar(file) {
    if (!file) return;
    if (!/^image\/(jpeg|jpg|png|webp)$/i.test(file.type)) {
      throw new Error("Usa una imagen JPG, PNG o WEBP");
    }
    if (file.size > 3 * 1024 * 1024) {
      throw new Error("La imagen supera 3 MB");
    }
    const form = new FormData();
    form.append("file", file);
    const res = await PlanoAuth.apiFetch("/api/auth/me/avatar", {
      method: "POST",
      body: form,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(PlanoAuth.formatApiError(data, "No se pudo subir la foto"));
    if (data.user) localStorage.setItem("plano_ia_user", JSON.stringify(data.user));
    else await PlanoAuth.refreshMe();
    opts.onUserUpdated();
    return data;
  }

  async function removeProfileAvatar() {
    const res = await PlanoAuth.apiFetch("/api/auth/me/avatar", { method: "DELETE" });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(PlanoAuth.formatApiError(data, "No se pudo quitar la foto"));
    if (data.user) localStorage.setItem("plano_ia_user", JSON.stringify(data.user));
    else await PlanoAuth.refreshMe();
    opts.onUserUpdated();
    return data;
  }

  function renderUsageHistoryChart(history, sub) {
    if (!history?.length) {
      return `<section class="account-section">
        <div class="account-section-head">
          <h3>Uso mensual</h3>
          <p>Sin datos de uso todavía.</p>
        </div>
      </section>`;
    }
    const unlimited = isPlanUnlimited(sub);
    const maxVal = Math.max(
      1,
      ...history.map((h) => h.analyses_used || 0),
      ...(unlimited ? [1] : history.map((h) => Math.min(h.analyses_limit || 0, 20)))
    );
    const bars = history
      .map((h) => {
        const used = h.analyses_used || 0;
        const pct = Math.max(used > 0 ? 12 : 4, Math.round((used / maxVal) * 100));
        return `<div class="usage-history-col${h.is_current ? " is-current" : ""}" title="${h.period_key}: ${used} análisis">
          <div class="usage-history-bar-wrap"><div class="usage-history-bar" style="height:${pct}%"></div></div>
          <span class="usage-history-label">${escapeHtml(h.label)}</span>
          <span class="usage-history-value">${used}</span>
        </div>`;
      })
      .join("");
    return `<section class="account-section">
      <div class="account-section-head">
        <h3>Uso mensual</h3>
        <p>Análisis realizados por mes${unlimited ? " (plan ilimitado)" : ""}.</p>
      </div>
      <div class="usage-history-grid">${bars}</div>
    </section>`;
  }

  async function downloadBillingReceipt(receiptId, receiptNumber) {
    const res = await PlanoAuth.apiFetch(`/api/billing/receipts/${receiptId}/pdf?t=${Date.now()}`);
    if (!res.ok) {
      const data = await res.json().catch(() => ({}));
      throw new Error(data.detail || "No se pudo descargar el comprobante");
    }
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `ARCHITECT-${receiptNumber || receiptId}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  async function exportAllBillingReceipts() {
    const res = await PlanoAuth.apiFetch("/api/billing/receipts/export/zip");
    if (!res.ok) {
      const data = await res.json().catch(() => ({}));
      throw new Error(typeof data.detail === "string" ? data.detail : "No se pudo exportar");
    }
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "ARCHITECT-comprobantes.zip";
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  async function resendBillingReceipt(receiptId) {
    const res = await PlanoAuth.apiFetch(`/api/billing/receipts/${receiptId}/email`, {
      method: "POST",
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(typeof data.detail === "string" ? data.detail : "No se pudo enviar el correo");
    }
    return data;
  }

  function receiptCardHtml(r) {
    const emailBadge = r.email_sent_at
      ? '<span class="receipt-badge receipt-badge--sent">Enviado</span>'
      : '<span class="receipt-badge receipt-badge--pending">Sin correo</span>';
    return `
      <article class="receipt-card" data-receipt-id="${r.id}">
        <div class="receipt-card-top">
          <div class="receipt-card-main">
            <code class="receipt-card-folio">${escapeHtml(r.receipt_number)}</code>
            <p class="receipt-card-meta">
              <span>${escapeHtml(r.plan_name)}</span>
              <span class="receipt-card-dot" aria-hidden="true">·</span>
              <span>${escapeHtml(r.amount_label || "")}</span>
            </p>
            <p class="receipt-card-date">${escapeHtml(formatReceiptDate(r.created_at))}</p>
          </div>
          ${emailBadge}
        </div>
        <div class="receipt-card-actions">
          <button type="button" class="btn-link text-xs receipt-download-btn" data-id="${r.id}" data-number="${escapeHtml(r.receipt_number)}">PDF</button>
          <button type="button" class="btn-link text-xs receipt-email-btn" data-id="${r.id}">Reenviar</button>
        </div>
      </article>`;
  }

  function renderReceiptsSection(receipts, expanded = accountReceiptsExpanded) {
    accountReceiptsCache = Array.isArray(receipts) ? receipts : [];
    accountReceiptsExpanded = !!expanded;

    if (!accountReceiptsCache.length) {
      return `
        <section class="account-section account-receipts">
          <div class="account-section-head">
            <h3>Mis comprobantes</h3>
            <p>Aún no tienes compras registradas.</p>
          </div>
        </section>`;
    }

    const total = accountReceiptsCache.length;
    const visible = accountReceiptsExpanded
      ? accountReceiptsCache
      : accountReceiptsCache.slice(0, ACCOUNT_RECEIPTS_PAGE_SIZE);
    const hiddenCount = Math.max(0, total - visible.length);
    const cards = visible.map(receiptCardHtml).join("");
    const moreControls =
      total > ACCOUNT_RECEIPTS_PAGE_SIZE
        ? `<div class="receipts-more-row">
            <span class="receipts-more-meta">Mostrando ${visible.length} de ${total}</span>
            <button type="button" class="btn-link receipts-more-btn" id="btnToggleReceipts">
              ${accountReceiptsExpanded ? "Ver menos" : `Ver más (${hiddenCount})`}
            </button>
          </div>`
        : `<p class="receipts-more-meta">Mostrando ${total} comprobante${total === 1 ? "" : "s"}</p>`;

    return `
      <section class="account-section account-receipts">
        <div class="account-section-head account-section-head--row">
          <div>
            <h3>Mis comprobantes</h3>
            <p>Pasarela simulada · no es factura fiscal.</p>
          </div>
          <button type="button" class="btn-link text-xs receipt-export-all-btn">Exportar ZIP</button>
        </div>
        <div class="receipts-list">${cards}</div>
        ${moreControls}
      </section>`;
  }

  function bindReceiptActions(container) {
    container?.querySelectorAll(".receipt-export-all-btn").forEach((btn) => {
      btn.onclick = async () => {
        btn.disabled = true;
        try {
          await exportAllBillingReceipts();
          opts.toast("ZIP descargado");
        } catch (err) {
          opts.toast(err.message || "No se pudo exportar");
        } finally {
          btn.disabled = false;
        }
      };
    });
    container?.querySelectorAll(".receipt-download-btn").forEach((btn) => {
      btn.onclick = async () => {
        btn.disabled = true;
        try {
          await downloadBillingReceipt(btn.dataset.id, btn.dataset.number);
        } catch (err) {
          opts.toast(err.message || "Error al descargar");
        } finally {
          btn.disabled = false;
        }
      };
    });
    container?.querySelectorAll(".receipt-email-btn").forEach((btn) => {
      btn.onclick = async () => {
        btn.disabled = true;
        try {
          await resendBillingReceipt(btn.dataset.id);
          opts.toast("Comprobante enviado a tu correo");
          await open();
        } catch (err) {
          opts.toast(err.message || "No se pudo reenviar");
        } finally {
          btn.disabled = false;
        }
      };
    });
    const toggleBtn = container?.querySelector("#btnToggleReceipts");
    if (toggleBtn) {
      toggleBtn.onclick = () => {
        const section = container.querySelector(".account-receipts");
        if (!section) return;
        section.outerHTML = renderReceiptsSection(accountReceiptsCache, !accountReceiptsExpanded);
        bindReceiptActions(container);
      };
    }
  }

  function bindAccountSettingsForms(body, user) {
    const nameForm = body.querySelector("#accountNameForm");
    nameForm?.addEventListener("submit", async (e) => {
      e.preventDefault();
      const fullName = body.querySelector("#accountFullName")?.value?.trim() || "";
      const btn = nameForm.querySelector("button[type=submit]");
      if (btn) btn.disabled = true;
      try {
        const res = await PlanoAuth.apiFetch("/api/auth/me", {
          method: "PATCH",
          body: JSON.stringify({ full_name: fullName }),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(PlanoAuth.formatApiError(data, "No se pudo guardar"));
        localStorage.setItem("plano_ia_user", JSON.stringify(data.user));
        opts.onUserUpdated();
        opts.toast("Nombre actualizado");
        await open();
      } catch (err) {
        opts.toast(err.message || "Error al guardar");
      } finally {
        if (btn) btn.disabled = false;
      }
    });

    const passForm = body.querySelector("#accountPasswordForm");
    passForm?.addEventListener("submit", async (e) => {
      e.preventDefault();
      const current = body.querySelector("#accountCurrentPassword")?.value || null;
      const next = body.querySelector("#accountNewPassword")?.value || "";
      const next2 = body.querySelector("#accountNewPassword2")?.value || "";
      if (next !== next2) {
        opts.toast("Las contraseñas nuevas no coinciden");
        return;
      }
      const btn = passForm.querySelector("button[type=submit]");
      if (btn) btn.disabled = true;
      try {
        const res = await PlanoAuth.apiFetch("/api/auth/me/password", {
          method: "POST",
          body: JSON.stringify({
            current_password: user.has_password === false ? null : current,
            new_password: next,
          }),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(PlanoAuth.formatApiError(data, "No se pudo cambiar"));
        localStorage.setItem("plano_ia_user", JSON.stringify(data.user));
        opts.toast(user.has_password === false ? "Contraseña creada" : "Contraseña actualizada");
        passForm.reset();
        await open();
      } catch (err) {
        opts.toast(err.message || "Error al cambiar contraseña");
      } finally {
        if (btn) btn.disabled = false;
      }
    });

    const delForm = body.querySelector("#accountDeleteForm");
    delForm?.addEventListener("submit", async (e) => {
      e.preventDefault();
      if (!confirm("¿Eliminar tu cuenta de forma permanente? Esta acción no se puede deshacer.")) {
        return;
      }
      const btn = delForm.querySelector("button[type=submit]");
      if (btn) btn.disabled = true;
      try {
        const payload =
          user.has_password === false
            ? { confirm_email: body.querySelector("#accountDeleteEmail")?.value || "" }
            : { password: body.querySelector("#accountDeletePassword")?.value || "" };
        const res = await PlanoAuth.apiFetch("/api/auth/me", {
          method: "DELETE",
          body: JSON.stringify(payload),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(PlanoAuth.formatApiError(data, "No se pudo eliminar"));
        opts.toast("Cuenta eliminada");
        PlanoAuth.logout();
      } catch (err) {
        opts.toast(err.message || "Error al eliminar");
        if (btn) btn.disabled = false;
      }
    });
  }

  async function loadAccountBillingActions(body, sub) {
    const slot = body.querySelector("#accountBillingActions");
    if (!slot) return;
    const plan = sub?.plan || {};
    const price = plan.price_monthly_cents || 0;
    const isPaid = price > 0;

    let eligibility = null;
    let refunds = [];
    try {
      const [elRes, rfRes] = await Promise.all([
        PlanoAuth.apiFetch("/api/billing/refund-eligibility"),
        PlanoAuth.apiFetch("/api/billing/refunds"),
      ]);
      if (elRes.ok) eligibility = await elRes.json();
      if (rfRes.ok) {
        const d = await rfRes.json();
        refunds = d.refunds || [];
      }
    } catch {
      /* ignore */
    }

    const pending = refunds.find((r) => r.status === "pending");
    const reasons = (eligibility?.reasons || []).map((r) => `<li>${escapeHtml(r)}</li>`).join("");
    const canRequestRefund = !!eligibility?.eligible && !isPaid && !pending;
    const eligibleBadge = eligibility?.eligible
      ? isPaid
        ? '<span class="account-badge account-badge--ok">Cancela para pedir reembolso</span>'
        : '<span class="account-badge account-badge--ok">Candidato a reembolso</span>'
      : '<span class="account-badge">Sin elegibilidad actual</span>';

    slot.innerHTML = `
      <div class="account-section-head">
        <h3>Suscripción y reembolso</h3>
        <p>Si cancelas en los primeros ${eligibility?.window_days || 7} días y usaste poco el plan (≤30% de análisis y chat), puedes pedir reembolso.</p>
      </div>
      <div class="account-billing-panel">
        <div class="account-billing-row">
          <div>
            <strong>${escapeHtml(plan.name || "—")}</strong>
            <p class="account-hint">${isPaid ? "Plan de pago activo" : "Plan gratis / sin cobro activo"}</p>
          </div>
          ${isPaid ? '<button type="button" class="account-btn account-btn--ghost account-btn--sm" id="btnCancelSub">Cancelar suscripción</button>' : ""}
        </div>
        <div class="account-refund-box">
          <div class="account-refund-head">${eligibleBadge}</div>
          <ul class="account-refund-reasons">${reasons || "<li>Sin información de elegibilidad.</li>"}</ul>
          ${
            pending
              ? `<p class="account-hint">Solicitud #${pending.id} pendiente de revisión.</p>`
              : canRequestRefund
                ? `<form id="accountRefundForm" class="account-form account-form--inline">
                    <label>Motivo (opcional)
                      <input type="text" id="accountRefundReason" maxlength="500" placeholder="Ej. no lo usé como esperaba" />
                    </label>
                    <button type="submit" class="account-btn account-btn--solid account-btn--sm">Pedir reembolso</button>
                  </form>`
                : isPaid && eligibility?.eligible
                  ? `<p class="account-hint">Cancela la suscripción primero; después podrás enviar la solicitud.</p>`
                  : ""
          }
        </div>
      </div>
    `;

    const cancelBtn = slot.querySelector("#btnCancelSub");
    cancelBtn?.addEventListener("click", async () => {
      if (!confirm("¿Cancelar tu suscripción de pago y volver al plan Gratis?")) return;
      cancelBtn.disabled = true;
      try {
        const res = await PlanoAuth.apiFetch("/api/billing/cancel", { method: "POST" });
        const data = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(PlanoAuth.formatApiError(data, "No se pudo cancelar"));
        if (data.subscription) {
          localStorage.setItem("plano_ia_subscription", JSON.stringify(data.subscription));
        }
        const elig = data.refund_eligibility;
        if (elig?.eligible) {
          opts.toast("Suscripción cancelada. Eres candidato a reembolso.");
        } else {
          opts.toast(data.message || "Suscripción cancelada");
        }
        await open();
      } catch (err) {
        opts.toast(err.message || "Error al cancelar");
        cancelBtn.disabled = false;
      }
    });

    const refundForm = slot.querySelector("#accountRefundForm");
    refundForm?.addEventListener("submit", async (e) => {
      e.preventDefault();
      const btn = refundForm.querySelector("button[type=submit]");
      if (btn) btn.disabled = true;
      try {
        const res = await PlanoAuth.apiFetch("/api/billing/refunds", {
          method: "POST",
          body: JSON.stringify({
            reason: slot.querySelector("#accountRefundReason")?.value || "",
          }),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(PlanoAuth.formatApiError(data, "No se pudo solicitar"));
        opts.toast(data.message || "Solicitud enviada");
        await open();
      } catch (err) {
        opts.toast(err.message || "Error al solicitar reembolso");
        if (btn) btn.disabled = false;
      }
    });
  }

  function wireChrome() {
    if (wiredChrome) return;
    wiredChrome = true;
    const btnClose = $("#btnCloseAccount");
    if (btnClose) btnClose.onclick = () => $("#accountModal")?.close();
    const btnLogout = $("#btnAccountLogout");
    if (btnLogout) btnLogout.onclick = () => PlanoAuth.logout();
    const btnPlans = $("#btnAccountPlans");
    if (btnPlans) {
      btnPlans.onclick = () => {
        $("#accountModal")?.close();
        opts.onOpenPlans();
      };
    }
  }

  async function open() {
    wireChrome();
    const user = PlanoAuth.getUser();
    const body = $("#accountBody");
    const modal = $("#accountModal");
    if (!body || !modal || !user) return;

    let sub = PlanoAuth.getSubscription();
    try {
      const res = await PlanoAuth.apiFetch("/api/billing/subscription");
      if (res.ok) {
        const fresh = await res.json();
        localStorage.setItem("plano_ia_subscription", JSON.stringify(fresh));
        sub = fresh;
      }
    } catch {
      /* cache */
    }

    const plan = sub?.plan || {};
    const usage = sub?.usage || {};
    const used = usage.analyses_used ?? 0;
    const limit = plan.analyses_limit_monthly ?? 0;
    const unlimited = isPlanUnlimited(sub);
    const usageStr = unlimited
      ? `${used} análisis este mes (ilimitado)`
      : `${used} / ${limit}`;
    const storageGb = plan.storage_gb ?? plan.features?.storage_gb;
    const storageUsed = usage.storage_used_gb;
    const storageStr =
      storageGb == null
        ? "—"
        : storageUsed != null
          ? `${storageUsed} / ${storageGb} GB`
          : `${storageGb} GB`;
    const initials = (user.full_name || user.email || "U")
      .split(/\s+/)
      .map((w) => w[0])
      .join("")
      .slice(0, 2)
      .toUpperCase();

    body.innerHTML = `
      <section class="account-section account-profile">
        <div class="account-profile-row">
          <div class="account-avatar-wrap">
            <div class="account-avatar${user.avatar_url ? " has-photo" : ""}" id="accountAvatarPreview" ${user.avatar_url ? `style="background-image:url('${escapeHtml(user.avatar_url)}')"` : ""}>${user.avatar_url ? "" : escapeHtml(initials)}</div>
            <label class="account-avatar-edit" title="Cambiar foto">
              <span class="material-symbols-outlined">photo_camera</span>
              <input type="file" id="accountAvatarInput" accept="image/jpeg,image/png,image/webp" hidden />
            </label>
          </div>
          <div class="account-profile-copy">
            <strong class="account-profile-name">${escapeHtml(user.full_name || user.email)}</strong>
            <span class="account-profile-email">${escapeHtml(user.email)}</span>
            <div class="account-avatar-actions">
              <button type="button" class="btn-link text-xs" id="btnPickAvatar">Subir foto</button>
              ${user.avatar_url ? '<button type="button" class="btn-link text-xs account-avatar-remove" id="btnRemoveAvatar">Quitar</button>' : ""}
            </div>
          </div>
        </div>
        <div class="account-meta-grid">
          <div class="account-meta-item">
            <span class="account-meta-label">Rol</span>
            <span class="account-meta-value">${escapeHtml(roleLabel(user))}</span>
          </div>
          <div class="account-meta-item">
            <span class="account-meta-label">Plan</span>
            <span class="account-meta-value">${escapeHtml(plan.name || "—")}</span>
          </div>
          <div class="account-meta-item">
            <span class="account-meta-label">Uso</span>
            <span class="account-meta-value">${usageStr}</span>
          </div>
          <div class="account-meta-item">
            <span class="account-meta-label">Documentación</span>
            <span class="account-meta-value">${escapeHtml(String(storageStr))}</span>
          </div>
        </div>
        <p class="account-period">Periodo: ${escapeHtml(formatReceiptDate(sub?.period_start))} — ${escapeHtml(formatReceiptDate(sub?.period_end))}</p>
      </section>

      <section class="account-section account-settings">
        <div class="account-section-head">
          <h3>Datos de la cuenta</h3>
          <p>Actualiza tu nombre visible en la plataforma.</p>
        </div>
        <form id="accountNameForm" class="account-form">
          <label>Nombre
            <input type="text" id="accountFullName" maxlength="120" required value="${escapeHtml(user.full_name || "")}" />
          </label>
          <button type="submit" class="account-btn account-btn--solid account-btn--sm">Guardar nombre</button>
        </form>
      </section>

      <section class="account-section account-settings">
        <div class="account-section-head">
          <h3>${user.has_password === false ? "Definir contraseña" : "Cambiar contraseña"}</h3>
          <p>${user.has_password === false
            ? "Tu cuenta usa Google. Puedes crear una contraseña para entrar también con correo."
            : "Usa una contraseña de al menos 8 caracteres."}</p>
        </div>
        <form id="accountPasswordForm" class="account-form">
          ${user.has_password === false
            ? ""
            : `<label>Contraseña actual
                <input type="password" id="accountCurrentPassword" autocomplete="current-password" required />
              </label>`}
          <label>Nueva contraseña
            <input type="password" id="accountNewPassword" autocomplete="new-password" minlength="8" required />
          </label>
          <label>Confirmar nueva
            <input type="password" id="accountNewPassword2" autocomplete="new-password" minlength="8" required />
          </label>
          <button type="submit" class="account-btn account-btn--solid account-btn--sm">
            ${user.has_password === false ? "Crear contraseña" : "Actualizar contraseña"}
          </button>
        </form>
      </section>

      <section class="account-section account-billing-actions" id="accountBillingActions">
        <p class="account-loading">Cargando opciones de plan…</p>
      </section>

      <section class="account-section account-danger">
        <div class="account-section-head">
          <h3>Eliminar cuenta</h3>
          <p>Borra tu usuario, chats, análisis y proyectos. No se puede deshacer.</p>
        </div>
        <form id="accountDeleteForm" class="account-form">
          ${user.has_password === false
            ? `<label>Escribe tu correo para confirmar
                <input type="email" id="accountDeleteEmail" autocomplete="off" placeholder="${escapeHtml(user.email)}" required />
              </label>`
            : `<label>Contraseña
                <input type="password" id="accountDeletePassword" autocomplete="current-password" required />
              </label>`}
          <button type="submit" class="account-btn account-btn--danger account-btn--sm">Eliminar mi cuenta</button>
        </form>
      </section>

      <div class="account-usage-chart-slot">
        <p class="account-loading">Cargando uso mensual…</p>
      </div>
      <div class="account-receipts">
        <p class="account-loading">Cargando comprobantes…</p>
      </div>
    `;
    modal.showModal();

    bindAccountSettingsForms(body, user);
    loadAccountBillingActions(body, sub);

    const avatarInput = body.querySelector("#accountAvatarInput");
    const pickBtn = body.querySelector("#btnPickAvatar");
    const removeBtn = body.querySelector("#btnRemoveAvatar");
    pickBtn?.addEventListener("click", () => avatarInput?.click());
    avatarInput?.addEventListener("change", async () => {
      const file = avatarInput.files?.[0];
      avatarInput.value = "";
      if (!file) return;
      try {
        opts.toast("Subiendo foto…");
        await uploadProfileAvatar(file);
        opts.toast("Foto de perfil actualizada");
        await open();
      } catch (err) {
        opts.toast(err.message || "No se pudo subir la foto");
      }
    });
    removeBtn?.addEventListener("click", async () => {
      try {
        await removeProfileAvatar();
        opts.toast("Foto eliminada");
        await open();
      } catch (err) {
        opts.toast(err.message || "No se pudo quitar la foto");
      }
    });

    try {
      const [receiptsRes, historyRes] = await Promise.all([
        PlanoAuth.apiFetch("/api/billing/receipts"),
        PlanoAuth.apiFetch("/api/billing/usage-history?months=6"),
      ]);
      const receiptsData = await receiptsRes.json().catch(() => ({}));
      const historyData = await historyRes.json().catch(() => ({}));
      const receipts = receiptsRes.ok ? receiptsData.receipts || [] : [];
      const history = historyRes.ok ? historyData.history || [] : [];
      accountReceiptsExpanded = false;

      const chartSlot = body.querySelector(".account-usage-chart-slot");
      if (chartSlot) chartSlot.outerHTML = renderUsageHistoryChart(history, sub);

      const receiptsEl = body.querySelector(".account-receipts");
      if (receiptsEl) {
        receiptsEl.outerHTML = renderReceiptsSection(receipts, false);
        bindReceiptActions(body);
      }
    } catch {
      const receiptsEl = body.querySelector(".account-receipts");
      if (receiptsEl) {
        receiptsEl.innerHTML =
          '<p class="account-loading">No se pudo cargar el historial de compras.</p>';
      }
    }
  }

  function close() {
    $("#accountModal")?.close();
  }

  window.ArchitectAccount = {
    configure,
    open,
    close,
  };
})();
