/**
 * Diálogos modales y toasts con el estilo ARCHITECT.
 */
(function () {
  const ICONS = {
    info: "info",
    danger: "warning",
    question: "help",
  };

  let dialogEl = null;
  let queue = Promise.resolve();

  function ensureDialog() {
    if (dialogEl) return dialogEl;
    dialogEl = document.createElement("dialog");
    dialogEl.className = "arch-dialog";
    dialogEl.setAttribute("aria-labelledby", "archDialogTitle");
    dialogEl.innerHTML = `
      <div class="arch-dialog-box glass-panel">
        <div class="arch-dialog-icon" id="archDialogIcon" aria-hidden="true">
          <span class="material-symbols-outlined"></span>
        </div>
        <h2 class="arch-dialog-title" id="archDialogTitle"></h2>
        <p class="arch-dialog-message" id="archDialogMessage"></p>
        <div class="arch-dialog-field hidden" id="archDialogField">
          <textarea id="archDialogInput" class="arch-dialog-input" rows="3"></textarea>
          <p class="arch-dialog-hint hidden" id="archDialogHint"></p>
        </div>
        <div class="arch-dialog-actions" id="archDialogActions"></div>
      </div>`;
    document.body.appendChild(dialogEl);
    return dialogEl;
  }

  function enqueue(task) {
    const run = queue.then(task);
    queue = run.catch(() => {});
    return run;
  }

  function setIcon(kind) {
    const wrap = dialogEl.querySelector("#archDialogIcon");
    const icon = wrap?.querySelector(".material-symbols-outlined");
    if (!wrap || !icon) return;
    wrap.className = `arch-dialog-icon arch-dialog-icon--${kind || "info"}`;
    icon.textContent = ICONS[kind] || ICONS.info;
  }

  function waitClose() {
    return new Promise((resolve) => {
      const onClose = () => {
        dialogEl.removeEventListener("close", onClose);
        resolve(dialogEl.returnValue);
      };
      dialogEl.addEventListener("close", onClose);
      dialogEl.showModal();
    });
  }

  function bindButton(label, value, className) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = className;
    btn.textContent = label;
    btn.addEventListener("click", () => {
      dialogEl.returnValue = value;
      dialogEl.close();
    });
    return btn;
  }

  function alert(message, options = {}) {
    return enqueue(async () => {
      ensureDialog();
      const title = options.title || "ARCHITECT";
      const confirmLabel = options.confirmLabel || "Entendido";

      setIcon(options.variant === "danger" ? "danger" : "info");
      dialogEl.querySelector("#archDialogTitle").textContent = title;
      dialogEl.querySelector("#archDialogMessage").textContent = message || "";
      dialogEl.querySelector("#archDialogField").classList.add("hidden");

      const actions = dialogEl.querySelector("#archDialogActions");
      actions.innerHTML = "";
      actions.appendChild(bindButton(confirmLabel, "ok", "btn-primary arch-dialog-btn"));

      await waitClose();
      return true;
    });
  }

  function confirm(message, options = {}) {
    return enqueue(async () => {
      ensureDialog();
      const title = options.title || "¿Confirmar acción?";
      const confirmLabel = options.confirmLabel || "Confirmar";
      const cancelLabel = options.cancelLabel || "Cancelar";
      const variant = options.variant || "question";

      setIcon(variant === "danger" ? "danger" : "question");
      dialogEl.querySelector("#archDialogTitle").textContent = title;
      dialogEl.querySelector("#archDialogMessage").textContent = message || "";
      dialogEl.querySelector("#archDialogField").classList.add("hidden");

      const actions = dialogEl.querySelector("#archDialogActions");
      actions.innerHTML = "";
      actions.appendChild(bindButton(cancelLabel, "", "btn-secondary arch-dialog-btn"));
      actions.appendChild(
        bindButton(
          confirmLabel,
          "ok",
          variant === "danger"
            ? "btn-primary arch-dialog-btn arch-dialog-btn--danger"
            : "btn-primary arch-dialog-btn"
        )
      );

      const result = await waitClose();
      return result === "ok";
    });
  }

  function prompt(options = {}) {
    return enqueue(async () => {
      ensureDialog();
      const title = options.title || "Introduce un valor";
      const message = options.message || "";
      const placeholder = options.placeholder || "";
      const confirmLabel = options.confirmLabel || "Aceptar";
      const cancelLabel = options.cancelLabel || "Cancelar";
      const minLength = Number(options.minLength) || 0;
      const multiline = options.multiline !== false;

      setIcon("question");
      dialogEl.querySelector("#archDialogTitle").textContent = title;
      dialogEl.querySelector("#archDialogMessage").textContent = message;

      const field = dialogEl.querySelector("#archDialogField");
      const input = dialogEl.querySelector("#archDialogInput");
      const hint = dialogEl.querySelector("#archDialogHint");

      field.classList.remove("hidden");
      input.value = options.defaultValue || "";
      input.placeholder = placeholder;
      input.rows = multiline ? 3 : 1;
      if (minLength > 0) {
        hint.textContent = `Mínimo ${minLength} caracteres`;
        hint.classList.remove("hidden");
      } else {
        hint.textContent = "";
        hint.classList.add("hidden");
      }

      const actions = dialogEl.querySelector("#archDialogActions");
      actions.innerHTML = "";
      actions.appendChild(bindButton(cancelLabel, "", "btn-secondary arch-dialog-btn"));
      const okBtn = bindButton(confirmLabel, "ok", "btn-primary arch-dialog-btn");
      actions.appendChild(okBtn);

      const validate = () => {
        const len = input.value.trim().length;
        okBtn.disabled = minLength > 0 && len < minLength;
      };
      input.oninput = validate;
      validate();

      dialogEl.addEventListener(
        "keydown",
        (e) => {
          if (e.key === "Enter" && !multiline && !e.shiftKey) {
            e.preventDefault();
            if (!okBtn.disabled) {
              dialogEl.returnValue = "ok";
              dialogEl.close();
            }
          }
        },
        { once: true }
      );

      const result = await waitClose();
      field.classList.add("hidden");
      if (result !== "ok") return null;
      const trimmed = input.value.trim();
      if (minLength > 0 && trimmed.length < minLength) {
        showToast(`Debe tener al menos ${minLength} caracteres`, { variant: "error" });
        return null;
      }
      return trimmed;
    });
  }

  const TOAST_DEFAULT_MS = 5200;

  const TOAST_VARIANTS = {
    success: { icon: "check_circle" },
    error: { icon: "error" },
    warning: { icon: "warning" },
    info: { icon: "info" },
  };

  function inferToastVariant(message) {
    const m = (message || "").toLowerCase();
    if (/no se pudo|error al|inválid|debe tener|formato no|terminó|expirada/.test(m)) {
      return "error";
    }
    if (/adjunta|primero|modo prueba|cuenta para/.test(m)) {
      return "warning";
    }
    if (/nueva sesión|nuevo chat|nueva prueba|pulsa enviar|actualizando/.test(m)) {
      return "info";
    }
    return "success";
  }

  function inferToastIcon(variant, message) {
    if (variant === "error") return "error";
    if (variant === "warning") return "warning";
    if (variant === "info") return "info";

    const m = (message || "").toLowerCase();
    if (/eliminad|quitado/.test(m)) return "delete";
    if (/subido|archivo/.test(m)) return "upload_file";
    if (/comentario/.test(m)) return "chat";
    if (/responsable|asignad/.test(m)) return "person_check";
    if (/invit|uniste|miembro/.test(m)) return "group_add";
    if (/etapa|avanzad|reabiert/.test(m)) return "flag";
    if (/proyecto|apartado/.test(m)) return "folder";
    if (/plan/.test(m)) return "payments";
    if (/copiado|enlace/.test(m)) return "link";
    if (/ajustes/.test(m)) return "settings";
    if (/revisión|revis/.test(m)) return "fact_check";
    if (/notas/.test(m)) return "sticky_note_2";
    if (/análisis|corrección/.test(m)) return "analytics";
    if (/chat/.test(m)) return "forum";
    if (/rol|usuario|panel/.test(m)) return "admin_panel_settings";
    return TOAST_VARIANTS.success.icon;
  }

  function normalizeToastOptions(message, optionsOrMs) {
    if (typeof optionsOrMs === "number") {
      return { message, duration: optionsOrMs };
    }
    if (optionsOrMs && typeof optionsOrMs === "object") {
      return { message, duration: TOAST_DEFAULT_MS, ...optionsOrMs };
    }
    return { message, duration: TOAST_DEFAULT_MS };
  }

  function ensureToastHost() {
    let host = document.getElementById("toast-host");
    if (!host) {
      const legacy = document.getElementById("toast");
      if (legacy) {
        legacy.id = "toast-host";
        legacy.className = "toast-host";
        legacy.removeAttribute("hidden");
        legacy.innerHTML = "";
        host = legacy;
      } else {
        host = document.createElement("div");
        host.id = "toast-host";
        host.className = "toast-host";
        host.setAttribute("aria-live", "polite");
        host.setAttribute("aria-atomic", "true");
        document.body.appendChild(host);
      }
    }
    if (host.parentElement !== document.body) {
      document.body.appendChild(host);
    }
    return host;
  }

  function revealToastCard(card) {
    card.classList.add("is-visible");
    card.style.opacity = "1";
    card.style.transform = "translate3d(0,0,0)";
  }

  function hideToastCard(card) {
    if (!card || !card.isConnected) return;
    card.classList.remove("is-visible");
    card.classList.add("is-leaving");
    const finish = () => {
      if (card.isConnected) card.remove();
    };
    card.addEventListener("animationend", finish, { once: true });
    window.setTimeout(finish, 360);
  }

  function showToast(message, optionsOrMs = {}) {
    const opts = normalizeToastOptions(message, optionsOrMs);
    const text = (opts.message || "").replace(/\n+/g, " · ").trim();
    if (!text) return;

    const duration = Math.max(1800, Number(opts.duration) || TOAST_DEFAULT_MS);
    const variant = opts.variant || inferToastVariant(text);
    const icon = opts.icon || inferToastIcon(variant, text);
    const host = ensureToastHost();

    if (showToast._card) {
      clearTimeout(showToast._t);
      hideToastCard(showToast._card);
      showToast._card = null;
    }

    const card = document.createElement("div");
    card.className = `toast-card toast-card--${variant}`;
    card.setAttribute("role", "status");
    card.innerHTML = `
      <span class="toast-icon material-symbols-outlined" aria-hidden="true">${icon}</span>
      <div class="toast-content">
        <p class="toast-message"></p>
        <div class="toast-progress" aria-hidden="true"><span></span></div>
      </div>`;
    card.querySelector(".toast-message").textContent = text;

    const progress = card.querySelector(".toast-progress span");
    if (progress) {
      progress.style.animationDuration = `${duration}ms`;
    }

    host.appendChild(card);
    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => revealToastCard(card));
    });

    showToast._card = card;
    showToast._t = window.setTimeout(() => {
      if (showToast._card === card) showToast._card = null;
      hideToastCard(card);
    }, duration);
  }

  window.PlanoDialog = { alert, confirm, prompt };
  window.showToast = showToast;
  window.PlanoToast = { show: showToast, DEFAULT_MS: TOAST_DEFAULT_MS };
})();
