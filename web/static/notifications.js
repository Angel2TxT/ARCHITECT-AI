/**
 * Campana + panel de notificaciones in-app.
 * El panel vive en document.body (fixed) para no quedar recortado por el sidebar.
 */
(function () {
  const POLL_MS = 45000;
  let pollTimer = null;
  let open = false;
  let items = [];
  let unread = 0;
  let loading = false;
  let roots = [];
  let floatingPanel = null;
  let listEl = null;
  let activeBell = null;

  function apiFetch(url, options) {
    if (window.PlanoAuth?.apiFetch) return window.PlanoAuth.apiFetch(url, options);
    if (typeof window.apiFetch === "function") return window.apiFetch(url, options);
    const token = localStorage.getItem("plano_ia_token");
    const headers = { ...(options?.headers || {}) };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (options?.body && !headers["Content-Type"]) {
      headers["Content-Type"] = "application/json";
    }
    return fetch(url, { ...options, headers }).then(async (res) => {
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.detail || data.message || res.statusText);
      return data;
    });
  }

  function hasSession() {
    return !!(window.PlanoAuth?.getToken?.() || localStorage.getItem("plano_ia_token"));
  }

  function escapeHtml(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function relativeTime(iso) {
    if (!iso) return "";
    const t = new Date(iso).getTime();
    if (Number.isNaN(t)) return "";
    const sec = Math.round((Date.now() - t) / 1000);
    if (sec < 60) return "ahora";
    if (sec < 3600) return `hace ${Math.floor(sec / 60)} min`;
    if (sec < 86400) return `hace ${Math.floor(sec / 3600)} h`;
    if (sec < 604800) return `hace ${Math.floor(sec / 86400)} d`;
    return new Date(iso).toLocaleDateString("es-MX", {
      day: "numeric",
      month: "short",
    });
  }

  function ensureFloatingPanel() {
    if (floatingPanel) return floatingPanel;
    floatingPanel = document.createElement("div");
    floatingPanel.id = "notifFloatingPanel";
    floatingPanel.className = "notif-panel notif-panel--floating";
    floatingPanel.hidden = true;
    floatingPanel.setAttribute("role", "dialog");
    floatingPanel.setAttribute("aria-label", "Notificaciones");
    floatingPanel.innerHTML = `
      <header class="notif-panel-head">
        <strong>Notificaciones</strong>
        <div class="notif-panel-actions">
          <button type="button" class="notif-text-btn" data-notif-action="mark-all">Marcar leídas</button>
          <button type="button" class="notif-icon-btn" data-notif-action="refresh" aria-label="Actualizar">
            <span class="material-symbols-outlined">refresh</span>
          </button>
        </div>
      </header>
      <div class="notif-list" role="list"></div>
      <footer class="notif-panel-foot">
        <span class="notif-empty-hint">Los avisos se guardan en tu cuenta</span>
      </footer>`;
    document.body.appendChild(floatingPanel);
    listEl = floatingPanel.querySelector(".notif-list");
    floatingPanel.addEventListener("click", (e) => e.stopPropagation());
    floatingPanel
      .querySelector('[data-notif-action="mark-all"]')
      .addEventListener("click", () => markAllRead());
    floatingPanel
      .querySelector('[data-notif-action="refresh"]')
      .addEventListener("click", () => refresh({ forceList: true }));
    return floatingPanel;
  }

  function ensureMount(mountEl) {
    if (!mountEl) return null;
    if (mountEl.dataset.notifReady === "1") {
      return mountEl.querySelector(".notif-root");
    }
    mountEl.dataset.notifReady = "1";
    mountEl.innerHTML = `
      <div class="notif-root">
        <button type="button" class="notif-bell" aria-label="Notificaciones" aria-expanded="false" aria-haspopup="true">
          <span class="material-symbols-outlined" aria-hidden="true">notifications</span>
          <span class="notif-badge" hidden>0</span>
        </button>
      </div>`;
    const root = mountEl.querySelector(".notif-root");
    const bell = root.querySelector(".notif-bell");
    bell.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (open && activeBell === bell) togglePanel(false);
      else togglePanel(true, bell);
    });
    roots.push({
      mount: mountEl,
      root,
      bell,
      badge: root.querySelector(".notif-badge"),
    });
    return root;
  }

  function syncBadges() {
    const count = Math.max(0, Number(unread) || 0);
    const label = count > 99 ? "99+" : String(count);
    const show = count > 0;

    for (const r of roots) {
      if (!r.badge) continue;
      r.badge.textContent = label;
      r.badge.hidden = !show;
      r.badge.classList.toggle("is-visible", show);
      r.badge.setAttribute("aria-hidden", show ? "false" : "true");
      if (show) {
        r.badge.removeAttribute("hidden");
      } else {
        r.badge.setAttribute("hidden", "");
      }
      r.bell?.classList.toggle("has-unread", show);
      r.bell?.setAttribute(
        "aria-label",
        show ? `Notificaciones (${label} sin leer)` : "Notificaciones"
      );
      r.bell?.setAttribute("aria-expanded", open && activeBell === r.bell ? "true" : "false");
      r.root?.classList.toggle("is-open", open && activeBell === r.bell);
    }
    const navBadge = document.getElementById("notifNavBadge");
    if (navBadge) {
      navBadge.textContent = label;
      navBadge.hidden = !show;
      navBadge.classList.toggle("is-visible", show);
      if (show) navBadge.removeAttribute("hidden");
      else navBadge.setAttribute("hidden", "");
    }
    document.getElementById("btnNotifications")?.classList.toggle("has-unread", show);
  }

  function renderList() {
    ensureFloatingPanel();
    if (!listEl) return;
    if (loading && !items.length) {
      listEl.innerHTML = `<p class="notif-empty">Cargando…</p>`;
      return;
    }
    if (!items.length) {
      listEl.innerHTML = `<p class="notif-empty">No tienes notificaciones</p>`;
      return;
    }
    listEl.innerHTML = items
      .map((n) => {
        const unreadCls = n.is_read ? "" : " is-unread";
        return `
          <article class="notif-item${unreadCls}" role="listitem" data-id="${n.id}" data-link="${escapeHtml(n.link || "")}">
            <span class="notif-item-icon material-symbols-outlined" aria-hidden="true">${escapeHtml(n.icon || "notifications")}</span>
            <div class="notif-item-body">
              <p class="notif-item-title">${escapeHtml(n.title)}</p>
              ${n.body ? `<p class="notif-item-text">${escapeHtml(n.body)}</p>` : ""}
              <time class="notif-item-time">${escapeHtml(relativeTime(n.created_at))}</time>
            </div>
            <button type="button" class="notif-item-dismiss" data-dismiss="${n.id}" aria-label="Eliminar">
              <span class="material-symbols-outlined">close</span>
            </button>
          </article>`;
      })
      .join("");

    listEl.querySelectorAll(".notif-item").forEach((el) => {
      el.addEventListener("click", (ev) => {
        if (ev.target.closest("[data-dismiss]")) return;
        void onItemClick(Number(el.dataset.id), el.dataset.link || "");
      });
    });
    listEl.querySelectorAll("[data-dismiss]").forEach((btn) => {
      btn.addEventListener("click", (ev) => {
        ev.stopPropagation();
        void dismiss(Number(btn.getAttribute("data-dismiss")));
      });
    });
  }

  function positionPanel(anchorEl) {
    const panel = ensureFloatingPanel();
    const width = Math.min(360, window.innerWidth - 16);
    const maxH = Math.min(440, window.innerHeight * 0.7);
    panel.style.width = `${width}px`;
    panel.style.maxHeight = `${maxH}px`;

    const margin = 8;
    let top;
    let left;

    if (anchorEl && anchorEl.getBoundingClientRect) {
      const rect = anchorEl.getBoundingClientRect();
      const collapsed = document.body.classList.contains("sidebar-collapsed");
      if (collapsed || rect.right < 120) {
        // Rail estrecho: abrir a la derecha de la campana
        left = Math.min(rect.right + margin, window.innerWidth - width - margin);
        top = Math.max(margin, Math.min(rect.top, window.innerHeight - maxH - margin));
      } else {
        // Sidebar expandido / admin topbar: debajo, alineado a la derecha del botón
        left = Math.min(rect.right - width, window.innerWidth - width - margin);
        left = Math.max(margin, left);
        top = rect.bottom + margin;
        if (top + maxH > window.innerHeight - margin) {
          top = Math.max(margin, rect.top - maxH - margin);
        }
      }
    } else {
      left = margin;
      top = 72;
    }

    panel.style.top = `${Math.round(top)}px`;
    panel.style.left = `${Math.round(left)}px`;
    panel.style.right = "auto";
    panel.style.bottom = "auto";
  }

  function togglePanel(next, bell) {
    open = !!next;
    activeBell = open ? bell || activeBell || roots[0]?.bell || null : null;
    const panel = ensureFloatingPanel();
    if (open) {
      positionPanel(activeBell);
      panel.hidden = false;
      document.body.classList.add("notif-panel-open");
      refresh({ forceList: true });
    } else {
      panel.hidden = true;
      document.body.classList.remove("notif-panel-open");
    }
    syncBadges();
  }

  async function refresh({ forceList = false } = {}) {
    if (!hasSession()) {
      unread = 0;
      items = [];
      syncBadges();
      renderList();
      return;
    }
    try {
      if (forceList || open) {
        loading = true;
        renderList();
        const data = await apiFetch("/api/notifications?limit=40");
        items = data.items || [];
        unread = data.unread || 0;
        loading = false;
        syncBadges();
        renderList();
      } else {
        const data = await apiFetch("/api/notifications/unread-count");
        unread = data.unread || 0;
        syncBadges();
      }
    } catch {
      loading = false;
      renderList();
    }
  }

  async function markAllRead() {
    if (!hasSession()) return;
    try {
      const data = await apiFetch("/api/notifications/mark-read", {
        method: "POST",
        body: JSON.stringify({ all: true }),
      });
      unread = data.unread || 0;
      items = items.map((n) => ({ ...n, is_read: true }));
      syncBadges();
      renderList();
    } catch {
      /* ignore */
    }
  }

  async function markRead(ids) {
    if (!ids?.length) return;
    try {
      const data = await apiFetch("/api/notifications/mark-read", {
        method: "POST",
        body: JSON.stringify({ ids }),
      });
      unread = data.unread ?? Math.max(0, unread - ids.length);
      const set = new Set(ids);
      items = items.map((n) => (set.has(n.id) ? { ...n, is_read: true } : n));
      syncBadges();
      renderList();
    } catch {
      /* ignore */
    }
  }

  async function dismiss(id) {
    try {
      const data = await apiFetch(`/api/notifications/${id}`, { method: "DELETE" });
      items = items.filter((n) => n.id !== id);
      unread = data.unread ?? unread;
      syncBadges();
      renderList();
    } catch {
      /* ignore */
    }
  }

  async function onItemClick(id, link) {
    const item = items.find((n) => n.id === id);
    if (item && !item.is_read) await markRead([id]);
    togglePanel(false);
    if (!link) return;
    if (link.includes("home_project=")) {
      const idMatch = /home_project=([^&]+)/.exec(link);
      if (idMatch && document.getElementById("btnHomeProjects")) {
        document.getElementById("btnHomeProjects").click();
      }
      return;
    }
    if (link.includes("support=1") && document.getElementById("btnSupportHelp")) {
      document.getElementById("btnSupportHelp").click();
      return;
    }
    if (link.includes("plans=1") && document.getElementById("btnPlans")) {
      document.getElementById("btnPlans").click();
      return;
    }
    if (link.includes("account=1") && document.getElementById("btnAccount")) {
      document.getElementById("btnAccount")?.click?.();
      return;
    }
    if (link.includes("/app/admin") || link.startsWith("/legacy-app")) {
      window.location.href = link;
    }
  }

  function onDocClick(e) {
    if (!open) return;
    if (floatingPanel?.contains(e.target)) return;
    if (roots.some((r) => r.root?.contains(e.target))) return;
    if (e.target.closest?.("#btnNotifications")) return;
    togglePanel(false);
  }

  function startPolling() {
    stopPolling();
    pollTimer = window.setInterval(() => refresh({ forceList: false }), POLL_MS);
  }

  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  function pickVisibleBell() {
    const collapsed = document.body.classList.contains("sidebar-collapsed");
    const preferred = collapsed
      ? document.querySelector("#notifMount .notif-bell")
      : document.querySelector("#notifMountExpanded .notif-bell") ||
        document.querySelector("#adminNotifMount .notif-bell");
    return preferred || roots.find((r) => r.bell?.offsetParent !== null)?.bell || roots[0]?.bell;
  }

  function openFromNav() {
    const bell = pickVisibleBell();
    togglePanel(true, bell);
  }

  function mount(selectorOrEl) {
    const el =
      typeof selectorOrEl === "string"
        ? document.querySelector(selectorOrEl)
        : selectorOrEl;
    if (!el) return null;
    ensureMount(el);
    syncBadges();
    return el;
  }

  function init(options = {}) {
    ensureFloatingPanel();
    const selectors = options.selectors || [
      "#notifMountExpanded",
      "#notifMount",
      "#adminNotifMount",
    ];
    selectors.forEach((s) => mount(s));
    document.getElementById("btnNotifications")?.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (open) togglePanel(false);
      else openFromNav();
    });
    document.addEventListener("click", onDocClick);
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && open) togglePanel(false);
    });
    window.addEventListener(
      "resize",
      () => {
        if (open) positionPanel(activeBell);
      },
      { passive: true }
    );
    if (hasSession()) {
      refresh({ forceList: false });
      startPolling();
    }
    window.addEventListener("storage", (e) => {
      if (e.key === "plano_ia_token") {
        if (hasSession()) {
          refresh({ forceList: false });
          startPolling();
        } else {
          stopPolling();
          unread = 0;
          items = [];
          syncBadges();
          renderList();
          togglePanel(false);
        }
      }
    });
  }

  window.PlanoNotifications = {
    init,
    mount,
    refresh,
    markAllRead,
    open: openFromNav,
    getUnread: () => unread,
  };
})();
