(function () {
  const SECTIONS = [
    { id: "overview", label: "Resumen", icon: "dashboard", desc: "Métricas generales" },
    { id: "users", label: "Usuarios", icon: "group", desc: "Cuentas y permisos" },
    { id: "plans", label: "Planes", icon: "payments", desc: "Catálogo y límites" },
    { id: "subscriptions", label: "Suscripciones", icon: "card_membership", desc: "Estado de facturación" },
    { id: "analyses", label: "Análisis", icon: "analytics", desc: "Revisiones de planos" },
    { id: "home-projects", label: "Casa hogar", icon: "home_work", desc: "Proyectos de vivienda" },
    { id: "chats", label: "Chats", icon: "forum", desc: "Conversaciones" },
    { id: "activity", label: "Actividad", icon: "history", desc: "Auditoría casa hogar" },
    { id: "system", label: "Sistema", icon: "settings", desc: "Invitados y uso" },
  ];

  const sidebarEl = document.getElementById("adminSidebar");
  const sectionRoot = document.getElementById("adminSectionRoot");
  const statusEl = document.getElementById("adminStatus");
  const errorEl = document.getElementById("adminError");
  const refreshBtn = document.getElementById("btnAdminRefresh");

  let currentSection = "overview";
  let plans = [];
  let busyId = null;
  let userSearch = "";
  let userSearchTimer = null;

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
  };

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

  function formatDate(value) {
    if (!value) return "—";
    try {
      return new Date(value).toLocaleString();
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

  function formatBillingSource(customerId, subscriptionId) {
    const cid = String(customerId || "");
    const sid = String(subscriptionId || "");
    if (cid.startsWith("demo_cus_") || sid.startsWith("demo_sub_")) return "Pasarela demo";
    if (cid && !cid.startsWith("demo_")) return "Externo";
    return "Manual";
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

  function statusBadge(value, map) {
    const label = map[value] || value;
    return `<span class="admin-badge admin-badge--${escapeHtml(value)}">${escapeHtml(label)}</span>`;
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

  function renderSidebar() {
    if (!sidebarEl) return;
    sidebarEl.innerHTML = `
      <p class="admin-sidebar-kicker">Apartados</p>
      <nav class="admin-nav">
        ${SECTIONS.map(
          (s) => `
          <button type="button" class="admin-nav-item${currentSection === s.id ? " is-active" : ""}" data-section="${s.id}">
            <span class="material-symbols-outlined">${s.icon}</span>
            <span class="admin-nav-copy">
              <strong>${s.label}</strong>
              <small>${s.desc}</small>
            </span>
          </button>`
        ).join("")}
      </nav>`;
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

  function statCards(items) {
    return `<div class="admin-stats-grid">${items
      .map(
        ([label, value]) =>
          `<article class="admin-stat-card"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></article>`
      )
      .join("")}</div>`;
  }

  function pct(part, total) {
    const p = Number(part) || 0;
    const t = Number(total) || 0;
    if (!t) return 0;
    return Math.round((p / t) * 100);
  }

  function planAccent(slug) {
    const map = {
      free: "muted",
      starter: "blue",
      pro: "violet",
      enterprise: "gold",
    };
    return map[slug] || "muted";
  }

  function isoDate(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
  }

  function defaultReportRange() {
    const to = new Date();
    const from = new Date(to.getFullYear(), to.getMonth(), 1);
    return { from: isoDate(from), to: isoDate(to) };
  }

  function renderExportCard() {
    const range = defaultReportRange();
    return `
      <section class="admin-export-card">
        <div class="admin-export-head">
          <div>
            <h3>Descargar resumen por período</h3>
            <p>Exporta métricas, usuarios, análisis y actividad filtrados por fechas.</p>
          </div>
          <span class="material-symbols-outlined admin-export-icon">download</span>
        </div>
        <div class="admin-export-form">
          <label class="admin-export-field">
            <span>Desde</span>
            <input type="date" id="adminReportFrom" value="${range.from}" />
          </label>
          <label class="admin-export-field">
            <span>Hasta</span>
            <input type="date" id="adminReportTo" value="${range.to}" />
          </label>
          <div class="admin-export-actions">
            <button type="button" class="btn-secondary admin-export-btn" data-export-report="csv" title="Compatible con Excel">
              <span class="material-symbols-outlined">table</span>
              CSV (Excel)
            </button>
            <button type="button" class="btn-secondary admin-export-btn" data-export-report="pdf">
              <span class="material-symbols-outlined">picture_as_pdf</span>
              PDF
            </button>
          </div>
        </div>
        <div class="admin-export-presets">
          <span>Atajos:</span>
          <button type="button" class="admin-preset-btn" data-report-preset="month">Mes actual</button>
          <button type="button" class="admin-preset-btn" data-report-preset="last7">Últimos 7 días</button>
          <button type="button" class="admin-preset-btn" data-report-preset="last30">Últimos 30 días</button>
          <button type="button" class="admin-preset-btn" data-report-preset="last90">Últimos 90 días</button>
        </div>
        <p id="adminExportStatus" class="admin-export-status" aria-live="polite"></p>
      </section>`;
  }

  function applyReportPreset(preset) {
    const fromEl = document.getElementById("adminReportFrom");
    const toEl = document.getElementById("adminReportTo");
    if (!fromEl || !toEl) return;
    const to = new Date();
    let from = new Date();
    if (preset === "month") {
      from = new Date(to.getFullYear(), to.getMonth(), 1);
    } else if (preset === "last7") {
      from.setDate(to.getDate() - 6);
    } else if (preset === "last30") {
      from.setDate(to.getDate() - 29);
    } else if (preset === "last90") {
      from.setDate(to.getDate() - 89);
    }
    fromEl.value = isoDate(from);
    toEl.value = isoDate(to);
  }

  async function downloadSummaryReport(format) {
    const fromEl = document.getElementById("adminReportFrom");
    const toEl = document.getElementById("adminReportTo");
    const statusEl = document.getElementById("adminExportStatus");
    if (!fromEl?.value || !toEl?.value) {
      showError("Selecciona fecha inicial y final.");
      return;
    }
    if (fromEl.value > toEl.value) {
      showError("La fecha final debe ser posterior a la inicial.");
      return;
    }
    showError("");
    if (statusEl) statusEl.textContent = "Generando archivo…";
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
      if (statusEl) statusEl.textContent = `Descarga lista: ${filename}`;
      toast(`Resumen exportado (${format.toUpperCase()})`);
    } catch (err) {
      if (statusEl) statusEl.textContent = "";
      showError(err.message || "No se pudo exportar el resumen");
    }
  }

  function kpiCard(icon, label, value, meta, accent = "default") {
    return `
      <article class="admin-kpi admin-kpi--${accent}">
        <div class="admin-kpi-icon"><span class="material-symbols-outlined">${icon}</span></div>
        <div class="admin-kpi-body">
          <span class="admin-kpi-label">${escapeHtml(label)}</span>
          <strong class="admin-kpi-value">${escapeHtml(value)}</strong>
          ${meta ? `<small class="admin-kpi-meta">${meta}</small>` : ""}
        </div>
      </article>`;
  }

  function renderOverview() {
    const s = cache.stats;
    if (!s) return "<p>Cargando resumen…</p>";

    const activePct = pct(s.users_active, s.users);
    const realAnalyses = s.analyses_real ?? Math.max((s.analyses_total || 0) - (s.analyses_demo || 0), 0);
    const trainingPct = pct(s.analyses_training_eligible, s.analyses_total);
    const maxPlanSubs = Math.max(
      1,
      ...(s.plans_breakdown || []).map((p) => p.subscribers || 0)
    );

    const planBars = (s.plans_breakdown || [])
      .map((p) => {
        const width = Math.max(6, Math.round(((p.subscribers || 0) / maxPlanSubs) * 100));
        return `
          <div class="admin-plan-bar-row">
            <div class="admin-plan-bar-head">
              <span>${escapeHtml(p.name)}</span>
              <strong>${p.subscribers ?? 0} <small>(${p.share_pct ?? 0}%)</small></strong>
            </div>
            <div class="admin-plan-bar-track">
              <div class="admin-plan-bar-fill admin-plan-bar-fill--${planAccent(p.slug)}" style="width:${width}%"></div>
            </div>
          </div>`;
      })
      .join("");

    const recentUsers = (s.recent_users || [])
      .map(
        (u) => `
        <li class="admin-mini-item">
          <div>
            <strong>${escapeHtml(u.email)}</strong>
            <small>${u.oauth_provider === "google" ? "Google" : "Email"} · ${escapeHtml(u.role)}</small>
          </div>
          <time>${formatDate(u.created_at)}</time>
        </li>`
      )
      .join("");

    const recentAnalyses = (s.recent_analyses || [])
      .map(
        (a) => `
        <li class="admin-mini-item">
          <div>
            <strong>${escapeHtml(a.original_filename || "Plano")}</strong>
            <small>${escapeHtml(a.user_email || "—")} · ${a.is_demo_model ? "Demo" : "Real"}</small>
          </div>
          <time>${formatDate(a.created_at)}</time>
        </li>`
      )
      .join("");

    const recentActivity = (s.recent_activity || [])
      .map(
        (e) => `
        <li class="admin-mini-item admin-mini-item--activity">
          <div>
            <strong>${escapeHtml(eventLabel(e.event_type))}</strong>
            <small>${escapeHtml(e.project_name || e.project_id || "—")} · ${escapeHtml(e.actor_email || "Sistema")}</small>
          </div>
          <time>${formatDate(e.created_at)}</time>
        </li>`
      )
      .join("");

    const snapshot = [
      ["Chats", s.chats],
      ["Mensajes", s.messages],
      ["Invitados sin cuenta", s.guest_trials],
      ["Análisis invitados", s.guest_trial_analyses],
      ["Docs casa hogar", s.home_documents],
      ["Eventos auditoría", s.home_events],
      ["Proyectos completados", s.home_projects_completed],
      ["Admins", s.users_admin],
    ];

    return `
      <div class="admin-overview">
        <header class="admin-overview-head">
          <div>
            ${sectionHead("Resumen", "Panorama operativo de la plataforma en tiempo real.")}
          </div>
          <div class="admin-period-badge">
            <span class="material-symbols-outlined">calendar_month</span>
            Período <strong>${escapeHtml(s.period_key)}</strong>
          </div>
        </header>

        ${renderExportCard()}

        <div class="admin-kpi-grid">
          ${kpiCard(
            "group",
            "Usuarios activos",
            s.users_active ?? 0,
            `${activePct}% del total · +${s.users_new_7d ?? 0} esta semana`,
            "users"
          )}
          ${kpiCard(
            "analytics",
            "Análisis este mes",
            s.analyses_this_month ?? 0,
            `${s.analyses_total ?? 0} históricos · ${realAnalyses} con modelo real`,
            "analyses"
          )}
          ${kpiCard(
            "home_work",
            "Proyectos activos",
            s.home_projects_active ?? 0,
            `${s.home_projects ?? 0} totales · ${s.home_projects_completed ?? 0} completados`,
            "home"
          )}
          ${kpiCard(
            "payments",
            "Planes de pago",
            s.paid_subscribers ?? 0,
            `${s.subscriptions_active ?? 0} suscripciones activas`,
            "billing"
          )}
        </div>

        <div class="admin-overview-panels">
          <section class="admin-panel-card">
            <div class="admin-panel-card-head">
              <h3>Distribución por plan</h3>
              <button type="button" class="admin-link-btn" data-goto-section="plans">Ver planes</button>
            </div>
            <div class="admin-plan-bars">${planBars || '<p class="admin-hint">Sin planes configurados.</p>'}</div>
          </section>

          <section class="admin-panel-card">
            <div class="admin-panel-card-head">
              <h3>Indicadores clave</h3>
            </div>
            <ul class="admin-snapshot-list">
              ${snapshot
                .map(
                  ([label, value]) =>
                    `<li><span>${escapeHtml(label)}</span><strong>${escapeHtml(value ?? 0)}</strong></li>`
                )
                .join("")}
            </ul>
            <div class="admin-meter-block">
              <div class="admin-meter-head">
                <span>Elegibles para entrenamiento</span>
                <strong>${trainingPct}%</strong>
              </div>
              <div class="admin-meter-track">
                <div class="admin-meter-fill" style="width:${trainingPct}%"></div>
              </div>
              <small>${s.analyses_training_eligible ?? 0} de ${s.analyses_total ?? 0} análisis</small>
            </div>
            <div class="admin-meter-block">
              <div class="admin-meter-head">
                <span>Registro con Google</span>
                <strong>${pct(s.users_google, s.users)}%</strong>
              </div>
              <div class="admin-meter-track">
                <div class="admin-meter-fill admin-meter-fill--blue" style="width:${pct(s.users_google, s.users)}%"></div>
              </div>
              <small>${s.users_google ?? 0} Google · ${s.users_email ?? 0} correo</small>
            </div>
          </section>
        </div>

        <div class="admin-overview-panels">
          <section class="admin-panel-card">
            <div class="admin-panel-card-head">
              <h3>Últimos registros</h3>
              <button type="button" class="admin-link-btn" data-goto-section="users">Ver usuarios</button>
            </div>
            <ul class="admin-mini-list">${recentUsers || '<li class="admin-mini-empty">Sin registros recientes</li>'}</ul>
          </section>

          <section class="admin-panel-card">
            <div class="admin-panel-card-head">
              <h3>Últimos análisis</h3>
              <button type="button" class="admin-link-btn" data-goto-section="analyses">Ver análisis</button>
            </div>
            <ul class="admin-mini-list">${recentAnalyses || '<li class="admin-mini-empty">Sin análisis recientes</li>'}</ul>
          </section>
        </div>

        <section class="admin-panel-card">
          <div class="admin-panel-card-head">
            <h3>Actividad reciente en casa hogar</h3>
            <button type="button" class="admin-link-btn" data-goto-section="activity">Ver todo</button>
          </div>
          <ul class="admin-mini-list admin-mini-list--wide">${recentActivity || '<li class="admin-mini-empty">Sin actividad reciente</li>'}</ul>
        </section>

        <nav class="admin-quick-nav" aria-label="Accesos rápidos">
          <button type="button" class="admin-quick-btn" data-goto-section="users"><span class="material-symbols-outlined">group</span>Usuarios</button>
          <button type="button" class="admin-quick-btn" data-goto-section="subscriptions"><span class="material-symbols-outlined">card_membership</span>Suscripciones</button>
          <button type="button" class="admin-quick-btn" data-goto-section="analyses"><span class="material-symbols-outlined">analytics</span>Análisis</button>
          <button type="button" class="admin-quick-btn" data-goto-section="home-projects"><span class="material-symbols-outlined">home_work</span>Casa hogar</button>
          <button type="button" class="admin-quick-btn" data-goto-section="chats"><span class="material-symbols-outlined">forum</span>Chats</button>
          <button type="button" class="admin-quick-btn" data-goto-section="system"><span class="material-symbols-outlined">settings</span>Sistema</button>
        </nav>
      </div>`;
  }

  function planOptions(selected) {
    if (!plans.length) {
      return `<option value="${selected || "free"}">${selected || "free"}</option>`;
    }
    return plans
      .map(
        (p) =>
          `<option value="${p.slug}"${p.slug === selected ? " selected" : ""}>${escapeHtml(p.name)}</option>`
      )
      .join("");
  }

  function renderUsers() {
    const data = cache.users;
    if (!data) return "<p>Cargando usuarios…</p>";
    const users = data.items || [];
    const total = data.total || users.length;
    return `
      ${sectionHead("Usuarios", "Gestiona cuentas, planes, roles y acceso.")}
      <div class="admin-toolbar">
        <input type="search" class="admin-search" id="adminUserSearch" placeholder="Buscar por correo o nombre…" value="${escapeHtml(userSearch)}" />
        <span class="admin-toolbar-meta">${total} cuenta(s)</span>
      </div>
      <div class="admin-table-wrap">
        <table class="admin-table">
          <thead>
            <tr>
              <th>ID</th><th>Correo</th><th>Nombre</th><th>Plan</th><th>Uso mes</th>
              <th>Rol</th><th>Acceso</th><th>Proveedor</th><th>Alta</th><th></th>
            </tr>
          </thead>
          <tbody>
            ${users
              .map(
                (u) => `
              <tr data-user-id="${u.id}">
                <td>${u.id}</td>
                <td>${escapeHtml(u.email)}</td>
                <td>${escapeHtml(u.full_name || "—")}</td>
                <td>
                  <select class="admin-select" data-action="plan" ${busyId === u.id ? "disabled" : ""}>
                    ${planOptions(u.plan_slug || "free")}
                  </select>
                </td>
                <td>${u.analyses_used ?? 0}${u.analyses_limit != null ? ` / ${u.analyses_limit}` : ""}</td>
                <td>
                  <select class="admin-select" data-action="role" ${busyId === u.id ? "disabled" : ""}>
                    <option value="user"${u.role === "user" ? " selected" : ""}>Usuario</option>
                    <option value="admin"${u.role === "admin" ? " selected" : ""}>Admin</option>
                  </select>
                </td>
                <td>
                  <label class="admin-toggle">
                    <input type="checkbox" data-action="active" ${u.is_active ? "checked" : ""} ${busyId === u.id ? "disabled" : ""} />
                    ${u.is_active ? "Activo" : "Inactivo"}
                  </label>
                </td>
                <td>${u.oauth_provider === "google" ? "Google" : "Email"}</td>
                <td>${formatDate(u.created_at)}</td>
                <td class="admin-row-actions">
                  <button type="button" class="admin-icon-btn" data-action="reset-usage" title="Reiniciar uso del mes" ${busyId === u.id ? "disabled" : ""}>
                    <span class="material-symbols-outlined">restart_alt</span>
                  </button>
                  <button type="button" class="admin-delete-btn" data-action="delete" title="Eliminar usuario" ${busyId === u.id ? "disabled" : ""}>
                    <span class="material-symbols-outlined">delete</span>
                  </button>
                </td>
              </tr>`
              )
              .join("")}
          </tbody>
        </table>
      </div>`;
  }

  function renderPlans() {
    const items = cache.plans;
    if (!items) return "<p>Cargando planes…</p>";
    return `
      ${sectionHead("Planes", "Catálogo de suscripción, límites y suscriptores por plan.")}
      <div class="admin-cards-grid">
        ${items
          .map(
            (p) => `
          <article class="admin-plan-card">
            <div class="admin-plan-card-head">
              <h3>${escapeHtml(p.name)}</h3>
              <span class="admin-plan-price">${formatMoney(p.price_monthly_cents)}<small>/mes</small></span>
            </div>
            <p class="admin-plan-desc">${escapeHtml(p.description || "—")}</p>
            <ul class="admin-plan-meta">
              <li><strong>${p.analyses_limit_monthly}</strong> análisis / mes</li>
              <li>Hasta <strong>${p.max_file_mb} MB</strong> por archivo</li>
              <li>Modelo real: <strong>${p.allow_real_model ? "Sí" : "No"}</strong></li>
              <li>Visible en landing: <strong>${p.is_public ? "Sí" : "No"}</strong></li>
              <li>Suscriptores: <strong>${p.subscribers ?? 0}</strong></li>
            </ul>
            <code class="admin-plan-slug">${escapeHtml(p.slug)}</code>
          </article>`
          )
          .join("")}
      </div>`;
  }

  function renderTableOnly(columns, rows) {
    return `
      <div class="admin-table-wrap">
        <table class="admin-table admin-table--compact">
          <thead><tr>${columns.map((c) => `<th>${c}</th>`).join("")}</tr></thead>
          <tbody>${rows || '<tr><td colspan="99">Sin registros</td></tr>'}</tbody>
        </table>
      </div>`;
  }

  function renderTableSection(title, subtitle, columns, rows, total) {
    return `
      ${sectionHead(title, subtitle)}
      <p class="admin-toolbar-meta">${total ?? rows.length} registro(s)</p>
      ${renderTableOnly(columns, rows)}`;
  }

  function renderSubscriptions() {
    const data = cache.subscriptions;
    if (!data) return "<p>Cargando suscripciones…</p>";
    const rows = (data.items || [])
      .map(
        (s) => `
        <tr>
          <td>${s.id}</td>
          <td>${escapeHtml(s.user_email || "—")}</td>
          <td>${escapeHtml(s.plan_name || s.plan_slug || "—")}</td>
          <td>${statusBadge(s.status, subStatusMap)}</td>
          <td>${formatDate(s.current_period_end)}</td>
          <td>${formatBillingSource(s.stripe_customer_id, s.stripe_subscription_id)}</td>
        </tr>`
      )
      .join("");
    return renderTableSection(
      "Suscripciones",
      "Estado de planes asignados y períodos de facturación.",
      ["ID", "Usuario", "Plan", "Estado", "Fin período", "Origen"],
      rows,
      data.total
    );
  }

  function renderAnalyses() {
    const data = cache.analyses;
    if (!data) return "<p>Cargando análisis…</p>";
    const rows = (data.items || [])
      .map(
        (a) => `
        <tr>
          <td>${a.id}</td>
          <td>${escapeHtml(a.user_email || "—")}</td>
          <td>${escapeHtml(a.original_filename)}</td>
          <td>${a.is_demo_model ? "Demo" : "Real"}</td>
          <td>${a.training_eligible ? "Sí" : "No"}</td>
          <td>${escapeHtml(a.status_text || "—")}</td>
          <td>${formatDate(a.created_at)}</td>
        </tr>`
      )
      .join("");
    return renderTableSection(
      "Análisis de planos",
      "Historial global de revisiones en el workspace.",
      ["ID", "Usuario", "Archivo", "Modelo", "Entrenamiento", "Estado", "Fecha"],
      rows,
      data.total
    );
  }

  function renderHomeProjects() {
    const data = cache.homeProjects;
    if (!data) return "<p>Cargando proyectos…</p>";
    const rows = (data.items || [])
      .map(
        (p) => `
        <tr>
          <td><code>${escapeHtml(p.id.slice(0, 8))}…</code></td>
          <td>${escapeHtml(p.name)}</td>
          <td>${escapeHtml(p.client_name || "—")}</td>
          <td>${escapeHtml(p.owner_email || "—")}</td>
          <td>${statusBadge(p.status, projectStatusMap)}</td>
          <td>Etapa ${p.current_stage}</td>
          <td>${p.documents_count ?? 0}</td>
          <td>${formatDate(p.updated_at)}</td>
        </tr>`
      )
      .join("");
    return renderTableSection(
      "Proyectos casa hogar",
      "Viviendas gestionadas con metodología de 9 etapas.",
      ["ID", "Proyecto", "Cliente", "Propietario", "Estado", "Etapa", "Docs", "Actualizado"],
      rows,
      data.total
    );
  }

  function renderChats() {
    const data = cache.chats;
    if (!data) return "<p>Cargando chats…</p>";
    const rows = (data.items || [])
      .map(
        (c) => `
        <tr>
          <td><code>${escapeHtml(c.id.slice(0, 8))}…</code></td>
          <td>${escapeHtml(c.user_email || "—")}</td>
          <td>${escapeHtml(c.title || "—")}</td>
          <td>${c.messages_count ?? 0}</td>
          <td>${formatDate(c.updated_at)}</td>
        </tr>`
      )
      .join("");
    return renderTableSection(
      "Chats",
      "Conversaciones del workspace y mensajes asociados.",
      ["ID", "Usuario", "Título", "Mensajes", "Actualizado"],
      rows,
      data.total
    );
  }

  function renderActivity() {
    const data = cache.activity;
    if (!data) return "<p>Cargando actividad…</p>";
    const rows = (data.items || [])
      .map(
        (e) => `
        <tr>
          <td>${formatDate(e.created_at)}</td>
          <td>${escapeHtml(e.project_name || e.project_id || "—")}</td>
          <td>${escapeHtml(eventLabel(e.event_type))}</td>
          <td>${escapeHtml(e.actor_email || "Sistema")}</td>
        </tr>`
      )
      .join("");
    return renderTableSection(
      "Actividad y auditoría",
      "Eventos recientes en proyectos casa hogar.",
      ["Fecha", "Proyecto", "Evento", "Actor"],
      rows,
      data.total
    );
  }

  function renderSystem() {
    const s = cache.stats;
    const g = cache.guestTrials;
    if (!s || !g) return "<p>Cargando sistema…</p>";
    const rows = (g.items || [])
      .map(
        (t) => `
        <tr>
          <td><code>${escapeHtml(t.id.slice(0, 8))}…</code></td>
          <td>${t.analyses_count ?? 0}</td>
          <td>${t.asks_count ?? 0}</td>
          <td>${formatDate(t.last_seen_at)}</td>
        </tr>`
      )
      .join("");
    return `
      ${sectionHead("Sistema", "Uso sin cuenta, invitados y métricas de plataforma.")}
      ${statCards([
        ["Sesiones invitado", s.guest_trials],
        ["Análisis invitados (total)", g.totals?.analyses ?? 0],
        ["Preguntas invitados (total)", g.totals?.asks ?? 0],
        ["Período actual", s.period_key],
      ])}
      <div class="admin-subsection">
        <h3>Últimas sesiones de invitado</h3>
        <p class="admin-toolbar-meta">${g.total ?? 0} registro(s)</p>
        ${renderTableOnly(
          ["ID", "Análisis", "Preguntas", "Última visita"],
          rows
        )}
      </div>`;
  }

  const renderers = {
    overview: renderOverview,
    users: renderUsers,
    plans: renderPlans,
    subscriptions: renderSubscriptions,
    analyses: renderAnalyses,
    "home-projects": renderHomeProjects,
    chats: renderChats,
    activity: renderActivity,
    system: renderSystem,
  };

  function renderSection() {
    renderSidebar();
    const render = renderers[currentSection];
    if (sectionRoot && render) {
      sectionRoot.innerHTML = `<section class="admin-section">${render()}</section>`;
    }
  }

  async function loadSectionData(section) {
    switch (section) {
      case "overview":
        cache.stats = await apiAdmin("/api/admin/stats");
        break;
      case "users": {
        const q = userSearch.trim() ? `&q=${encodeURIComponent(userSearch.trim())}` : "";
        cache.users = await apiAdmin(`/api/admin/users?limit=100${q}`);
        cache.plans = await apiAdmin("/api/admin/plans");
        plans = cache.plans;
        break;
      }
      case "plans":
        cache.plans = await apiAdmin("/api/admin/plans");
        plans = cache.plans;
        break;
      case "subscriptions":
        cache.subscriptions = await apiAdmin("/api/admin/subscriptions?limit=100");
        break;
      case "analyses":
        cache.analyses = await apiAdmin("/api/admin/analyses?limit=80");
        break;
      case "home-projects":
        cache.homeProjects = await apiAdmin("/api/admin/home-projects?limit=80");
        break;
      case "chats":
        cache.chats = await apiAdmin("/api/admin/chats?limit=80");
        break;
      case "activity":
        cache.activity = await apiAdmin("/api/admin/activity?limit=100");
        break;
      case "system":
        cache.stats = await apiAdmin("/api/admin/stats");
        cache.guestTrials = await apiAdmin("/api/admin/guest-trials?limit=50");
        break;
      default:
        break;
    }
  }

  async function navigate(section) {
    if (!SECTIONS.some((s) => s.id === section)) return;
    currentSection = section;
    showError("");
    setStatus("Cargando…");
    try {
      await loadSectionData(section);
      renderSection();
      setStatus("");
      if (history.replaceState) {
        history.replaceState(null, "", `/app/admin#${section}`);
      }
    } catch (err) {
      showError(err.message || "No se pudo cargar el apartado");
      setStatus("");
    }
  }

  async function refreshCurrent() {
    await navigate(currentSection);
  }

  function toast(msg) {
    window.showToast?.(msg);
  }

  async function patchUser(userId, payload) {
    busyId = userId;
    showError("");
    try {
      await apiAdmin(`/api/admin/users/${userId}`, {
        method: "PATCH",
        body: JSON.stringify(payload),
      });
      await loadSectionData("users");
      renderSection();
      toast("Usuario actualizado");
    } catch (err) {
      showError(err.message || "No se pudo guardar");
    } finally {
      busyId = null;
    }
  }

  async function changePlan(userId, planSlug) {
    busyId = userId;
    showError("");
    try {
      await apiAdmin(`/api/admin/users/${userId}/plan`, {
        method: "POST",
        body: JSON.stringify({ plan_slug: planSlug }),
      });
      await loadSectionData("users");
      renderSection();
      toast("Plan actualizado");
    } catch (err) {
      showError(err.message || "No se pudo cambiar el plan");
    } finally {
      busyId = null;
    }
  }

  async function resetUsage(userId) {
    busyId = userId;
    showError("");
    try {
      await apiAdmin(`/api/admin/users/${userId}/reset-usage`, { method: "POST" });
      await loadSectionData("users");
      renderSection();
      toast("Uso del mes reiniciado");
    } catch (err) {
      showError(err.message || "No se pudo reiniciar el uso");
    } finally {
      busyId = null;
    }
  }

  async function deleteUser(userId, email) {
    if (
      !(await PlanoDialog.confirm(
        `¿Eliminar a ${email}? Se borrarán sus chats, análisis y proyectos.`,
        { title: "Eliminar usuario", variant: "danger", confirmLabel: "Eliminar" }
      ))
    ) {
      return;
    }
    busyId = userId;
    showError("");
    try {
      await apiAdmin(`/api/admin/users/${userId}`, { method: "DELETE" });
      await loadSectionData("users");
      renderSection();
      toast("Usuario eliminado");
    } catch (err) {
      showError(err.message || "No se pudo eliminar");
    } finally {
      busyId = null;
    }
  }

  sidebarEl?.addEventListener("click", (event) => {
    const btn = event.target.closest("[data-section]");
    if (!btn || busyId) return;
    navigate(btn.dataset.section);
  });

  sectionRoot?.addEventListener("change", (event) => {
    const target = event.target;
    const row = target.closest("tr[data-user-id]");
    if (!row || busyId) return;
    const userId = Number(row.dataset.userId);
    const action = target.dataset.action;
    if (action === "role") patchUser(userId, { role: target.value });
    if (action === "plan") changePlan(userId, target.value);
    if (action === "active") patchUser(userId, { is_active: target.checked });
  });

  sectionRoot?.addEventListener("click", (event) => {
    const exportBtn = event.target.closest("[data-export-report]");
    if (exportBtn && !busyId) {
      downloadSummaryReport(exportBtn.dataset.exportReport);
      return;
    }
    const presetBtn = event.target.closest("[data-report-preset]");
    if (presetBtn) {
      applyReportPreset(presetBtn.dataset.reportPreset);
      return;
    }

    const goto = event.target.closest("[data-goto-section]");
    if (goto && !busyId) {
      navigate(goto.dataset.gotoSection);
      return;
    }

    const btn = event.target.closest("[data-action]");
    if (!btn || busyId) return;
    const row = btn.closest("tr[data-user-id]");
    if (!row) return;
    const userId = Number(row.dataset.userId);
    const email = row.children[1]?.textContent || "usuario";
    if (btn.dataset.action === "delete") deleteUser(userId, email);
    if (btn.dataset.action === "reset-usage") resetUsage(userId);
  });

  sectionRoot?.addEventListener("input", (event) => {
    if (event.target.id !== "adminUserSearch") return;
    userSearch = event.target.value;
    clearTimeout(userSearchTimer);
    userSearchTimer = setTimeout(() => {
      if (currentSection === "users") {
        loadSectionData("users")
          .then(() => renderSection())
          .catch((err) => showError(err.message || "Error al buscar"));
      }
    }, 320);
  });

  refreshBtn?.addEventListener("click", () => {
    refreshCurrent()
      .then(() => toast("Panel actualizado"))
      .catch((err) => showError(err.message || "Error al cargar"));
  });

  function initialSection() {
    const hash = (window.location.hash || "").replace(/^#/, "");
    return SECTIONS.some((s) => s.id === hash) ? hash : "overview";
  }

  async function boot() {
    if (!window.PlanoAuth?.getToken()) {
      window.location.href = "/login?next=/app/admin";
      return;
    }
    try {
      const me = await window.PlanoAuth.refreshMe();
      if (!me?.user || me.user.role !== "admin") {
        window.location.href = "/legacy-app";
        return;
      }
      await navigate(initialSection());
    } catch (err) {
      showError(err.message || "No se pudo cargar el panel");
      setStatus("");
    }
  }

  boot();
})();
