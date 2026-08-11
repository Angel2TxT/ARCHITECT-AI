(function () {
  const PINNED = [
    { id: "welcome", label: "Inicio", icon: "waving_hand", desc: "Bienvenida" },
  ];

  const MODULES = [
    {
      id: "support",
      label: "Soporte",
      icon: "support_agent",
      sections: [
        { id: "support-inbox", label: "Bandeja", icon: "inbox", desc: "Dudas de usuarios" },
      ],
    },
    {
      id: "ops",
      label: "Operación",
      icon: "dashboard",
      sections: [
        { id: "overview", label: "Resumen", icon: "monitoring", desc: "KPIs y panorama" },
        { id: "exports", label: "Exportaciones", icon: "download", desc: "Reportes globales" },
      ],
    },
    {
      id: "accounts",
      label: "Cuentas",
      icon: "group",
      sections: [
        { id: "users", label: "Usuarios", icon: "person", desc: "Altas y permisos" },
        { id: "subscriptions", label: "Suscripciones", icon: "card_membership", desc: "Planes activos" },
        { id: "guests", label: "Invitados", icon: "science", desc: "Prueba sin cuenta" },
      ],
    },
    {
      id: "billing",
      label: "Facturación",
      icon: "payments",
      sections: [
        { id: "plans", label: "Planes", icon: "sell", desc: "Catálogo y límites" },
        { id: "receipts", label: "Comprobantes", icon: "receipt_long", desc: "Tickets demo" },
        { id: "refunds", label: "Reembolsos", icon: "currency_exchange", desc: "Solicitudes de usuarios" },
      ],
    },
    {
      id: "ia",
      label: "IA y workspace",
      icon: "psychology",
      sections: [
        { id: "analyses", label: "Análisis", icon: "analytics", desc: "Revisión de planos" },
        { id: "chats", label: "Chats", icon: "forum", desc: "Conversaciones" },
        { id: "knowledge", label: "Biblioteca", icon: "menu_book", desc: "Manuales indexados" },
        { id: "norms", label: "Normativa", icon: "gavel", desc: "Umbrales Chiapas" },
      ],
    },
    {
      id: "home",
      label: "Casa hogar",
      icon: "home_work",
      sections: [
        { id: "home-projects", label: "Proyectos", icon: "apartment", desc: "9 etapas" },
        { id: "activity", label: "Actividad", icon: "history", desc: "Auditoría" },
      ],
    },
  ];

  const SECTION_META = {};
  PINNED.forEach((s) => (SECTION_META[s.id] = { ...s, moduleId: null, pinned: true }));
  MODULES.forEach((m) => m.sections.forEach((s) => (SECTION_META[s.id] = { ...s, moduleId: m.id })));

  const EXPORT_MAP = {
    users: "users",
    subscriptions: "subscriptions",
    plans: "plans",
    analyses: "analyses",
    "home-projects": "home-projects",
    chats: "chats",
    activity: "activity",
    receipts: "receipts",
    guests: "guest-trials",
  };

  const sidebarEl = document.getElementById("adminSidebar");
  const sectionRoot = document.getElementById("adminSectionRoot");
  const statusEl = document.getElementById("adminStatus");
  const errorEl = document.getElementById("adminError");
  const refreshBtn = document.getElementById("btnAdminRefresh");
  const modal = document.getElementById("adminModal");
  const modalTitle = document.getElementById("adminModalTitle");
  const modalBody = document.getElementById("adminModalBody");
  const modalFoot = document.getElementById("adminModalFoot");
  const modalClose = document.getElementById("adminModalClose");

  let currentSection = "welcome";
  let staffRole = "admin";
  let plans = [];
  let busyId = null;
  let userSearch = "";
  let userSearchTimer = null;
  let openModules = loadOpenModules();
  let supportFilter = "";
  let supportSelectedId = null;
  const PAGE_SIZE = 20;
  const pageState = {};
  const CLIENT_PAGE_KEYS = new Set(["knowledge", "norms-rules", "norms-domains"]);

  const cache = {
    stats: null,
    users: null,
    plans: null,
    subscriptions: null,
    analyses: null,
    homeProjects: null,
    chats: null,
    activity: null,
    guestTrials: null,
    receipts: null,
    billingSummary: null,
    refunds: null,
    knowledge: null,
    norms: null,
    supportInbox: null,
    supportTicket: null,
  };

  function visibleModules() {
    if (staffRole === "support") {
      return MODULES.filter((m) => m.id === "support" || m.id === "accounts").map((m) => {
        if (m.id !== "accounts") return m;
        return {
          ...m,
          sections: m.sections.filter((s) => s.id === "users"),
        };
      });
    }
    return MODULES;
  }

  function canAccessSection(sectionId) {
    if (staffRole === "admin") return !!SECTION_META[sectionId];
    return sectionId === "welcome" || sectionId === "support-inbox" || sectionId === "users";
  }

  function panelBrandLabel() {
    return staffRole === "support" ? "Panel de soporte" : "Panel admin";
  }

  function panelTitleLabel() {
    return staffRole === "support" ? "Soporte" : "Administración";
  }

  function getPage(key) {
    return Math.max(1, Number(pageState[key]) || 1);
  }

  function setPage(key, page) {
    pageState[key] = Math.max(1, Number(page) || 1);
  }

  function pageOffset(key) {
    return (getPage(key) - 1) * PAGE_SIZE;
  }

  function pageSlice(items, key) {
    const list = Array.isArray(items) ? items : [];
    const pages = Math.max(1, Math.ceil(list.length / PAGE_SIZE) || 1);
    const page = Math.min(getPage(key), pages);
    if (page !== getPage(key)) setPage(key, page);
    const start = (page - 1) * PAGE_SIZE;
    return { items: list.slice(start, start + PAGE_SIZE), total: list.length, page, pages };
  }

  function renderPager(key, total) {
    const t = Number(total) || 0;
    const pages = Math.max(1, Math.ceil(t / PAGE_SIZE) || 1);
    const page = Math.min(getPage(key), pages);
    if (page !== getPage(key)) setPage(key, page);
    const from = t === 0 ? 0 : (page - 1) * PAGE_SIZE + 1;
    const to = Math.min(page * PAGE_SIZE, t);
    return `
      <nav class="admin-pager" aria-label="Paginación">
        <button type="button" class="admin-pager-btn" data-page-key="${escapeHtml(key)}" data-page-go="prev" data-page-total="${t}" ${page <= 1 ? "disabled" : ""}>
          <span class="material-symbols-outlined">chevron_left</span>
          Anterior
        </button>
        <span class="admin-pager-meta">Mostrando ${from}–${to} de ${t} · Página ${page} de ${pages}</span>
        <button type="button" class="admin-pager-btn" data-page-key="${escapeHtml(key)}" data-page-go="next" data-page-total="${t}" ${page >= pages ? "disabled" : ""}>
          Siguiente
          <span class="material-symbols-outlined">chevron_right</span>
        </button>
      </nav>`;
  }

  function pageQuery(key) {
    return `limit=${PAGE_SIZE}&offset=${pageOffset(key)}`;
  }

  function defaultOpenModules() {
    const all = {};
    MODULES.forEach((m) => {
      all[m.id] = false;
    });
    return all;
  }

  function loadOpenModules() {
    try {
      const raw = sessionStorage.getItem("admin_open_modules_v4");
      if (!raw) return defaultOpenModules();
      return { ...defaultOpenModules(), ...JSON.parse(raw) };
    } catch {
      return defaultOpenModules();
    }
  }

  function saveOpenModules() {
    sessionStorage.setItem("admin_open_modules_v4", JSON.stringify(openModules));
  }

  function showError(message) {
    if (!errorEl) return;
    if (!message) {
      errorEl.textContent = "";
      errorEl.classList.add("hidden");
      return;
    }
    errorEl.textContent = message;
    errorEl.classList.remove("hidden");
  }

  function setStatus(message) {
    if (statusEl) statusEl.textContent = message || "";
  }

  function toast(msg) {
    window.showToast?.(msg) || setStatus(msg);
  }

  function formatDate(value) {
    if (!value) return "—";
    try {
      return new Date(value).toLocaleString("es-MX", {
        dateStyle: "short",
        timeStyle: "short",
      });
    } catch {
      return "—";
    }
  }

  function formatMoney(cents) {
    if (cents == null) return "—";
    return new Intl.NumberFormat("es-MX", {
      style: "currency",
      currency: "MXN",
      maximumFractionDigits: 0,
    }).format(cents / 100);
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function eventLabel(type) {
    const labels = {
      section_assigned: "Apartado asignado",
      section_status_changed: "Estado de apartado",
      section_reopened: "Apartado reabierto",
      section_comment_added: "Comentario",
      section_comment_deleted: "Comentario eliminado",
      document_uploaded: "Documento subido",
      document_deleted: "Documento eliminado",
      member_invited: "Invitación enviada",
      member_joined: "Miembro unido",
      member_removed: "Miembro removido",
      stage_completed: "Etapa completada",
      stage_reopened: "Etapa reabierta",
      stage_advanced: "Etapa avanzada",
    };
    return labels[type] || type;
  }

  const projectStatusMap = {
    active: "Activo",
    on_hold: "En pausa",
    completed: "Completado",
    canceled: "Cancelado",
  };

  const subStatusMap = {
    active: "Activa",
    trialing: "Prueba",
    past_due: "Vencida",
    canceled: "Cancelada",
    expired: "Expirada",
  };

  async function apiAdmin(url, options) {
    const res = await window.PlanoAuth.apiFetch(url, options);
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(window.PlanoAuth.formatApiError(data, `Error (${res.status})`));
    }
    return data;
  }

  async function confirmAction(message) {
    if (window.PlanoDialog?.confirm) {
      return window.PlanoDialog.confirm(message);
    }
    if (window.ArchitectDialogs?.confirm) {
      return window.ArchitectDialogs.confirm(message);
    }
    return window.confirm(message);
  }

  function openModal(title, bodyHtml, footHtml = "") {
    if (!modal) return;
    modalTitle.textContent = title;
    modalBody.innerHTML = bodyHtml;
    modalFoot.innerHTML = footHtml;
    if (typeof modal.showModal === "function") modal.showModal();
    else modal.setAttribute("open", "");
  }

  function closeModal() {
    if (!modal) return;
    if (typeof modal.close === "function") modal.close();
    else modal.removeAttribute("open");
  }

  function sectionHead(title, subtitle) {
    return `
      <header class="admin-section-head">
        <div>
          <h2>${escapeHtml(title)}</h2>
          ${subtitle ? `<p>${escapeHtml(subtitle)}</p>` : ""}
        </div>
      </header>`;
  }

  function exportButtons(resource) {
    if (!resource) return "";
    return `
      <div class="admin-export-inline">
        <button type="button" class="btn-secondary admin-export-res" data-export-res="${resource}" data-format="csv">
          <span class="material-symbols-outlined">table</span> Excel
        </button>
        <button type="button" class="btn-secondary admin-export-res" data-export-res="${resource}" data-format="pdf">
          <span class="material-symbols-outlined">picture_as_pdf</span> PDF
        </button>
      </div>`;
  }

  function pct(part, total) {
    const p = Number(part) || 0;
    const t = Number(total) || 0;
    if (!t) return 0;
    return Math.round((p / t) * 100);
  }

  function isoDate(d) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }

  function defaultReportRange() {
    const to = new Date();
    const from = new Date(to.getFullYear(), to.getMonth(), 1);
    return { from: isoDate(from), to: isoDate(to) };
  }

  function renderSidebar() {
    if (!sidebarEl) return;
    const mods = visibleModules();
    const crumb = document.getElementById("adminBreadcrumb");
    if (crumb) crumb.textContent = SECTION_META[currentSection]?.label || panelTitleLabel();

    const user = window.PlanoAuth?.getUser?.() || {};
    const initials = String(user.full_name || user.email || "A")
      .split(/\s+/)
      .map((w) => w[0])
      .join("")
      .slice(0, 2)
      .toUpperCase();
    const roleLabel =
      staffRole === "support" || user.role === "support"
        ? "Soporte"
        : user.role === "admin"
          ? "Administrador"
          : "Usuario";

    sidebarEl.innerHTML = `
      <div class="admin-sidebar-brand">
        <span class="admin-sidebar-brand-mark">
          <img src="/static/brand/architect-icon.png?v=3" alt="" width="20" height="20" />
        </span>
        <strong>${panelTitleLabel()}</strong>
        <button type="button" class="admin-sidebar-brand-close" id="adminSidebarClose" aria-label="Cerrar menú">
          <span class="material-symbols-outlined">close</span>
        </button>
      </div>
      <div class="admin-sidebar-scroll">
        <div class="admin-sidebar-top">
          <a class="admin-back-workspace" href="/legacy-app" title="Volver al workspace">
            <span class="material-symbols-outlined">arrow_back</span>
            <span>Volver al workspace</span>
          </a>
        </div>
        <div class="admin-nav-pinned">
          ${PINNED.map(
            (s) => `
            <button type="button" class="admin-nav-item admin-nav-item--pinned${currentSection === s.id ? " is-active" : ""}" data-section="${s.id}">
              <span class="material-symbols-outlined">${s.icon}</span>
              <span class="admin-nav-copy">
                <strong>${escapeHtml(s.label)}</strong>
                ${s.desc ? `<small>${escapeHtml(s.desc)}</small>` : ""}
              </span>
            </button>`
          ).join("")}
        </div>
        <nav class="admin-nav-modules">
          ${mods.map((mod) => {
            const open = openModules[mod.id] !== false;
            const hasActive = mod.sections.some((s) => s.id === currentSection);
            const expanded = open || hasActive;
            return `
            <div class="admin-mod${expanded ? " is-open" : ""}${hasActive ? " has-active" : ""}" data-module="${mod.id}">
              <button type="button" class="admin-mod-toggle" data-toggle-module="${mod.id}" aria-expanded="${expanded}">
                <span class="material-symbols-outlined">${mod.icon}</span>
                <strong>${escapeHtml(mod.label)}</strong>
                <span class="material-symbols-outlined admin-mod-chevron">${expanded ? "expand_less" : "expand_more"}</span>
              </button>
              <div class="admin-mod-children" ${expanded ? "" : "hidden"}>
                ${mod.sections
                  .map(
                    (s) => `
                  <button type="button" class="admin-nav-item${currentSection === s.id ? " is-active" : ""}" data-section="${s.id}">
                    <span class="material-symbols-outlined">${s.icon}</span>
                    <span class="admin-nav-copy">
                      <strong>${escapeHtml(s.label)}</strong>
                      ${s.desc ? `<small>${escapeHtml(s.desc)}</small>` : ""}
                    </span>
                  </button>`
                  )
                  .join("")}
              </div>
            </div>`;
          }).join("")}
        </nav>
      </div>
      <footer class="admin-sidebar-foot">
        <div class="admin-user-pill">
          <button type="button" class="admin-user-pill-main" id="adminBtnProfile" title="Mi cuenta / perfil">
            <div class="admin-user-avatar${user.avatar_url ? " has-photo" : ""}" id="adminUserAvatar" ${user.avatar_url ? `style="background-image:url('${escapeHtml(user.avatar_url)}')"` : ""}>${user.avatar_url ? "" : escapeHtml(initials)}</div>
            <div class="admin-user-info">
              <span class="admin-user-name">${escapeHtml(user.full_name || user.email || "Usuario")}</span>
              <span class="admin-user-role">${escapeHtml(roleLabel)}</span>
            </div>
          </button>
          <button type="button" class="admin-user-logout" id="adminBtnLogout" title="Cerrar sesión">
            <span class="material-symbols-outlined">logout</span>
          </button>
        </div>
        <button type="button" class="admin-sidebar-expand-all" id="adminExpandAll" title="Expandir todos los módulos">
          <span class="material-symbols-outlined">unfold_more</span>
          Expandir todo
        </button>
        <p>Panel operativo ARCHITECT · ${panelBrandLabel()}</p>
      </footer>`;
    document.title = `${panelTitleLabel()} · ARCHITECT`;
  }

  async function downloadResource(resource, format) {
    showError("");
    setStatus("Generando archivo…");
    try {
      const url = `/api/admin/export/${encodeURIComponent(resource)}?format=${encodeURIComponent(format)}`;
      const res = await window.PlanoAuth.apiFetch(url);
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(window.PlanoAuth.formatApiError(data, `Error (${res.status})`));
      }
      const blob = await res.blob();
      const disposition = res.headers.get("Content-Disposition") || "";
      const match = disposition.match(/filename=\"?([^\";]+)\"?/i);
      const filename = match?.[1] || `architect-${resource}.${format === "pdf" ? "pdf" : "csv"}`;
      const link = document.createElement("a");
      link.href = URL.createObjectURL(blob);
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(link.href);
      setStatus("");
      toast(`Exportado: ${filename}`);
    } catch (err) {
      setStatus("");
      showError(err.message || "No se pudo exportar");
    }
  }

  async function downloadSummaryReport(format) {
    const fromEl = document.getElementById("adminReportFrom");
    const toEl = document.getElementById("adminReportTo");
    if (!fromEl?.value || !toEl?.value) {
      showError("Selecciona fecha inicial y final.");
      return;
    }
    showError("");
    setStatus("Generando resumen…");
    try {
      const url = `/api/admin/reports/summary?from=${encodeURIComponent(fromEl.value)}&to=${encodeURIComponent(toEl.value)}&format=${encodeURIComponent(format)}`;
      const res = await window.PlanoAuth.apiFetch(url);
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(window.PlanoAuth.formatApiError(data, `Error (${res.status})`));
      }
      const blob = await res.blob();
      const disposition = res.headers.get("Content-Disposition") || "";
      const match = disposition.match(/filename=\"?([^\";]+)\"?/i);
      const filename = match?.[1] || `architect-resumen.${format === "pdf" ? "pdf" : "csv"}`;
      const link = document.createElement("a");
      link.href = URL.createObjectURL(blob);
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(link.href);
      setStatus("");
      toast("Resumen descargado");
    } catch (err) {
      setStatus("");
      showError(err.message || "No se pudo exportar");
    }
  }

  function renderExportCard() {
    const range = defaultReportRange();
    return `
      <section class="admin-export-card">
        <div class="admin-export-head">
          <div>
            <h3>Resumen por período</h3>
            <p>Métricas, altas, análisis y actividad filtrados por fechas.</p>
          </div>
        </div>
        <div class="admin-export-form">
          <label class="admin-export-field"><span>Desde</span><input type="date" id="adminReportFrom" value="${range.from}" /></label>
          <label class="admin-export-field"><span>Hasta</span><input type="date" id="adminReportTo" value="${range.to}" /></label>
          <div class="admin-export-actions">
            <button type="button" class="btn-secondary admin-export-btn" data-export-report="csv">Excel</button>
            <button type="button" class="btn-secondary admin-export-btn" data-export-report="pdf">PDF</button>
          </div>
        </div>
      </section>`;
  }

  function kpiCard(icon, label, value, meta) {
    return `
      <article class="admin-kpi">
        <div class="admin-kpi-icon"><span class="material-symbols-outlined">${icon}</span></div>
        <div class="admin-kpi-body">
          <span class="admin-kpi-label">${escapeHtml(label)}</span>
          <strong class="admin-kpi-value">${escapeHtml(value)}</strong>
          ${meta ? `<small class="admin-kpi-meta">${meta}</small>` : ""}
        </div>
      </article>`;
  }

  function renderWelcome() {
    const user = window.PlanoAuth?.getUser?.() || {};
    const name = (user.full_name || "").trim() || (user.email || "").split("@")[0] || "Administrador";
    const hour = new Date().getHours();
    const salute = hour < 12 ? "Buenos días" : hour < 19 ? "Buenas tardes" : "Buenas noches";
    const s = cache.stats;
    const dateLabel = new Date().toLocaleDateString("es-MX", {
      weekday: "long",
      day: "numeric",
      month: "long",
    });

    if (staffRole === "support") {
      return `
        <div class="admin-welcome">
          <section class="admin-welcome-banner">
            <div class="admin-welcome-banner-grid" aria-hidden="true"></div>
            <div class="admin-welcome-banner-copy">
              <p class="admin-welcome-kicker">Architect · Soporte</p>
              <h2>${escapeHtml(salute)}, <strong>${escapeHtml(name)}</strong></h2>
              <p class="admin-welcome-lead">
                Esta bandeja es solo para el equipo de soporte y administración.
                Los usuarios abren tickets desde <strong>Ayuda</strong> en su workspace.
              </p>
              <div class="admin-welcome-actions">
                <button type="button" class="admin-welcome-cta" data-section="support-inbox">
                  <span class="material-symbols-outlined">inbox</span>
                  Abrir bandeja
                </button>
              </div>
            </div>
            <div class="admin-welcome-glass">
              <img src="/static/brand/architect-icon.png?v=3" alt="" class="admin-welcome-mark" />
              <p class="admin-welcome-date">${escapeHtml(dateLabel)}</p>
              <p class="admin-welcome-aside-label">${panelBrandLabel()}</p>
            </div>
          </section>
        </div>`;
    }

    const shortcuts = [
      { id: "overview", icon: "monitoring", title: "Resumen", text: "KPIs y estado de la plataforma" },
      { id: "users", icon: "person", title: "Usuarios", text: "Cuentas, roles y acceso" },
      { id: "plans", icon: "sell", title: "Planes", text: "Catálogo y límites" },
      { id: "analyses", icon: "analytics", title: "Análisis", text: "Revisiones de planos" },
      { id: "home-projects", icon: "apartment", title: "Casa hogar", text: "Proyectos por etapas" },
      { id: "support-inbox", icon: "support_agent", title: "Bandeja soporte", text: "Responder tickets de usuarios" },
      { id: "exports", icon: "download", title: "Exportar", text: "Excel y PDF" },
    ];
    const stats = s
      ? [
          { icon: "group", value: s.users_active ?? 0, label: "Usuarios activos" },
          { icon: "analytics", value: s.analyses_this_month ?? 0, label: "Análisis del mes" },
          { icon: "home_work", value: s.home_projects_active ?? 0, label: "Proyectos activos" },
          { icon: "payments", value: s.paid_subscribers ?? 0, label: "Planes de pago" },
        ]
      : [];
    return `
      <div class="admin-welcome">
        <section class="admin-welcome-banner">
          <div class="admin-welcome-banner-grid" aria-hidden="true"></div>
          <div class="admin-welcome-banner-copy">
            <p class="admin-welcome-kicker">Architect · Control operativo</p>
            <h2>${escapeHtml(salute)}, <strong>${escapeHtml(name)}</strong></h2>
            <p class="admin-welcome-lead">
              Gestiona cuentas, facturación, IA y casa hogar. Los tickets de usuarios se atienden en la bandeja de soporte.
            </p>
            <div class="admin-welcome-actions">
              <button type="button" class="admin-welcome-cta" data-section="overview">
                <span class="material-symbols-outlined">monitoring</span>
                Abrir resumen
              </button>
              <button type="button" class="admin-welcome-cta admin-welcome-cta--ghost" data-section="support-inbox">
                <span class="material-symbols-outlined">support_agent</span>
                Bandeja soporte
              </button>
            </div>
          </div>
          <div class="admin-welcome-glass">
            <img src="/static/brand/architect-icon.png?v=3" alt="" class="admin-welcome-mark" />
            <p class="admin-welcome-date">${escapeHtml(dateLabel)}</p>
            <p class="admin-welcome-aside-label">${panelBrandLabel()}</p>
          </div>
        </section>

        ${
          stats.length
            ? `<section class="admin-welcome-stats">
                ${stats
                  .map(
                    (st) => `
                  <article class="admin-welcome-stat">
                    <span class="admin-welcome-stat-icon"><span class="material-symbols-outlined">${st.icon}</span></span>
                    <div>
                      <strong>${escapeHtml(String(st.value))}</strong>
                      <small>${escapeHtml(st.label)}</small>
                    </div>
                  </article>`
                  )
                  .join("")}
              </section>`
            : ""
        }

        <section class="admin-welcome-shortcuts">
          <div class="admin-welcome-section-label">
            <h3>Accesos rápidos</h3>
            <p>Entra directo a lo que más usas</p>
          </div>
          <div class="admin-welcome-grid">
            ${shortcuts
              .map(
                (c) => `
              <button type="button" class="admin-welcome-card" data-section="${c.id}">
                <span class="admin-welcome-card-left">
                  <span class="admin-welcome-card-icon"><span class="material-symbols-outlined">${c.icon}</span></span>
                  <span class="admin-nav-copy">
                    <strong>${escapeHtml(c.title)}</strong>
                    <small>${escapeHtml(c.text)}</small>
                  </span>
                </span>
                <span class="material-symbols-outlined admin-welcome-card-go">chevron_right</span>
              </button>`
              )
              .join("")}
          </div>
        </section>
      </div>`;
  }

  function renderOverview() {
    const s = cache.stats;
    if (!s) return "<p>Cargando resumen…</p>";
    const planBars = (s.plans_breakdown || [])
      .map((p) => {
        const max = Math.max(1, ...(s.plans_breakdown || []).map((x) => x.subscribers || 0));
        const width = Math.max(4, Math.round(((p.subscribers || 0) / max) * 100));
        return `<div class="admin-plan-bar-row">
          <div class="admin-plan-bar-head"><span>${escapeHtml(p.name)}</span><strong>${p.subscribers ?? 0}</strong></div>
          <div class="admin-plan-bar-track"><div class="admin-plan-bar-fill" style="width:${width}%"></div></div>
        </div>`;
      })
      .join("");

    return `
      <div class="admin-overview">
        ${sectionHead("Resumen", "Estado operativo de la plataforma.")}
        ${renderExportCard()}
        <div class="admin-kpi-grid">
          ${kpiCard("group", "Usuarios activos", s.users_active ?? 0, `${pct(s.users_active, s.users)}% del total`)}
          ${kpiCard("analytics", "Análisis del mes", s.analyses_this_month ?? 0, `${s.analyses_total ?? 0} históricos`)}
          ${kpiCard("home_work", "Proyectos activos", s.home_projects_active ?? 0, `${s.home_projects ?? 0} totales`)}
          ${kpiCard("payments", "Planes de pago", s.paid_subscribers ?? 0, formatMoney(s.billing_simulated_revenue_cents) + " simulados")}
        </div>
        <div class="admin-overview-panels">
          <section class="admin-panel-card">
            <div class="admin-panel-card-head"><h3>Distribución por plan</h3>
              <button type="button" class="admin-link-btn" data-section="plans">Ver planes</button></div>
            <div class="admin-plan-bars">${planBars || '<p class="admin-hint">Sin datos</p>'}</div>
          </section>
          <section class="admin-panel-card">
            <div class="admin-panel-card-head"><h3>Indicadores</h3></div>
            <ul class="admin-snapshot-list">
              <li><span>Chats</span><strong>${s.chats ?? 0}</strong></li>
              <li><span>Mensajes</span><strong>${s.messages ?? 0}</strong></li>
              <li><span>Invitados</span><strong>${s.guest_trials ?? 0}</strong></li>
              <li><span>Docs casa hogar</span><strong>${s.home_documents ?? 0}</strong></li>
              <li><span>Comprobantes</span><strong>${s.billing_receipts_total ?? 0}</strong></li>
              <li><span>Admins</span><strong>${s.users_admin ?? 0}</strong></li>
            </ul>
          </section>
        </div>
      </div>`;
  }

  function planOptions(selected) {
    return (plans.length ? plans : [{ slug: "free", name: "Gratis" }])
      .map((p) => `<option value="${p.slug}"${p.slug === selected ? " selected" : ""}>${escapeHtml(p.name)}</option>`)
      .join("");
  }

  function avatarMarkup(name, email) {
    const seed = (name || email || "?").trim() || "?";
    const parts = seed.split(/[\s@._-]+/).filter(Boolean);
    const initials = ((parts[0]?.[0] || "?") + (parts[1]?.[0] || "")).toUpperCase();
    return `<span class="admin-avatar" title="${escapeHtml(seed)}">${escapeHtml(initials)}</span>`;
  }

  function membersTable(headHtml, bodyHtml, extraClass = "") {
    return `
      <div class="admin-members${extraClass ? ` ${extraClass}` : ""}">
        <table class="admin-table" role="grid">
          <thead><tr>${headHtml}</tr></thead>
          <tbody>${bodyHtml}</tbody>
        </table>
      </div>`;
  }

  function renderUsers() {
    const data = cache.users;
    if (!data) return "<p>Cargando usuarios…</p>";
    const users = data.items || [];
    const total = data.total ?? users.length;
    const supportMode = staffRole === "support";
    const body =
      users
        .map((u) => {
          const canImpersonate = u.role === "user" && u.is_active;
          if (supportMode) {
            return `<tr data-user-id="${u.id}">
              <td class="admin-col-avatar">${avatarMarkup(u.full_name, u.email)}</td>
              <td class="admin-col-name"><strong>${escapeHtml(u.full_name || "Sin nombre")}</strong></td>
              <td class="admin-col-email">${escapeHtml(u.email || "")}</td>
              <td class="admin-col-plan">${escapeHtml(u.plan_name || u.plan_slug || "—")}</td>
              <td class="admin-col-usage">${u.analyses_used ?? 0}${u.analyses_limit != null ? `/${u.analyses_limit}` : ""}</td>
              <td class="admin-col-role">${escapeHtml(u.role || "user")}</td>
              <td class="admin-col-access">${u.is_active ? "Activo" : "Inactivo"}</td>
              <td class="admin-col-actions">
                <div class="admin-row-actions">
                  <button type="button" class="admin-icon-btn admin-impersonate-btn" data-action="impersonate" data-user-id="${u.id}" title="Entrar como este usuario" ${canImpersonate && busyId !== u.id ? "" : "disabled"}>
                    <span class="material-symbols-outlined">login</span>
                  </button>
                </div>
              </td>
            </tr>`;
          }
          return `<tr data-user-id="${u.id}">
              <td class="admin-col-avatar">${avatarMarkup(u.full_name, u.email)}</td>
              <td class="admin-col-name">
                <input class="admin-cell-input" data-action="name" aria-label="Nombre" type="text" spellcheck="false" autocomplete="off" value="${escapeHtml(u.full_name || "")}" placeholder="Sin nombre" ${busyId === u.id ? "disabled" : ""} />
              </td>
              <td class="admin-col-email">
                <input class="admin-cell-input admin-cell-input--accent" data-action="email" aria-label="Correo" type="email" spellcheck="false" autocomplete="off" value="${escapeHtml(u.email || "")}" ${busyId === u.id ? "disabled" : ""} />
              </td>
              <td class="admin-col-plan">
                <select class="admin-select admin-select--ghost" data-action="plan" ${busyId === u.id ? "disabled" : ""}>${planOptions(u.plan_slug || "free")}</select>
              </td>
              <td class="admin-col-usage">${u.analyses_used ?? 0}${u.analyses_limit != null ? `/${u.analyses_limit}` : ""}</td>
              <td class="admin-col-role">
                <select class="admin-select admin-select--ghost" data-action="role" ${busyId === u.id ? "disabled" : ""}>
                  <option value="user"${u.role === "user" ? " selected" : ""}>Usuario</option>
                  <option value="support"${u.role === "support" ? " selected" : ""}>Soporte</option>
                  <option value="admin"${u.role === "admin" ? " selected" : ""}>Admin</option>
                </select>
              </td>
              <td class="admin-col-access">
                <label class="admin-toggle"><input type="checkbox" data-action="active" ${u.is_active ? "checked" : ""} ${busyId === u.id ? "disabled" : ""}/><span>Activo</span></label>
              </td>
              <td class="admin-col-actions">
                <div class="admin-row-actions">
                  <button type="button" class="admin-icon-btn admin-impersonate-btn" data-action="impersonate" data-user-id="${u.id}" title="Entrar como este usuario" ${canImpersonate && busyId !== u.id ? "" : "disabled"}>
                    <span class="material-symbols-outlined">login</span>
                  </button>
                  <button type="button" class="admin-icon-btn" data-action="reset-usage" title="Reiniciar uso" ${busyId === u.id ? "disabled" : ""}><span class="material-symbols-outlined">restart_alt</span></button>
                  <button type="button" class="admin-delete-btn" data-action="delete" title="Eliminar" ${busyId === u.id ? "disabled" : ""}><span class="material-symbols-outlined">delete</span></button>
                </div>
              </td>
            </tr>`;
        })
        .join("") || `<tr><td colspan="8" class="admin-empty-row">Sin resultados en esta página</td></tr>`;
    return `
      ${sectionHead(
        "Usuarios",
        supportMode
          ? "Consulta cuentas y entra como el usuario para reproducir errores. No puedes editar roles desde soporte."
          : "Cuentas, roles, planes y acceso. También puedes entrar como un usuario para diagnosticar."
      )}
      <div class="admin-toolbar">
        <input type="search" class="admin-search" id="adminUserSearch" placeholder="Buscar correo o nombre…" value="${escapeHtml(userSearch)}" />
        <div class="admin-toolbar-actions">
          ${supportMode ? "" : `<button type="button" class="btn-primary" id="btnCreateUser">Nuevo usuario</button>`}
          ${supportMode ? "" : exportButtons("users")}
          <span class="admin-toolbar-meta">${total} cuenta(s)</span>
        </div>
      </div>
      ${membersTable(
        `<th class="admin-col-avatar"></th>
         <th class="admin-col-name">Nombre</th>
         <th class="admin-col-email">Correo</th>
         <th class="admin-col-plan">Plan</th>
         <th class="admin-col-usage">Uso</th>
         <th class="admin-col-role">Rol</th>
         <th class="admin-col-access">Acceso</th>
         <th class="admin-col-actions">Acciones</th>`,
        body,
        "admin-members--users"
      )}
      ${renderPager("users", total)}`;
  }

  function renderPlans() {
    const items = cache.plans;
    if (!items) return "<p>Cargando planes…</p>";
    return `
      ${sectionHead("Planes", "Catálogo, límites y beneficios.")}
      <div class="admin-toolbar">
        <button type="button" class="btn-primary" id="btnCreatePlan">Nuevo plan</button>
        ${exportButtons("plans")}
      </div>
      <div class="admin-cards-grid">
        ${items
          .map((p) => {
            const benefits = (p.features?.benefits || []).slice(0, 5);
            return `<article class="admin-plan-card" data-plan-id="${p.id}">
              <div class="admin-plan-card-head">
                <h3>${escapeHtml(p.name)}</h3>
                <span class="admin-plan-price">${formatMoney(p.price_monthly_cents)}<small>/mes</small></span>
              </div>
              <p class="admin-plan-desc">${escapeHtml(p.description || "—")}</p>
              <ul class="admin-plan-meta">
                <li><strong>${p.analyses_limit_monthly}</strong> análisis/mes</li>
                <li><strong>${p.storage_gb ?? p.features?.storage_gb ?? "—"} GB</strong> docs</li>
                <li>Hasta <strong>${p.max_file_mb} MB</strong></li>
                <li>Modelo real: <strong>${p.allow_real_model ? "Sí" : "No"}</strong></li>
                <li>App móvil: <strong>${p.features?.mobile_app ? "Sí" : "No"}</strong></li>
                <li>Suscriptores: <strong>${p.subscribers ?? 0}</strong></li>
                <li>Público: <strong>${p.is_public ? "Sí" : "No"}</strong></li>
              </ul>
              ${
                benefits.length
                  ? `<ul class="admin-plan-benefits">${benefits.map((b) => `<li>${escapeHtml(b)}</li>`).join("")}</ul>`
                  : ""
              }
              <div class="admin-row-actions" style="margin-top:0.75rem">
                <button type="button" class="btn-secondary text-xs" data-edit-plan="${p.id}">Editar</button>
                ${
                  p.slug !== "free"
                    ? `<button type="button" class="admin-delete-btn" data-hide-plan="${p.id}" title="Ocultar/eliminar"><span class="material-symbols-outlined">visibility_off</span></button>`
                    : ""
                }
              </div>
            </article>`;
          })
          .join("")}
      </div>`;
  }

  function renderSubscriptions() {
    const data = cache.subscriptions;
    if (!data) return "<p>Cargando suscripciones…</p>";
    const items = data.items || [];
    const total = data.total ?? items.length;
    const body =
      items
        .map(
          (s) => `<tr data-sub-id="${s.id}" data-user-id="${s.user_id}">
              <td class="admin-td-avatar">${avatarMarkup(s.user_name, s.user_email)}</td>
              <td>${escapeHtml(s.user_email || "—")}</td>
              <td><select class="admin-select admin-select--ghost" data-action="sub-plan">${planOptions(s.plan_slug || "free")}</select></td>
              <td><select class="admin-select admin-select--ghost" data-action="sub-status">
                ${Object.entries(subStatusMap)
                  .map(([k, v]) => `<option value="${k}"${s.status === k ? " selected" : ""}>${v}</option>`)
                  .join("")}
              </select></td>
              <td>${formatDate(s.current_period_end)}</td>
            </tr>`
        )
        .join("") || `<tr><td colspan="5" class="admin-empty-row">Sin resultados en esta página</td></tr>`;
    return `
      ${sectionHead("Suscripciones", "Estado de facturación por cuenta.")}
      <div class="admin-toolbar">${exportButtons("subscriptions")}<span class="admin-toolbar-meta">${total}</span></div>
      ${membersTable(
        `<th></th><th>Usuario</th><th>Plan</th><th>Estado</th><th>Fin período</th>`,
        body
      )}
      ${renderPager("subscriptions", total)}`;
  }

  function renderReceipts() {
    const data = cache.receipts;
    const summary = cache.billingSummary;
    if (!data) return "<p>Cargando comprobantes…</p>";
    const items = data.items || data.receipts || [];
    const total = data.total ?? items.length;
    return `
      ${sectionHead("Comprobantes", "Tickets de pasarela simulada.")}
      <div class="admin-kpi-grid" style="margin-bottom:1rem">
        ${kpiCard("receipt", "Emitidos", summary?.receipts_total ?? total, "")}
        ${kpiCard("payments", "Ingresos simulados", formatMoney(summary?.simulated_revenue_cents ?? 0), "")}
      </div>
      <div class="admin-toolbar">${exportButtons("receipts")}<span class="admin-toolbar-meta">${total}</span></div>
      <div class="admin-members"><table class="admin-table" role="grid">
        <thead><tr><th>Folio</th><th>Usuario</th><th>Plan</th><th>Importe</th><th>Email</th><th>Fecha</th></tr></thead>
        <tbody>
          ${items
            .map(
              (r) => `<tr>
              <td>${escapeHtml(r.receipt_number || r.id)}</td>
              <td>${escapeHtml(r.user_email || r.email || "—")}</td>
              <td>${escapeHtml(r.plan_name || r.plan_slug || "—")}</td>
              <td>${formatMoney(r.amount_cents)}</td>
              <td>${r.email_sent_at ? "Enviado" : "—"}</td>
              <td>${formatDate(r.created_at)}</td>
            </tr>`
            )
            .join("") || '<tr><td colspan="6" class="admin-empty-row">Sin comprobantes</td></tr>'}
        </tbody>
      </table></div>
      ${renderPager("receipts", total)}`;
  }

  function renderRefunds() {
    const data = cache.refunds;
    if (!data) return "<p>Cargando reembolsos…</p>";
    const items = data.refunds || [];
    return `
      ${sectionHead("Reembolsos", "Solicitudes tras cancelar con uso bajo en la ventana de días.")}
      <div class="admin-toolbar"><span class="admin-toolbar-meta">${items.length} solicitud${items.length === 1 ? "" : "es"}</span></div>
      <div class="admin-members"><table class="admin-table" role="grid">
        <thead><tr><th>ID</th><th>Usuario</th><th>Importe</th><th>Folio</th><th>Estado</th><th>Fecha</th><th></th></tr></thead>
        <tbody>
          ${items
            .map((r) => {
              const pending = r.status === "pending";
              return `<tr data-refund-id="${r.id}">
              <td>${r.id}</td>
              <td>
                <strong>${escapeHtml(r.user_name || "—")}</strong><br>
                <span class="admin-hint">${escapeHtml(r.user_email || "")}</span>
              </td>
              <td>${formatMoney(r.amount_cents)}</td>
              <td>${escapeHtml(r.receipt_number || "—")}</td>
              <td><span class="admin-pill">${escapeHtml(r.status)}</span></td>
              <td>${formatDate(r.created_at)}</td>
              <td class="admin-row-actions">
                ${
                  pending
                    ? `<button type="button" class="btn-secondary text-xs" data-refund-approve="${r.id}">Aprobar</button>
                       <button type="button" class="admin-delete-btn text-xs" data-refund-reject="${r.id}">Rechazar</button>`
                    : `<span class="admin-hint">${escapeHtml(r.admin_note || "—")}</span>`
                }
              </td>
            </tr>`;
            })
            .join("") || '<tr><td colspan="7" class="admin-empty-row">Sin solicitudes</td></tr>'}
        </tbody>
      </table></div>`;
  }

  function renderAnalyses() {
    const data = cache.analyses;
    if (!data) return "<p>Cargando análisis…</p>";
    const items = data.items || [];
    const total = data.total ?? items.length;
    return `
      ${sectionHead("Análisis", "Revisiones de planos con IA.")}
      <div class="admin-toolbar">${exportButtons("analyses")}<span class="admin-toolbar-meta">${total}</span></div>
      <div class="admin-members"><table class="admin-table" role="grid">
        <thead><tr><th>ID</th><th>Usuario</th><th>Archivo</th><th>Modelo</th><th>Fecha</th><th></th></tr></thead>
        <tbody>
          ${items
            .map(
              (a) => `<tr data-analysis-id="${a.id}">
              <td>${a.id}</td>
              <td>${escapeHtml(a.user_email || "—")}</td>
              <td>${escapeHtml(a.original_filename || "—")}</td>
              <td>${a.is_demo_model ? "Demo" : "Real"}</td>
              <td>${formatDate(a.created_at)}</td>
              <td class="admin-row-actions">
                <button type="button" class="admin-icon-btn" data-action="view-analysis" title="Ver"><span class="material-symbols-outlined">visibility</span></button>
                <button type="button" class="admin-delete-btn" data-action="delete-analysis" title="Eliminar"><span class="material-symbols-outlined">delete</span></button>
              </td>
            </tr>`
            )
            .join("") || `<tr><td colspan="6" class="admin-empty-row">Sin resultados en esta página</td></tr>`}
        </tbody>
      </table></div>
      ${renderPager("analyses", total)}`;
  }

  function renderChats() {
    const data = cache.chats;
    if (!data) return "<p>Cargando chats…</p>";
    const items = data.items || [];
    const total = data.total ?? items.length;
    return `
      ${sectionHead("Chats", "Conversaciones del asistente.")}
      <div class="admin-toolbar">${exportButtons("chats")}<span class="admin-toolbar-meta">${total}</span></div>
      <div class="admin-members"><table class="admin-table" role="grid">
        <thead><tr><th>Usuario</th><th>Título</th><th>Msgs</th><th>Actualizado</th><th></th></tr></thead>
        <tbody>
          ${items
            .map(
              (c) => `<tr data-chat-id="${escapeHtml(c.id)}">
              <td>${escapeHtml(c.user_email || "—")}</td>
              <td>${escapeHtml(c.title || "—")}</td>
              <td>${c.messages_count ?? 0}</td>
              <td>${formatDate(c.updated_at)}</td>
              <td class="admin-row-actions">
                <button type="button" class="admin-icon-btn" data-action="view-chat" title="Ver"><span class="material-symbols-outlined">visibility</span></button>
                <button type="button" class="admin-delete-btn" data-action="delete-chat" title="Eliminar"><span class="material-symbols-outlined">delete</span></button>
              </td>
            </tr>`
            )
            .join("") || `<tr><td colspan="5" class="admin-empty-row">Sin resultados en esta página</td></tr>`}
        </tbody>
      </table></div>
      ${renderPager("chats", total)}`;
  }

  function renderHomeProjects() {
    const data = cache.homeProjects;
    if (!data) return "<p>Cargando proyectos…</p>";
    const items = data.items || [];
    const total = data.total ?? items.length;
    return `
      ${sectionHead("Proyectos casa hogar", "Vivienda por etapas.")}
      <div class="admin-toolbar">${exportButtons("home-projects")}<span class="admin-toolbar-meta">${total}</span></div>
      <div class="admin-members"><table class="admin-table" role="grid">
        <thead><tr><th>Nombre</th><th>Cliente</th><th>Propietario</th><th>Estado</th><th>Etapa</th><th>Docs</th><th></th></tr></thead>
        <tbody>
          ${items
            .map(
              (p) => `<tr data-project-id="${escapeHtml(p.id)}">
              <td>${escapeHtml(p.name)}</td>
              <td>${escapeHtml(p.client_name || "—")}</td>
              <td>${escapeHtml(p.owner_email || "—")}</td>
              <td>${escapeHtml(projectStatusMap[p.status] || p.status)}</td>
              <td>${p.current_stage ?? "—"}</td>
              <td>${p.documents_count ?? 0}</td>
              <td class="admin-row-actions">
                <button type="button" class="admin-delete-btn" data-action="delete-project" title="Eliminar"><span class="material-symbols-outlined">delete</span></button>
              </td>
            </tr>`
            )
            .join("") || `<tr><td colspan="7" class="admin-empty-row">Sin resultados en esta página</td></tr>`}
        </tbody>
      </table></div>
      ${renderPager("home-projects", total)}`;
  }

  function renderActivity() {
    const data = cache.activity;
    if (!data) return "<p>Cargando actividad…</p>";
    const items = data.items || [];
    const total = data.total ?? items.length;
    return `
      ${sectionHead("Actividad", "Auditoría de casa hogar.")}
      <div class="admin-toolbar">${exportButtons("activity")}<span class="admin-toolbar-meta">${total}</span></div>
      <div class="admin-members"><table class="admin-table" role="grid">
        <thead><tr><th>Fecha</th><th>Proyecto</th><th>Evento</th><th>Actor</th></tr></thead>
        <tbody>
          ${items
            .map(
              (e) => `<tr>
              <td>${formatDate(e.created_at)}</td>
              <td>${escapeHtml(e.project_name || e.project_id || "—")}</td>
              <td>${escapeHtml(eventLabel(e.event_type))}</td>
              <td>${escapeHtml(e.actor_email || "Sistema")}</td>
            </tr>`
            )
            .join("") || `<tr><td colspan="4" class="admin-empty-row">Sin resultados en esta página</td></tr>`}
        </tbody>
      </table></div>
      ${renderPager("activity", total)}`;
  }

  function renderGuests() {
    const data = cache.guestTrials;
    if (!data) return "<p>Cargando invitados…</p>";
    const items = data.items || [];
    const total = data.total ?? items.length;
    return `
      ${sectionHead("Invitados", "Pruebas sin cuenta (cookie).")}
      <div class="admin-toolbar">${exportButtons("guest-trials")}
        <span class="admin-toolbar-meta">${total} · ${data.totals?.analyses ?? 0} análisis · ${data.totals?.asks ?? 0} preguntas</span>
      </div>
      <div class="admin-members"><table class="admin-table" role="grid">
        <thead><tr><th>ID</th><th>Análisis</th><th>Preguntas</th><th>Última visita</th><th></th></tr></thead>
        <tbody>
          ${items
            .map(
              (g) => `<tr data-guest-id="${escapeHtml(g.id)}">
              <td title="${escapeHtml(g.id)}">${escapeHtml(String(g.id).slice(0, 8))}…</td>
              <td>${g.analyses_count ?? 0}</td>
              <td>${g.asks_count ?? 0}</td>
              <td>${formatDate(g.last_seen_at)}</td>
              <td class="admin-row-actions">
                <button type="button" class="admin-icon-btn" data-action="reset-guest" title="Reiniciar"><span class="material-symbols-outlined">restart_alt</span></button>
                <button type="button" class="admin-delete-btn" data-action="delete-guest" title="Eliminar"><span class="material-symbols-outlined">delete</span></button>
              </td>
            </tr>`
            )
            .join("") || `<tr><td colspan="5" class="admin-empty-row">Sin resultados en esta página</td></tr>`}
        </tbody>
      </table></div>
      ${renderPager("guests", total)}`;
  }

  function renderSystem() {
    const s = cache.stats;
    const g = cache.guestTrials;
    if (!s) return "<p>Cargando…</p>";
    return `
      ${sectionHead("Salud del sistema", "Uso global e invitados.")}
      <div class="admin-kpi-grid">
        ${kpiCard("storage", "Documentos", s.home_documents ?? 0, "")}
        ${kpiCard("forum", "Mensajes", s.messages ?? 0, "")}
        ${kpiCard("science", "Invitados", s.guest_trials ?? 0, `${g?.totals?.asks ?? 0} preguntas`)}
        ${kpiCard("analytics", "Análisis totales", s.analyses_total ?? 0, `${s.analyses_demo ?? 0} demo`)}
      </div>
      <p class="admin-hint">La gestión detallada de invitados está en Cuentas → Invitados.</p>
      <button type="button" class="btn-secondary" data-section="guests">Ir a invitados</button>`;
  }

  function renderExports() {
    const resources = [
      { id: "users", label: "Usuarios", icon: "person" },
      { id: "subscriptions", label: "Suscripciones", icon: "card_membership" },
      { id: "plans", label: "Planes", icon: "sell" },
      { id: "analyses", label: "Análisis", icon: "analytics" },
      { id: "chats", label: "Chats", icon: "forum" },
      { id: "home-projects", label: "Proyectos", icon: "apartment" },
      { id: "activity", label: "Actividad", icon: "history" },
      { id: "receipts", label: "Comprobantes", icon: "receipt_long" },
      { id: "guest-trials", label: "Invitados", icon: "science" },
    ];
    return `
      ${sectionHead("Exportaciones", "Descarga CSV/Excel o PDF de cada recurso operativo.")}
      ${renderExportCard()}
      <div class="admin-export-grid">
        ${resources
          .map(
            (r) => `
          <article class="admin-export-tile">
            <div class="admin-export-tile-head">
              <span class="material-symbols-outlined">${r.icon}</span>
              <strong>${escapeHtml(r.label)}</strong>
            </div>
            ${exportButtons(r.id)}
          </article>`
          )
          .join("")}
      </div>`;
  }

  function renderKnowledge() {
    const k = cache.knowledge;
    if (!k) return "<p>Cargando biblioteca…</p>";
    const catalog = k.catalog || [];
    const paged = pageSlice(catalog, "knowledge");
    const docRows = paged.items
      .map(
        (d) => `<tr>
          <td>${escapeHtml(d.title || d.name || "—")}</td>
          <td>${d.pages ?? "—"}</td>
          <td>${escapeHtml(d.summary || "—")}</td>
        </tr>`
      )
      .join("");
    return `
      ${sectionHead("Biblioteca", "Manuales indexados para el asistente.")}
      <div class="admin-kpi-grid" style="margin-bottom:1rem">
        ${kpiCard("menu_book", "Páginas", k.pages ?? 0, k.ready ? "Lista" : "Sin indexar")}
        ${kpiCard("description", "Documentos", k.documents ?? catalog.length, "")}
        ${kpiCard("category", "Tipos", Object.keys(k.page_types || {}).length, "")}
      </div>
      ${
        catalog.length
          ? `<div class="admin-members"><table class="admin-table" role="grid">
              <thead><tr><th>Documento</th><th>Páginas</th><th>Resumen</th></tr></thead>
              <tbody>${docRows || `<tr><td colspan="3" class="admin-empty-row">Sin resultados en esta página</td></tr>`}</tbody>
            </table></div>
            ${renderPager("knowledge", paged.total)}`
          : `<p class="admin-hint">Sin manuales indexados. Comando: <code>${escapeHtml(k.ingest_command || "python scripts/ingest_knowledge_docs.py")}</code></p>`
      }
      <p class="admin-hint">${escapeHtml(k.docs || "docs/CONOCIMIENTO_DOCUMENTOS.md")}</p>`;
  }

  function renderNorms() {
    const n = cache.norms;
    if (!n) return "<p>Cargando normativa…</p>";
    const rulesList = Object.entries(n.rules || {}).map(([key, vals]) => ({
      key,
      detail: Object.entries(vals || {})
        .map(([k, v]) => `${k}: ${v}`)
        .join(" · "),
    }));
    const rulesPage = pageSlice(rulesList, "norms-rules");
    const domainsList = n.construction_domains || [];
    const domainsPage = pageSlice(domainsList, "norms-domains");
    const ruleRows = rulesPage.items
      .map((r) => `<tr><td>${escapeHtml(r.key)}</td><td>${escapeHtml(r.detail)}</td></tr>`)
      .join("");
    const domains = domainsPage.items
      .map(
        (d) => `<tr>
          <td>${escapeHtml(d.title || d.id)}</td>
          <td>${escapeHtml(d.scope || "—")}</td>
          <td>${escapeHtml(d.norm_ref || "—")}</td>
        </tr>`
      )
      .join("");
    const sources = (n.sources || [])
      .map((s) => {
        if (typeof s === "string") return `<li>${escapeHtml(s)}</li>`;
        return `<li>${escapeHtml(s.title || s.name || JSON.stringify(s))}</li>`;
      })
      .join("");
    return `
      ${sectionHead(n.bundle_title || "Normativa", "Umbrales y catálogo Chiapas.")}
      <p class="admin-hint">Bundle: <code>${escapeHtml(n.bundle_id || "—")}</code></p>
      <div class="admin-overview-panels">
        <section class="admin-panel-card">
          <div class="admin-panel-card-head"><h3>Reglas aplicadas</h3></div>
          <div class="admin-members"><table class="admin-table" role="grid">
            <thead><tr><th>Ámbito</th><th>Umbrales</th></tr></thead>
            <tbody>${ruleRows || '<tr><td colspan="2">Sin datos</td></tr>'}</tbody>
          </table></div>
          ${renderPager("norms-rules", rulesPage.total)}
        </section>
        <section class="admin-panel-card">
          <div class="admin-panel-card-head"><h3>Fuentes</h3></div>
          <ul class="admin-snapshot-list" style="display:block">${sources || "<li>Sin fuentes</li>"}</ul>
        </section>
      </div>
      <section class="admin-subsection" style="margin-top:1.25rem">
        <h3>Dominios de construcción</h3>
        <div class="admin-members"><table class="admin-table" role="grid">
          <thead><tr><th>Dominio</th><th>Alcance</th><th>Referencia</th></tr></thead>
          <tbody>${domains || '<tr><td colspan="3">Sin dominios</td></tr>'}</tbody>
        </table></div>
        ${renderPager("norms-domains", domainsPage.total)}
      </section>
      ${n.note ? `<p class="admin-hint">${escapeHtml(n.note)}</p>` : ""}`;
  }

  function supportStatusLabel(status) {
    return (
      {
        open: "Abierto",
        pending: "En espera",
        resolved: "Resuelto",
        closed: "Cerrado",
      }[status] || status
    );
  }

  function renderSupportInbox() {
    const data = cache.supportInbox;
    if (!data) return "<p>Cargando bandeja…</p>";
    const items = data.items || [];
    const total = data.total ?? items.length;
    const detail = cache.supportTicket;
    const openCount = items.filter((t) => t.status === "open" || t.status === "pending").length;

    const listCards =
      items
        .map((t) => {
          const when = formatDate(t.updated_at || t.created_at);
          const pri = t.priority === "high" ? '<span class="admin-support-priority">Alta</span>' : "";
          return `<button type="button" class="admin-support-card${supportSelectedId === t.id ? " is-selected" : ""}" data-ticket-id="${t.id}">
            <span class="admin-support-card-avatar">${avatarMarkup(t.user_name, t.user_email)}</span>
            <span class="admin-support-card-body">
              <span class="admin-support-card-top">
                <strong>${escapeHtml(t.subject)}</strong>
                <span class="admin-badge admin-badge--${escapeHtml(t.status)}">${escapeHtml(supportStatusLabel(t.status))}</span>
              </span>
              <span class="admin-support-card-meta">
                <span>${escapeHtml(t.user_name || t.user_email || "Usuario")}</span>
                <span>·</span>
                <span>${escapeHtml(when)}</span>
                ${pri}
              </span>
            </span>
          </button>`;
        })
        .join("") ||
      `<div class="admin-support-empty-list">
        <span class="material-symbols-outlined">inbox</span>
        <strong>Sin tickets en esta vista</strong>
        <p>Cambia el filtro o espera nuevas consultas.</p>
      </div>`;

    const thread = detail
      ? `
      <aside class="admin-support-detail">
        <header class="admin-support-detail-head">
          <div class="admin-support-detail-top">
            <button type="button" class="admin-support-back" id="btnSupportBack" aria-label="Volver a la lista">
              <span class="material-symbols-outlined">arrow_back</span>
            </button>
            <div class="admin-support-detail-identity">
              <div class="admin-support-detail-avatar">${avatarMarkup(detail.user_name, detail.user_email)}</div>
              <div class="admin-support-detail-copy">
                <h3>${escapeHtml(detail.subject)}</h3>
                <p>${escapeHtml(detail.user_name || "")}${detail.user_email ? ` · ${escapeHtml(detail.user_email)}` : ""}</p>
              </div>
            </div>
          </div>
          <div class="admin-support-detail-actions">
            <select id="supportStatusSelect" class="admin-select">
              ${["open", "pending", "resolved", "closed"]
                .map(
                  (s) =>
                    `<option value="${s}"${detail.status === s ? " selected" : ""}>${supportStatusLabel(s)}</option>`
                )
                .join("")}
            </select>
            <button type="button" class="btn-secondary" id="btnSupportAssign">
              <span class="material-symbols-outlined">person_add</span>
              <span class="admin-support-action-label">Asignarme</span>
            </button>
            <button type="button" class="btn-primary" id="btnSupportImpersonate" data-user-id="${detail.user_id}">
              <span class="material-symbols-outlined">login</span>
              <span class="admin-support-action-label">Entrar como usuario</span>
            </button>
          </div>
        </header>
        <div class="admin-support-thread">
          ${(detail.messages || [])
            .map(
              (m) => `
            <article class="admin-support-msg${m.is_staff ? " is-staff" : " is-user"}">
              <header>
                <strong>${escapeHtml(m.author_name || m.author_email || (m.is_staff ? "Soporte" : "Usuario"))}</strong>
                <time>${formatDate(m.created_at)}</time>
              </header>
              <p>${escapeHtml(m.body)}</p>
            </article>`
            )
            .join("")}
        </div>
        <form class="admin-support-reply" id="supportReplyForm">
          <textarea id="supportReplyBody" rows="3" placeholder="Escribe la respuesta para el usuario…" required></textarea>
          <button type="submit" class="btn-primary">
            <span class="material-symbols-outlined">send</span>
            Enviar respuesta
          </button>
        </form>
      </aside>`
      : `<aside class="admin-support-detail admin-support-detail--empty">
          <span class="material-symbols-outlined">forum</span>
          <strong>Selecciona un ticket</strong>
          <p>Verás la conversación completa y podrás responder al usuario.</p>
        </aside>`;

    return `
      <div class="admin-support-hero">
        <div>
          <h2>Bandeja de soporte</h2>
          <p>Solo personal de soporte y administración. Los usuarios abren tickets desde Ayuda en su workspace; aquí los respondes.</p>
        </div>
        <div class="admin-support-hero-stats">
          <div class="admin-support-stat">
            <strong>${total}</strong>
            <span>Total</span>
          </div>
          <div class="admin-support-stat admin-support-stat--accent">
            <strong>${openCount}</strong>
            <span>Activos (página)</span>
          </div>
        </div>
      </div>
      <div class="admin-toolbar admin-support-toolbar">
        <select id="supportStatusFilter" class="admin-select">
          <option value="">Todos los estados</option>
          <option value="open"${supportFilter === "open" ? " selected" : ""}>Abiertos</option>
          <option value="pending"${supportFilter === "pending" ? " selected" : ""}>En espera</option>
          <option value="resolved"${supportFilter === "resolved" ? " selected" : ""}>Resueltos</option>
          <option value="closed"${supportFilter === "closed" ? " selected" : ""}>Cerrados</option>
        </select>
        <span class="admin-toolbar-meta">${total} ticket(s)</span>
      </div>
      <div class="admin-support-layout${supportSelectedId ? " has-selection" : ""}">
        <div class="admin-support-list">
          <div class="admin-support-cards">${listCards}</div>
          ${renderPager("support-inbox", total)}
        </div>
        ${thread}
      </div>`;
  }

  function renderTools() {
    const links = [
      { section: "exports", label: "Centro de exportaciones", icon: "download", hint: "PDF y Excel" },
      { section: "users", label: "Crear / gestionar usuarios", icon: "person_add", hint: "Cuentas" },
      { section: "plans", label: "Editar catálogo de planes", icon: "sell", hint: "Facturación" },
      { section: "knowledge", label: "Estado de biblioteca IA", icon: "menu_book", hint: "Conocimiento" },
      { section: "norms", label: "Consultar normativa", icon: "gavel", hint: "Chiapas" },
      { section: "system", label: "Salud del sistema", icon: "health_and_safety", hint: "Monitoreo" },
      { section: "guests", label: "Limpiar invitados", icon: "science", hint: "Pruebas" },
      { section: "activity", label: "Auditoría casa hogar", icon: "history", hint: "Eventos" },
    ];
    return `
      ${sectionHead("Herramientas", "Atajos del panel de administración.")}
      <div class="admin-tools-grid">
        ${links
          .map(
            (l) => `
          <button type="button" class="admin-tool-card" data-section="${l.section}">
            <span class="material-symbols-outlined">${l.icon}</span>
            <span class="admin-nav-copy">
              <strong>${escapeHtml(l.label)}</strong>
              <small>${escapeHtml(l.hint)}</small>
            </span>
            <span class="material-symbols-outlined">chevron_right</span>
          </button>`
          )
          .join("")}
      </div>
      <p class="admin-hint">Abre el workspace: <a href="/legacy-app">/legacy-app</a> · App React: <a href="/">/</a></p>`;
  }

  function renderSection() {
    const map = {
      welcome: renderWelcome,
      overview: renderOverview,
      exports: renderExports,
      users: renderUsers,
      plans: renderPlans,
      subscriptions: renderSubscriptions,
      receipts: renderReceipts,
      refunds: renderRefunds,
      analyses: renderAnalyses,
      chats: renderChats,
      knowledge: renderKnowledge,
      norms: renderNorms,
      "home-projects": renderHomeProjects,
      activity: renderActivity,
      guests: renderGuests,
      "support-inbox": renderSupportInbox,
    };
    const fn = map[currentSection] || (() => "<p>Sección no disponible</p>");
    if (sectionRoot) sectionRoot.innerHTML = fn();
    bindSectionEvents();
  }

  function showCreateUserModal() {
    openModal(
      "Nuevo usuario",
      `<div class="admin-form-grid">
        <label>Correo<input type="email" id="cuEmail" required /></label>
        <label>Contraseña<input type="password" id="cuPass" required minlength="6" /></label>
        <label>Nombre<input type="text" id="cuName" /></label>
        <label>Rol<select id="cuRole"><option value="user">Usuario</option><option value="support">Soporte</option><option value="admin">Admin</option></select></label>
        <label>Plan<select id="cuPlan">${planOptions("free")}</select></label>
      </div>`,
      `<button type="button" class="btn-secondary" id="adminModalCancel">Cancelar</button>
       <button type="button" class="btn-primary" id="adminModalSaveUser">Crear</button>`
    );
  }

  function showPlanModal(plan) {
    const f = plan?.features || {};
    const benefitsText = Array.isArray(f.benefits) ? f.benefits.join("\n") : "";
    openModal(
      plan ? `Editar plan · ${plan.name}` : "Nuevo plan",
      `<div class="admin-form-grid">
        ${plan ? "" : `<label>Slug<input type="text" id="plSlug" placeholder="starter-pro" /></label>`}
        <label>Nombre<input type="text" id="plName" value="${escapeHtml(plan?.name || "")}" /></label>
        <label class="admin-form-span">Descripción<textarea id="plDesc" rows="2">${escapeHtml(plan?.description || "")}</textarea></label>
        <label>Precio (centavos MXN)<input type="number" id="plPrice" value="${plan?.price_monthly_cents ?? 0}" min="0" /></label>
        <label>Análisis/mes<input type="number" id="plAnalyses" value="${plan?.analyses_limit_monthly ?? 5}" min="0" /></label>
        <label>MB por archivo<input type="number" id="plMb" value="${plan?.max_file_mb ?? 5}" min="1" /></label>
        <label>GB documentación<input type="number" id="plGb" value="${f.storage_gb ?? 1}" min="0" step="0.5" /></label>
        <label>Orden<input type="number" id="plOrder" value="${plan?.sort_order ?? 0}" /></label>
        <label class="admin-toggle"><input type="checkbox" id="plReal" ${plan?.allow_real_model ? "checked" : ""}/> Modelo real</label>
        <label class="admin-toggle"><input type="checkbox" id="plPublic" ${plan?.is_public !== false ? "checked" : ""}/> Público</label>
        <label class="admin-toggle"><input type="checkbox" id="plMobile" ${f.mobile_app ? "checked" : ""}/> App móvil</label>
        <label class="admin-toggle"><input type="checkbox" id="plExport" ${f.export ? "checked" : ""}/> Export reportes</label>
        <label class="admin-toggle"><input type="checkbox" id="plInvites" ${f.team_invites ? "checked" : ""}/> Invitaciones equipo</label>
        <label>Máx. proyectos<input type="number" id="plMaxProj" value="${f.max_projects ?? 1}" min="0" /></label>
        <label>Preguntas chat/mes<input type="number" id="plAsks" value="${f.asks_limit_monthly ?? 20}" min="0" /></label>
        <label class="admin-form-span">Beneficios (uno por línea)<textarea id="plBenefits" rows="5">${escapeHtml(benefitsText)}</textarea></label>
      </div>`,
      `<button type="button" class="btn-secondary" id="adminModalCancel">Cancelar</button>
       <button type="button" class="btn-primary" id="adminModalSavePlan" data-plan-id="${plan?.id || ""}">Guardar</button>`
    );
  }

  function collectPlanPayload() {
    const benefits = ($("#plBenefits")?.value || "")
      .split("\n")
      .map((l) => l.trim())
      .filter(Boolean);
    return {
      slug: $("#plSlug")?.value?.trim() || undefined,
      name: $("#plName")?.value?.trim() || "",
      description: $("#plDesc")?.value || "",
      price_monthly_cents: Number($("#plPrice")?.value || 0),
      analyses_limit_monthly: Number($("#plAnalyses")?.value || 0),
      max_file_mb: Number($("#plMb")?.value || 5),
      sort_order: Number($("#plOrder")?.value || 0),
      allow_real_model: !!$("#plReal")?.checked,
      is_public: !!$("#plPublic")?.checked,
      features: {
        storage_gb: Number($("#plGb")?.value || 1),
        mobile_app: !!$("#plMobile")?.checked,
        export: !!$("#plExport")?.checked,
        team_invites: !!$("#plInvites")?.checked,
        home_projects: true,
        max_projects: Number($("#plMaxProj")?.value || 1),
        asks_limit_monthly: Number($("#plAsks")?.value || 20),
        benefits,
      },
    };
  }

  function $(sel) {
    return document.querySelector(sel);
  }

  async function startUserImpersonation(userId) {
    if (!userId) return;
    showError("");
    setStatus("Entrando como usuario…");
    try {
      const data = await apiAdmin(`/api/support/impersonate/${userId}`, { method: "POST" });
      if (!data?.access_token) throw new Error("No se recibió sesión de impersonación");
      window.PlanoAuth.startImpersonation(data);
    } catch (err) {
      setStatus("");
      showError(err.message || "No se pudo entrar como ese usuario");
    }
  }

  function bindSectionEvents() {
    sectionRoot?.querySelectorAll("[data-page-go]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const key = btn.getAttribute("data-page-key");
        const go = btn.getAttribute("data-page-go");
        if (!key) return;
        const total = Number(btn.getAttribute("data-page-total") || 0);
        const pages = Math.max(1, Math.ceil(total / PAGE_SIZE) || 1);
        let page = getPage(key);
        if (go === "prev") page -= 1;
        else if (go === "next") page += 1;
        else page = Number(go) || 1;
        page = Math.min(pages, Math.max(1, page));
        if (page === getPage(key)) return;
        setPage(key, page);
        if (CLIENT_PAGE_KEYS.has(key)) renderSection();
        else await loadSection(true);
      });
    });

    document.getElementById("supportStatusFilter")?.addEventListener("change", async (e) => {
      supportFilter = e.target.value || "";
      setPage("support-inbox", 1);
      supportSelectedId = null;
      await loadSection(true);
    });

    sectionRoot?.querySelectorAll("[data-ticket-id]").forEach((row) => {
      row.addEventListener("click", async () => {
        supportSelectedId = Number(row.getAttribute("data-ticket-id"));
        await loadSection(true);
        const thread = sectionRoot?.querySelector(".admin-support-thread");
        if (thread) thread.scrollTop = thread.scrollHeight;
      });
    });

    document.getElementById("btnSupportBack")?.addEventListener("click", async () => {
      supportSelectedId = null;
      cache.supportTicket = null;
      renderSection();
    });

    document.getElementById("btnSupportAssign")?.addEventListener("click", async () => {
      if (!supportSelectedId) return;
      try {
        await apiAdmin(`/api/support/tickets/${supportSelectedId}`, {
          method: "PATCH",
          body: JSON.stringify({ assign_to_me: true }),
        });
        toast("Ticket asignado");
        await loadSection(true);
      } catch (err) {
        showError(err.message);
      }
    });

    document.getElementById("btnSupportImpersonate")?.addEventListener("click", async (e) => {
      const uid = Number(e.currentTarget.getAttribute("data-user-id"));
      const ok = await confirmAction(
        "Vas a entrar al workspace como este usuario para diagnosticar el error. ¿Continuar?"
      );
      if (!ok) return;
      await startUserImpersonation(uid);
    });

    document.getElementById("supportStatusSelect")?.addEventListener("change", async (e) => {
      if (!supportSelectedId) return;
      try {
        await apiAdmin(`/api/support/tickets/${supportSelectedId}`, {
          method: "PATCH",
          body: JSON.stringify({ status: e.target.value }),
        });
        toast("Estado actualizado");
        await loadSection(true);
      } catch (err) {
        showError(err.message);
      }
    });

    document.getElementById("supportReplyForm")?.addEventListener("submit", async (e) => {
      e.preventDefault();
      if (!supportSelectedId) return;
      const body = document.getElementById("supportReplyBody")?.value || "";
      try {
        await apiAdmin(`/api/support/tickets/${supportSelectedId}/messages`, {
          method: "POST",
          body: JSON.stringify({ body }),
        });
        toast("Respuesta enviada");
        await loadSection(true);
      } catch (err) {
        showError(err.message);
      }
    });

    document.getElementById("btnCreateUser")?.addEventListener("click", showCreateUserModal);
    document.getElementById("btnCreatePlan")?.addEventListener("click", () => showPlanModal(null));

    document.querySelectorAll("[data-edit-plan]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const id = Number(btn.getAttribute("data-edit-plan"));
        const plan = (cache.plans || []).find((p) => p.id === id);
        if (plan) showPlanModal(plan);
      });
    });

    document.querySelectorAll("[data-hide-plan]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.getAttribute("data-hide-plan");
        if (!(await confirmAction("¿Ocultar o eliminar este plan?"))) return;
        try {
          const res = await apiAdmin(`/api/admin/plans/${id}`, { method: "DELETE" });
          toast(res.action === "hidden" ? "Plan ocultado (tiene suscriptores)" : "Plan eliminado");
          await loadSection(true);
        } catch (err) {
          showError(err.message);
        }
      });
    });

    document.querySelectorAll(".admin-export-btn").forEach((btn) => {
      btn.addEventListener("click", () => downloadSummaryReport(btn.dataset.exportReport || "csv"));
    });
    document.querySelectorAll(".admin-export-res").forEach((btn) => {
      btn.addEventListener("click", () =>
        downloadResource(btn.dataset.exportRes, btn.dataset.format || "csv")
      );
    });

    // Users row actions
    sectionRoot?.querySelectorAll("tr[data-user-id]").forEach((row) => {
      const id = Number(row.dataset.userId);
      const nameInput = row.querySelector('[data-action="name"]');
      const emailInput = row.querySelector('[data-action="email"]');
      const saveField = async (field, value, input) => {
        const next = String(value ?? "").trim();
        const prev = input?.dataset.prev ?? "";
        if (next === prev) return;
        const label = field === "name" ? "nombre" : "correo";
        const ok = await confirmAction(
          `¿Guardar el cambio de ${label}?\n\nDe: ${prev || "(vacío)"}\nA: ${next || "(vacío)"}`
        );
        if (!ok) {
          if (input) input.value = prev;
          return;
        }
        try {
          const payload =
            field === "name" ? { full_name: next } : { email: next };
          await apiAdmin(`/api/admin/users/${id}`, {
            method: "PATCH",
            body: JSON.stringify(payload),
          });
          if (input) input.dataset.prev = next;
          toast(field === "name" ? "Nombre actualizado" : "Correo actualizado");
          const av = row.querySelector(".admin-avatar");
          if (av && field === "name") {
            const email = emailInput?.value || "";
            av.outerHTML = avatarMarkup(next, email);
          }
        } catch (err) {
          showError(err.message);
          if (input) input.value = prev;
        }
      };
      if (nameInput) {
        nameInput.dataset.prev = nameInput.value;
        nameInput.addEventListener("blur", () => saveField("name", nameInput.value, nameInput));
        nameInput.addEventListener("keydown", (e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            nameInput.blur();
          }
          if (e.key === "Escape") {
            e.preventDefault();
            nameInput.value = nameInput.dataset.prev || "";
            nameInput.blur();
          }
        });
      }
      if (emailInput) {
        emailInput.dataset.prev = emailInput.value;
        emailInput.addEventListener("blur", () => saveField("email", emailInput.value, emailInput));
        emailInput.addEventListener("keydown", (e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            emailInput.blur();
          }
          if (e.key === "Escape") {
            e.preventDefault();
            emailInput.value = emailInput.dataset.prev || "";
            emailInput.blur();
          }
        });
      }
      row.querySelector('[data-action="plan"]')?.addEventListener("change", async (e) => {
        busyId = id;
        try {
          await apiAdmin(`/api/admin/users/${id}/plan`, {
            method: "POST",
            body: JSON.stringify({ plan_slug: e.target.value }),
          });
          toast("Plan actualizado");
          await loadSection(true);
        } catch (err) {
          showError(err.message);
        } finally {
          busyId = null;
        }
      });
      row.querySelector('[data-action="role"]')?.addEventListener("change", async (e) => {
        try {
          await apiAdmin(`/api/admin/users/${id}`, {
            method: "PATCH",
            body: JSON.stringify({ role: e.target.value }),
          });
          toast("Rol actualizado");
        } catch (err) {
          showError(err.message);
          await loadSection(true);
        }
      });
      row.querySelector('[data-action="active"]')?.addEventListener("change", async (e) => {
        try {
          await apiAdmin(`/api/admin/users/${id}`, {
            method: "PATCH",
            body: JSON.stringify({ is_active: e.target.checked }),
          });
          toast("Acceso actualizado");
        } catch (err) {
          showError(err.message);
          await loadSection(true);
        }
      });
      row.querySelector('[data-action="reset-usage"]')?.addEventListener("click", async () => {
        if (!(await confirmAction("¿Reiniciar uso del mes?"))) return;
        try {
          await apiAdmin(`/api/admin/users/${id}/reset-usage`, { method: "POST" });
          toast("Uso reiniciado");
          await loadSection(true);
        } catch (err) {
          showError(err.message);
        }
      });
      row.querySelector('[data-action="delete"]')?.addEventListener("click", async () => {
        if (!(await confirmAction("¿Eliminar este usuario? Esta acción no se puede deshacer."))) return;
        try {
          await apiAdmin(`/api/admin/users/${id}`, { method: "DELETE" });
          toast("Usuario eliminado");
          await loadSection(true);
        } catch (err) {
          showError(err.message);
        }
      });
      row.querySelector('[data-action="impersonate"]')?.addEventListener("click", async (e) => {
        e.preventDefault();
        e.stopPropagation();
        const uid = Number(e.currentTarget.getAttribute("data-user-id") || id);
        const ok = await confirmAction(
          "Vas a entrar al workspace como este usuario para diagnosticar. ¿Continuar?"
        );
        if (!ok) return;
        await startUserImpersonation(uid);
      });
    });

    // Subscriptions
    sectionRoot?.querySelectorAll("tr[data-sub-id]").forEach((row) => {
      const id = Number(row.dataset.subId);
      row.querySelector('[data-action="sub-plan"]')?.addEventListener("change", async (e) => {
        try {
          await apiAdmin(`/api/admin/subscriptions/${id}`, {
            method: "PATCH",
            body: JSON.stringify({ plan_slug: e.target.value }),
          });
          toast("Suscripción actualizada");
          await loadSection(true);
        } catch (err) {
          showError(err.message);
        }
      });
      row.querySelector('[data-action="sub-status"]')?.addEventListener("change", async (e) => {
        try {
          await apiAdmin(`/api/admin/subscriptions/${id}`, {
            method: "PATCH",
            body: JSON.stringify({ status: e.target.value }),
          });
          toast("Estado actualizado");
        } catch (err) {
          showError(err.message);
        }
      });
    });

    // Analyses / chats / projects / guests
    sectionRoot?.querySelectorAll("[data-action='view-analysis']").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.closest("tr")?.dataset.analysisId;
        try {
          const a = await apiAdmin(`/api/admin/analyses/${id}`);
          openModal(
            `Análisis #${a.id}`,
            `<dl class="admin-dl">
              <div><dt>Usuario</dt><dd>${escapeHtml(a.user_email || "—")}</dd></div>
              <div><dt>Archivo</dt><dd>${escapeHtml(a.original_filename || "—")}</dd></div>
              <div><dt>Modelo</dt><dd>${a.is_demo_model ? "Demo" : "Real"}</dd></div>
              <div><dt>Estado</dt><dd>${escapeHtml(a.status_text || "—")}</dd></div>
              <div><dt>Detecciones</dt><dd>${a.detections_count ?? 0}</dd></div>
              <div><dt>Incidencias</dt><dd>${a.issues_count ?? 0}</dd></div>
              <div><dt>Fecha</dt><dd>${formatDate(a.created_at)}</dd></div>
            </dl>`,
            `<button type="button" class="btn-secondary" id="adminModalCancel">Cerrar</button>`
          );
        } catch (err) {
          showError(err.message);
        }
      });
    });
    sectionRoot?.querySelectorAll("[data-action='delete-analysis']").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.closest("tr")?.dataset.analysisId;
        if (!(await confirmAction("¿Eliminar este análisis?"))) return;
        try {
          await apiAdmin(`/api/admin/analyses/${id}`, { method: "DELETE" });
          toast("Análisis eliminado");
          await loadSection(true);
        } catch (err) {
          showError(err.message);
        }
      });
    });
    sectionRoot?.querySelectorAll("[data-action='view-chat']").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.closest("tr")?.dataset.chatId;
        try {
          const c = await apiAdmin(`/api/admin/chats/${encodeURIComponent(id)}`);
          const msgs = (c.messages || [])
            .map(
              (m) => `<div class="admin-chat-msg admin-chat-msg--${escapeHtml(m.role)}">
                <strong>${escapeHtml(m.role)}</strong>
                <p>${escapeHtml(typeof m.content === "object" ? m.content.text || JSON.stringify(m.content) : m.content)}</p>
                <time>${formatDate(m.created_at)}</time>
              </div>`
            )
            .join("");
          openModal(
            c.title || "Chat",
            `<p class="admin-hint">${escapeHtml(c.user_email || "")}</p><div class="admin-chat-thread">${msgs || "Sin mensajes"}</div>`,
            `<button type="button" class="btn-secondary" id="adminModalCancel">Cerrar</button>`
          );
        } catch (err) {
          showError(err.message);
        }
      });
    });
    sectionRoot?.querySelectorAll("[data-action='delete-chat']").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.closest("tr")?.dataset.chatId;
        if (!(await confirmAction("¿Eliminar este chat y sus mensajes?"))) return;
        try {
          await apiAdmin(`/api/admin/chats/${encodeURIComponent(id)}`, { method: "DELETE" });
          toast("Chat eliminado");
          await loadSection(true);
        } catch (err) {
          showError(err.message);
        }
      });
    });
    sectionRoot?.querySelectorAll("[data-action='delete-project']").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.closest("tr")?.dataset.projectId;
        if (!(await confirmAction("¿Eliminar este proyecto casa hogar y su documentación?"))) return;
        try {
          await apiAdmin(`/api/admin/home-projects/${encodeURIComponent(id)}`, { method: "DELETE" });
          toast("Proyecto eliminado");
          await loadSection(true);
        } catch (err) {
          showError(err.message);
        }
      });
    });
    sectionRoot?.querySelectorAll("[data-action='reset-guest']").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.closest("tr")?.dataset.guestId;
        try {
          await apiAdmin(`/api/admin/guest-trials/${encodeURIComponent(id)}/reset`, { method: "POST" });
          toast("Contadores reiniciados");
          await loadSection(true);
        } catch (err) {
          showError(err.message);
        }
      });
    });
    sectionRoot?.querySelectorAll("[data-action='delete-guest']").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.closest("tr")?.dataset.guestId;
        if (!(await confirmAction("¿Eliminar este registro de invitado?"))) return;
        try {
          await apiAdmin(`/api/admin/guest-trials/${encodeURIComponent(id)}`, { method: "DELETE" });
          toast("Invitado eliminado");
          await loadSection(true);
        } catch (err) {
          showError(err.message);
        }
      });
    });

    sectionRoot?.querySelectorAll("[data-refund-approve]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.getAttribute("data-refund-approve");
        if (!(await confirmAction("¿Aprobar este reembolso (simulado)?"))) return;
        try {
          await apiAdmin(`/api/admin/refunds/${id}/review`, {
            method: "POST",
            body: JSON.stringify({ approve: true, admin_note: "Aprobado" }),
          });
          toast("Reembolso aprobado");
          await loadSection(true);
        } catch (err) {
          showError(err.message);
        }
      });
    });
    sectionRoot?.querySelectorAll("[data-refund-reject]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.getAttribute("data-refund-reject");
        const note = prompt("Motivo del rechazo (opcional):") || "Rechazado";
        try {
          await apiAdmin(`/api/admin/refunds/${id}/review`, {
            method: "POST",
            body: JSON.stringify({ approve: false, admin_note: note }),
          });
          toast("Solicitud rechazada");
          await loadSection(true);
        } catch (err) {
          showError(err.message);
        }
      });
    });

    const search = document.getElementById("adminUserSearch");
    search?.addEventListener("input", () => {
      userSearch = search.value || "";
      clearTimeout(userSearchTimer);
      userSearchTimer = setTimeout(() => {
        setPage("users", 1);
        loadSection(true);
      }, 320);
    });
  }

  function isAdminMobile() {
    return window.matchMedia("(max-width: 767px)").matches;
  }

  function setAdminNavOpen(open) {
    const next = !!open && isAdminMobile();
    document.body.classList.toggle("admin-nav-open", next);
    const btn = document.getElementById("adminMenuBtn");
    const icon = document.getElementById("adminMenuIcon");
    const backdrop = document.getElementById("adminSidebarBackdrop");
    if (btn) {
      btn.setAttribute("aria-expanded", next ? "true" : "false");
      btn.setAttribute("aria-label", next ? "Cerrar menú" : "Abrir menú");
    }
    if (icon) icon.textContent = next ? "close" : "menu";
    if (backdrop) backdrop.setAttribute("aria-hidden", next ? "false" : "true");
  }

  function toggleAdminNav() {
    setAdminNavOpen(!document.body.classList.contains("admin-nav-open"));
  }

  function bindGlobalEvents() {
    sidebarEl?.addEventListener("click", (e) => {
      if (e.target.closest("#adminSidebarClose")) {
        setAdminNavOpen(false);
        return;
      }
      if (e.target.closest("#adminBtnLogout")) {
        window.PlanoAuth?.logout?.();
        return;
      }
      if (e.target.closest("#adminBtnProfile")) {
        window.ArchitectAccount?.open?.();
        return;
      }
      const expandAll = e.target.closest("#adminExpandAll");
      if (expandAll) {
        openModules = defaultOpenModules();
        saveOpenModules();
        renderSidebar();
        return;
      }
      const toggle = e.target.closest("[data-toggle-module]");
      if (toggle) {
        const id = toggle.getAttribute("data-toggle-module");
        openModules[id] = !openModules[id];
        saveOpenModules();
        renderSidebar();
        return;
      }
      const item = e.target.closest("[data-section]");
      if (item) {
        goToSection(item.getAttribute("data-section"));
      }
    });

    document.getElementById("adminMenuBtn")?.addEventListener("click", () => toggleAdminNav());
    document.getElementById("adminSidebarBackdrop")?.addEventListener("click", () => setAdminNavOpen(false));
    window.addEventListener("resize", () => {
      if (!isAdminMobile()) setAdminNavOpen(false);
    });
    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && document.body.classList.contains("admin-nav-open")) {
        setAdminNavOpen(false);
      }
    });

    sectionRoot?.addEventListener("click", (e) => {
      const go = e.target.closest("[data-section]");
      if (go && !go.closest("select")) {
        const id = go.getAttribute("data-section");
        if (id && SECTION_META[id]) goToSection(id);
      }
    });

    refreshBtn?.addEventListener("click", () => loadSection(true));
    modalClose?.addEventListener("click", closeModal);
    modal?.addEventListener("click", (e) => {
      if (e.target === modal) closeModal();
      if (e.target.id === "adminModalCancel") closeModal();
      if (e.target.id === "adminModalSaveUser") saveNewUser();
      if (e.target.id === "adminModalSavePlan") savePlan(e.target.dataset.planId);
    });

    window.addEventListener("hashchange", () => {
      const fromHash = parseHash();
      if (fromHash && fromHash !== currentSection) goToSection(fromHash, false);
    });
  }

  async function saveNewUser() {
    try {
      await apiAdmin("/api/admin/users", {
        method: "POST",
        body: JSON.stringify({
          email: $("#cuEmail")?.value,
          password: $("#cuPass")?.value,
          full_name: $("#cuName")?.value || "",
          role: $("#cuRole")?.value || "user",
          plan_slug: $("#cuPlan")?.value || "free",
        }),
      });
      closeModal();
      toast("Usuario creado");
      await loadSection(true);
    } catch (err) {
      showError(err.message);
    }
  }

  async function savePlan(planId) {
    const payload = collectPlanPayload();
    if (!payload.name) {
      showError("El nombre es obligatorio");
      return;
    }
    try {
      if (planId) {
        await apiAdmin(`/api/admin/plans/${planId}`, {
          method: "PATCH",
          body: JSON.stringify(payload),
        });
      } else {
        await apiAdmin("/api/admin/plans", {
          method: "POST",
          body: JSON.stringify(payload),
        });
      }
      closeModal();
      toast("Plan guardado");
      cache.plans = null;
      await loadSection(true);
    } catch (err) {
      showError(err.message);
    }
  }

  function parseHash() {
    const raw = (location.hash || "").replace(/^#/, "");
    if (!raw) return null;
    const parts = raw.split("/");
    const last = parts[parts.length - 1];
    return SECTION_META[last] ? last : SECTION_META[raw] ? raw : null;
  }

  function setHash(sectionId) {
    const mod = SECTION_META[sectionId]?.moduleId;
    const next = mod ? `#${mod}/${sectionId}` : `#${sectionId}`;
    if (location.hash !== next) history.replaceState(null, "", next);
  }

  function goToSection(sectionId, push = true) {
    if (!SECTION_META[sectionId] || !canAccessSection(sectionId)) return;
    currentSection = sectionId;
    const mod = SECTION_META[sectionId].moduleId;
    if (mod) {
      openModules[mod] = true;
      saveOpenModules();
    }
    if (push) setHash(sectionId);
    renderSidebar();
    if (isAdminMobile()) setAdminNavOpen(false);
    loadSection(false);
  }

  async function loadSection(force) {
    showError("");
    setStatus("Cargando…");
    renderSidebar();
    try {
      if (staffRole === "admin" && (!plans.length || force)) {
        plans = await apiAdmin("/api/admin/plans");
        cache.plans = plans;
      }
      switch (currentSection) {
        case "welcome":
          if (force || !cache.stats) cache.stats = await apiAdmin("/api/admin/stats").catch(() => null);
          break;
        case "overview":
          if (force || !cache.stats) cache.stats = await apiAdmin("/api/admin/stats");
          break;
        case "users": {
          const q = userSearch.trim() ? `&q=${encodeURIComponent(userSearch.trim())}` : "";
          cache.users = await apiAdmin(`/api/admin/users?${pageQuery("users")}${q}`);
          break;
        }
        case "plans":
          cache.plans = await apiAdmin("/api/admin/plans");
          plans = cache.plans;
          break;
        case "subscriptions":
          cache.subscriptions = await apiAdmin(`/api/admin/subscriptions?${pageQuery("subscriptions")}`);
          break;
        case "receipts":
          cache.receipts = await apiAdmin(`/api/admin/billing/receipts?${pageQuery("receipts")}`);
          cache.billingSummary = await apiAdmin("/api/admin/billing/summary");
          break;
        case "refunds":
          cache.refunds = await apiAdmin("/api/admin/refunds");
          break;
        case "analyses":
          cache.analyses = await apiAdmin(`/api/admin/analyses?${pageQuery("analyses")}`);
          break;
        case "chats":
          cache.chats = await apiAdmin(`/api/admin/chats?${pageQuery("chats")}`);
          break;
        case "home-projects":
          cache.homeProjects = await apiAdmin(`/api/admin/home-projects?${pageQuery("home-projects")}`);
          break;
        case "activity":
          cache.activity = await apiAdmin(`/api/admin/activity?${pageQuery("activity")}`);
          break;
        case "guests":
          cache.guestTrials = await apiAdmin(`/api/admin/guest-trials?${pageQuery("guests")}`);
          break;
        case "exports":
          break;
        case "support-inbox": {
          const st = supportFilter ? `&status=${encodeURIComponent(supportFilter)}` : "";
          cache.supportInbox = await apiAdmin(`/api/support/inbox?${pageQuery("support-inbox")}${st}`);
          if (supportSelectedId) {
            cache.supportTicket = await apiAdmin(`/api/support/tickets/${supportSelectedId}`);
          } else {
            cache.supportTicket = null;
          }
          break;
        }
        case "knowledge":
          if (force || !cache.knowledge) cache.knowledge = await apiAdmin("/api/knowledge");
          break;
        case "norms":
          if (force || !cache.norms) cache.norms = await apiAdmin("/api/norms");
          break;
        default:
          break;
      }
      setStatus("");
      renderSection();
    } catch (err) {
      setStatus("");
      showError(err.message || "Error al cargar el panel");
      if (String(err.message || "").includes("401") || String(err.message || "").includes("403")) {
        window.location.href = "/login";
      }
    }
  }

  async function boot() {
    if (!window.PlanoAuth?.getToken()) {
      window.location.href = "/login?next=" + encodeURIComponent("/app/admin");
      return;
    }
    window.ArchitectAccount?.configure?.({
      toast: (msg) => toast(msg),
      onUserUpdated: () => renderSidebar(),
      onOpenPlans: () => {
        if (canAccessSection("plans")) goToSection("plans");
        else window.location.href = "/legacy-app";
      },
    });
    try {
      const me = await window.PlanoAuth.refreshMe?.();
      const role = me?.user?.role || me?.role || window.PlanoAuth.getUser()?.role;
      if (role !== "admin" && role !== "support") {
        showError("Se requiere cuenta administrador o de soporte.");
        setTimeout(() => (window.location.href = "/legacy-app"), 1200);
        return;
      }
      staffRole = role === "support" ? "support" : "admin";
    } catch {
      window.location.href = "/login?next=" + encodeURIComponent("/app/admin");
      return;
    }
    const fromHash = parseHash();
    // Entrada al panel: bienvenida (el resumen antiguo en hash ya no es la home)
    if (fromHash && fromHash !== "overview" && canAccessSection(fromHash)) {
      currentSection = fromHash;
    } else {
      currentSection = staffRole === "support" ? "support-inbox" : "welcome";
      setHash(currentSection);
    }
    bindGlobalEvents();
    await loadSection(true);
  }

  boot();
})();
