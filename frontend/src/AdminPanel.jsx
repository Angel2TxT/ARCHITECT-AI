import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  Activity,
  BarChart3,
  CreditCard,
  Download,
  FileText,
  Home,
  LayoutDashboard,
  Loader2,
  MessageSquare,
  RefreshCw,
  Settings,
  Shield,
  Trash2,
  Users,
} from "lucide-react";

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

const TOKEN_KEY = "plano_ia_token";

const SECTIONS = [
  { id: "overview", label: "Resumen", icon: LayoutDashboard },
  { id: "users", label: "Usuarios", icon: Users },
  { id: "plans", label: "Planes", icon: CreditCard },
  { id: "subscriptions", label: "Suscripciones", icon: CreditCard },
  { id: "receipts", label: "Comprobantes", icon: FileText },
  { id: "analyses", label: "Análisis", icon: BarChart3 },
  { id: "home-projects", label: "Casa hogar", icon: Home },
  { id: "chats", label: "Chats", icon: MessageSquare },
  { id: "activity", label: "Actividad", icon: Activity },
  { id: "system", label: "Sistema", icon: Settings },
];

async function apiFetch(url, options = {}) {
  const headers = { ...(options.headers || {}) };
  const token = localStorage.getItem(TOKEN_KEY);
  if (token) headers.Authorization = `Bearer ${token}`;
  if (options.body && !(options.body instanceof FormData)) {
    headers["Content-Type"] = headers["Content-Type"] || "application/json";
  }
  const res = await fetch(url, { ...options, headers });
  if (res.status === 401) {
    window.location.href = "/login";
    throw new Error("Sesión expirada");
  }
  if (res.status === 403) throw new Error("Solo administradores");
  return res;
}

function StatCard({ label, value }) {
  return (
    <article className="admin-stat">
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  );
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

function pct(part, total) {
  const p = Number(part) || 0;
  const t = Number(total) || 0;
  if (!t) return 0;
  return Math.round((p / t) * 100);
}

function planAccent(slug) {
  const map = { free: "muted", starter: "blue", pro: "violet", enterprise: "gold" };
  return map[slug] || "muted";
}

function KpiCard({ icon: Icon, label, value, meta, accent = "default" }) {
  return (
    <article className={`admin-kpi admin-kpi--${accent}`}>
      <div className="admin-kpi-icon">
        <Icon size={18} />
      </div>
      <div className="admin-kpi-body">
        <span className="admin-kpi-label">{label}</span>
        <strong className="admin-kpi-value">{value}</strong>
        {meta && <small className="admin-kpi-meta">{meta}</small>}
      </div>
    </article>
  );
}

const EVENT_LABELS = {
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

export default function AdminPanel() {
  const [section, setSection] = useState("overview");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [busyId, setBusyId] = useState(null);
  const [userSearch, setUserSearch] = useState("");

  const [stats, setStats] = useState(null);
  const [users, setUsers] = useState([]);
  const [usersTotal, setUsersTotal] = useState(0);
  const [plans, setPlans] = useState([]);
  const [subscriptions, setSubscriptions] = useState({ items: [], total: 0 });
  const [analyses, setAnalyses] = useState({ items: [], total: 0 });
  const [homeProjects, setHomeProjects] = useState({ items: [], total: 0 });
  const [chats, setChats] = useState({ items: [], total: 0 });
  const [activity, setActivity] = useState({ items: [], total: 0 });
  const [guestTrials, setGuestTrials] = useState({ items: [], total: 0, totals: {} });
  const [billingReceipts, setBillingReceipts] = useState({ items: [], total: 0 });
  const [billingSummary, setBillingSummary] = useState(null);
  const [reportFrom, setReportFrom] = useState(() => defaultReportRange().from);
  const [reportTo, setReportTo] = useState(() => defaultReportRange().to);
  const [exportStatus, setExportStatus] = useState("");
  const [exporting, setExporting] = useState(false);

  const loadSection = useCallback(async (target, search = "") => {
    setLoading(true);
    setError("");
    try {
      if (target === "overview" || target === "system") {
        const statsRes = await apiFetch("/api/admin/stats");
        if (!statsRes.ok) throw new Error("Error al cargar métricas");
        setStats(await statsRes.json());
      }
      if (target === "users") {
        const q = search.trim() ? `&q=${encodeURIComponent(search.trim())}` : "";
        const [usersRes, plansRes] = await Promise.all([
          apiFetch(`/api/admin/users?limit=100${q}`),
          apiFetch("/api/admin/plans"),
        ]);
        const usersData = await usersRes.json();
        if (!usersRes.ok) throw new Error(usersData.detail || "Error usuarios");
        setUsers(usersData.items || []);
        setUsersTotal(usersData.total || 0);
        if (plansRes.ok) setPlans(await plansRes.json());
      }
      if (target === "plans") {
        const res = await apiFetch("/api/admin/plans");
        if (!res.ok) throw new Error("Error al cargar planes");
        setPlans(await res.json());
      }
      if (target === "subscriptions") {
        const res = await apiFetch("/api/admin/subscriptions?limit=100");
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || "Error suscripciones");
        setSubscriptions(data);
      }
      if (target === "receipts") {
        const [listRes, sumRes] = await Promise.all([
          apiFetch("/api/admin/billing/receipts?limit=100"),
          apiFetch("/api/admin/billing/summary"),
        ]);
        const listData = await listRes.json();
        const sumData = await sumRes.json();
        if (!listRes.ok) throw new Error(listData.detail || "Error comprobantes");
        if (!sumRes.ok) throw new Error(sumData.detail || "Error resumen billing");
        setBillingReceipts(listData);
        setBillingSummary(sumData);
      }
      if (target === "analyses") {
        const res = await apiFetch("/api/admin/analyses?limit=80");
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || "Error análisis");
        setAnalyses(data);
      }
      if (target === "home-projects") {
        const res = await apiFetch("/api/admin/home-projects?limit=80");
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || "Error proyectos");
        setHomeProjects(data);
      }
      if (target === "chats") {
        const res = await apiFetch("/api/admin/chats?limit=80");
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || "Error chats");
        setChats(data);
      }
      if (target === "activity") {
        const res = await apiFetch("/api/admin/activity?limit=100");
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || "Error actividad");
        setActivity(data);
      }
      if (target === "system") {
        const res = await apiFetch("/api/admin/guest-trials?limit=50");
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || "Error invitados");
        setGuestTrials(data);
      }
    } catch (err) {
      setError(err.message || "Error");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    let cancelled = false;
    const delay = section === "users" && userSearch.trim() ? 320 : 0;
    const timer = setTimeout(() => {
      if (!cancelled) loadSection(section, userSearch);
    }, delay);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [section, userSearch, loadSection]);

  async function patchUser(userId, payload) {
    setBusyId(userId);
    setError("");
    try {
      const res = await apiFetch(`/api/admin/users/${userId}`, {
        method: "PATCH",
        body: JSON.stringify(payload),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || "No se pudo actualizar");
      setUsers((prev) => prev.map((u) => (u.id === userId ? { ...u, ...data } : u)));
    } catch (err) {
      setError(err.message || "Error al guardar");
    } finally {
      setBusyId(null);
    }
  }

  async function changePlan(userId, planSlug) {
    setBusyId(userId);
    setError("");
    try {
      const res = await apiFetch(`/api/admin/users/${userId}/plan`, {
        method: "POST",
        body: JSON.stringify({ plan_slug: planSlug }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || "No se pudo cambiar el plan");
      setUsers((prev) => prev.map((u) => (u.id === userId ? { ...u, ...data } : u)));
    } catch (err) {
      setError(err.message || "Error al cambiar plan");
    } finally {
      setBusyId(null);
    }
  }

  async function resetUsage(userId) {
    setBusyId(userId);
    setError("");
    try {
      const res = await apiFetch(`/api/admin/users/${userId}/reset-usage`, { method: "POST" });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || "No se pudo reiniciar uso");
      setUsers((prev) => prev.map((u) => (u.id === userId ? { ...u, ...data } : u)));
    } catch (err) {
      setError(err.message || "Error al reiniciar uso");
    } finally {
      setBusyId(null);
    }
  }

  async function deleteUser(user) {
    if (
      !window.confirm(
        `¿Eliminar a ${user.email}? Se borrarán sus chats, análisis y proyectos.`
      )
    ) {
      return;
    }
    setBusyId(user.id);
    setError("");
    try {
      const res = await apiFetch(`/api/admin/users/${user.id}`, { method: "DELETE" });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || "No se pudo eliminar");
      setUsers((prev) => prev.filter((u) => u.id !== user.id));
      setUsersTotal((n) => Math.max(0, n - 1));
      await loadSection("users");
    } catch (err) {
      setError(err.message || "Error al eliminar");
    } finally {
      setBusyId(null);
    }
  }

  const sectionTitle = useMemo(
    () => SECTIONS.find((s) => s.id === section)?.label || "Administración",
    [section]
  );

  function applyReportPreset(preset) {
    const to = new Date();
    let from = new Date();
    if (preset === "month") from = new Date(to.getFullYear(), to.getMonth(), 1);
    else if (preset === "last7") from.setDate(to.getDate() - 6);
    else if (preset === "last30") from.setDate(to.getDate() - 29);
    else if (preset === "last90") from.setDate(to.getDate() - 89);
    setReportFrom(isoDate(from));
    setReportTo(isoDate(to));
  }

  async function downloadSummaryReport(format) {
    if (!reportFrom || !reportTo) {
      setError("Selecciona fecha inicial y final.");
      return;
    }
    if (reportFrom > reportTo) {
      setError("La fecha final debe ser posterior a la inicial.");
      return;
    }
    setExporting(true);
    setExportStatus("Generando archivo…");
    setError("");
    try {
      const url = `/api/admin/reports/summary?from=${encodeURIComponent(reportFrom)}&to=${encodeURIComponent(reportTo)}&format=${encodeURIComponent(format)}`;
      const res = await apiFetch(url);
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.detail || `Error (${res.status})`);
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
      setExportStatus(`Descarga lista: ${filename}`);
    } catch (err) {
      setExportStatus("");
      setError(err.message || "No se pudo exportar el resumen");
    } finally {
      setExporting(false);
    }
  }

  function renderExportCard() {
    return (
      <section className="admin-export-card">
        <div className="admin-export-head">
          <div>
            <h3>Descargar resumen por período</h3>
            <p>Exporta métricas, usuarios, análisis y actividad filtrados por fechas.</p>
          </div>
          <Download size={20} className="admin-export-icon" />
        </div>
        <div className="admin-export-form">
          <label className="admin-export-field">
            <span>Desde</span>
            <input
              type="date"
              value={reportFrom}
              onChange={(e) => setReportFrom(e.target.value)}
            />
          </label>
          <label className="admin-export-field">
            <span>Hasta</span>
            <input type="date" value={reportTo} onChange={(e) => setReportTo(e.target.value)} />
          </label>
          <div className="admin-export-actions">
            <button
              type="button"
              className="hp-btn secondary admin-export-btn"
              disabled={exporting}
              onClick={() => downloadSummaryReport("csv")}
            >
              CSV (Excel)
            </button>
            <button
              type="button"
              className="hp-btn secondary admin-export-btn"
              disabled={exporting}
              onClick={() => downloadSummaryReport("pdf")}
            >
              PDF
            </button>
          </div>
        </div>
        <div className="admin-export-presets">
          <span>Atajos:</span>
          <button type="button" className="admin-preset-btn" onClick={() => applyReportPreset("month")}>
            Mes actual
          </button>
          <button type="button" className="admin-preset-btn" onClick={() => applyReportPreset("last7")}>
            Últimos 7 días
          </button>
          <button type="button" className="admin-preset-btn" onClick={() => applyReportPreset("last30")}>
            Últimos 30 días
          </button>
          <button type="button" className="admin-preset-btn" onClick={() => applyReportPreset("last90")}>
            Últimos 90 días
          </button>
        </div>
        {exportStatus && <p className="admin-export-status">{exportStatus}</p>}
      </section>
    );
  }

  function renderOverview() {
    if (!stats) return null;
    const activePct = pct(stats.users_active, stats.users);
    const realAnalyses =
      stats.analyses_real ??
      Math.max((stats.analyses_total || 0) - (stats.analyses_demo || 0), 0);
    const trainingPct = pct(stats.analyses_training_eligible, stats.analyses_total);
    const maxPlanSubs = Math.max(
      1,
      ...(stats.plans_breakdown || []).map((p) => p.subscribers || 0)
    );
    const snapshot = [
      ["Chats", stats.chats],
      ["Mensajes", stats.messages],
      ["Invitados sin cuenta", stats.guest_trials],
      ["Análisis invitados", stats.guest_trial_analyses],
      ["Docs casa hogar", stats.home_documents],
      ["Eventos auditoría", stats.home_events],
      ["Proyectos completados", stats.home_projects_completed],
      ["Admins", stats.users_admin],
    ];

    return (
      <div className="admin-overview">
        <header className="admin-overview-head">
          <div>
            <p className="admin-muted">Panorama operativo de la plataforma en tiempo real.</p>
          </div>
          <div className="admin-period-badge">
            Período <strong>{stats.period_key}</strong>
          </div>
        </header>

        {renderExportCard()}

        <div className="admin-kpi-grid">
          <KpiCard
            icon={Users}
            label="Usuarios activos"
            value={stats.users_active ?? 0}
            meta={`${activePct}% del total · +${stats.users_new_7d ?? 0} esta semana`}
            accent="users"
          />
          <KpiCard
            icon={BarChart3}
            label="Análisis este mes"
            value={stats.analyses_this_month ?? 0}
            meta={`${stats.analyses_total ?? 0} históricos · ${realAnalyses} con modelo real`}
            accent="analyses"
          />
          <KpiCard
            icon={Home}
            label="Proyectos activos"
            value={stats.home_projects_active ?? 0}
            meta={`${stats.home_projects ?? 0} totales · ${stats.home_projects_completed ?? 0} completados`}
            accent="home"
          />
          <KpiCard
            icon={CreditCard}
            label="Planes de pago"
            value={stats.paid_subscribers ?? 0}
            meta={`${stats.subscriptions_active ?? 0} suscripciones activas`}
            accent="billing"
          />
          <KpiCard
            icon={FileText}
            label="Ventas simuladas"
            value={formatMoney(stats.billing_simulated_revenue_cents ?? 0)}
            meta={`${stats.billing_receipts_total ?? 0} comprobantes emitidos`}
            accent="billing"
          />
        </div>

        {(stats.billing_by_plan || []).length > 0 && (
          <div className="admin-overview-panels">
            <section className="admin-panel-card">
              <div className="admin-panel-card-head">
                <h3>Comprobantes por plan (simulado)</h3>
                <button type="button" className="admin-link-btn" onClick={() => setSection("receipts")}>
                  Ver todos
                </button>
              </div>
              <ul className="admin-plan-breakdown">
                {stats.billing_by_plan.map((p) => (
                  <li key={p.plan_slug}>
                    <span>{p.plan_name}</span>
                    <strong>
                      {p.receipts_count} · {formatMoney(p.simulated_revenue_cents)}
                    </strong>
                  </li>
                ))}
              </ul>
            </section>
          </div>
        )}

        <div className="admin-overview-panels">
          <section className="admin-panel-card">
            <div className="admin-panel-card-head">
              <h3>Distribución por plan</h3>
              <button type="button" className="admin-link-btn" onClick={() => setSection("plans")}>
                Ver planes
              </button>
            </div>
            <div className="admin-plan-bars">
              {(stats.plans_breakdown || []).map((p) => {
                const width = Math.max(
                  6,
                  Math.round(((p.subscribers || 0) / maxPlanSubs) * 100)
                );
                return (
                  <div key={p.slug} className="admin-plan-bar-row">
                    <div className="admin-plan-bar-head">
                      <span>{p.name}</span>
                      <strong>
                        {p.subscribers ?? 0} <small>({p.share_pct ?? 0}%)</small>
                      </strong>
                    </div>
                    <div className="admin-plan-bar-track">
                      <div
                        className={`admin-plan-bar-fill admin-plan-bar-fill--${planAccent(p.slug)}`}
                        style={{ width: `${width}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </section>

          <section className="admin-panel-card">
            <div className="admin-panel-card-head">
              <h3>Indicadores clave</h3>
            </div>
            <ul className="admin-snapshot-list">
              {snapshot.map(([label, value]) => (
                <li key={label}>
                  <span>{label}</span>
                  <strong>{value ?? 0}</strong>
                </li>
              ))}
            </ul>
            <div className="admin-meter-block">
              <div className="admin-meter-head">
                <span>Elegibles para entrenamiento</span>
                <strong>{trainingPct}%</strong>
              </div>
              <div className="admin-meter-track">
                <div className="admin-meter-fill" style={{ width: `${trainingPct}%` }} />
              </div>
              <small>
                {stats.analyses_training_eligible ?? 0} de {stats.analyses_total ?? 0} análisis
              </small>
            </div>
          </section>
        </div>

        <div className="admin-overview-panels">
          <section className="admin-panel-card">
            <div className="admin-panel-card-head">
              <h3>Últimos registros</h3>
              <button type="button" className="admin-link-btn" onClick={() => setSection("users")}>
                Ver usuarios
              </button>
            </div>
            <ul className="admin-mini-list">
              {(stats.recent_users || []).map((u) => (
                <li key={u.id} className="admin-mini-item">
                  <div>
                    <strong>{u.email}</strong>
                    <small>
                      {u.oauth_provider === "google" ? "Google" : "Email"} · {u.role}
                    </small>
                  </div>
                  <time>{formatDate(u.created_at)}</time>
                </li>
              ))}
            </ul>
          </section>

          <section className="admin-panel-card">
            <div className="admin-panel-card-head">
              <h3>Últimos análisis</h3>
              <button type="button" className="admin-link-btn" onClick={() => setSection("analyses")}>
                Ver análisis
              </button>
            </div>
            <ul className="admin-mini-list">
              {(stats.recent_analyses || []).map((a) => (
                <li key={a.id} className="admin-mini-item">
                  <div>
                    <strong>{a.original_filename || "Plano"}</strong>
                    <small>
                      {a.user_email || "—"} · {a.is_demo_model ? "Demo" : "Real"}
                    </small>
                  </div>
                  <time>{formatDate(a.created_at)}</time>
                </li>
              ))}
            </ul>
          </section>
        </div>

        <section className="admin-panel-card">
          <div className="admin-panel-card-head">
            <h3>Actividad reciente en casa hogar</h3>
            <button type="button" className="admin-link-btn" onClick={() => setSection("activity")}>
              Ver todo
            </button>
          </div>
          <ul className="admin-mini-list admin-mini-list--wide">
            {(stats.recent_activity || []).map((e) => (
              <li key={e.id} className="admin-mini-item">
                <div>
                  <strong>{EVENT_LABELS[e.event_type] || e.event_type}</strong>
                  <small>
                    {e.project_name || e.project_id} · {e.actor_email || "Sistema"}
                  </small>
                </div>
                <time>{formatDate(e.created_at)}</time>
              </li>
            ))}
          </ul>
        </section>
      </div>
    );
  }

  function renderUsers() {
    return (
      <>
        <div className="admin-toolbar">
          <input
            type="search"
            className="admin-search"
            placeholder="Buscar por correo o nombre…"
            value={userSearch}
            onChange={(e) => setUserSearch(e.target.value)}
          />
          <span className="admin-toolbar-meta">{usersTotal} cuenta(s)</span>
        </div>
        <div className="admin-table-wrap">
          <table className="admin-table">
            <thead>
              <tr>
                <th>ID</th>
                <th>Correo</th>
                <th>Nombre</th>
                <th>Plan</th>
                <th>Uso mes</th>
                <th>Rol</th>
                <th>Acceso</th>
                <th>Proveedor</th>
                <th>Alta</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {users.map((u) => (
                <tr key={u.id}>
                  <td>{u.id}</td>
                  <td>{u.email}</td>
                  <td>{u.full_name || "—"}</td>
                  <td>
                    <select
                      value={u.plan_slug || "free"}
                      disabled={busyId === u.id || !plans.length}
                      onChange={(e) => changePlan(u.id, e.target.value)}
                    >
                      {plans.map((p) => (
                        <option key={p.slug} value={p.slug}>
                          {p.name}
                        </option>
                      ))}
                    </select>
                  </td>
                  <td>
                    {u.analyses_used ?? 0}
                    {u.analyses_limit != null ? ` / ${u.analyses_limit}` : ""}
                  </td>
                  <td>
                    <select
                      value={u.role}
                      disabled={busyId === u.id}
                      onChange={(e) => patchUser(u.id, { role: e.target.value })}
                    >
                      <option value="user">Usuario</option>
                      <option value="admin">Admin</option>
                    </select>
                  </td>
                  <td>
                    <label className="admin-toggle">
                      <input
                        type="checkbox"
                        checked={u.is_active}
                        disabled={busyId === u.id}
                        onChange={(e) => patchUser(u.id, { is_active: e.target.checked })}
                      />
                      {u.is_active ? "Activo" : "Inactivo"}
                    </label>
                  </td>
                  <td>{u.oauth_provider === "google" ? "Google" : "Email"}</td>
                  <td>{formatDate(u.created_at)}</td>
                  <td className="admin-row-actions">
                    <button
                      type="button"
                      className="admin-icon-btn"
                      disabled={busyId === u.id}
                      onClick={() => resetUsage(u.id)}
                      title="Reiniciar uso del mes"
                    >
                      <RefreshCw size={14} />
                    </button>
                    <button
                      type="button"
                      className="admin-delete-btn"
                      disabled={busyId === u.id}
                      onClick={() => deleteUser(u)}
                      title="Eliminar usuario"
                    >
                      <Trash2 size={14} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </>
    );
  }

  function renderPlans() {
    return (
      <div className="admin-cards-grid">
        {plans.map((p) => (
          <article key={p.slug} className="admin-plan-card">
            <div className="admin-plan-card-head">
              <h3>{p.name}</h3>
              <span className="admin-plan-price">
                {formatMoney(p.price_monthly_cents)}
                <small>/mes</small>
              </span>
            </div>
            <p className="admin-plan-desc">{p.description || "—"}</p>
            <ul className="admin-plan-meta">
              <li>
                <strong>{p.analyses_limit_monthly}</strong> análisis / mes
              </li>
              <li>
                Hasta <strong>{p.max_file_mb} MB</strong> por archivo
              </li>
              <li>
                Modelo real: <strong>{p.allow_real_model ? "Sí" : "No"}</strong>
              </li>
              <li>
                Suscriptores: <strong>{p.subscribers ?? 0}</strong>
              </li>
            </ul>
            <code className="admin-plan-slug">{p.slug}</code>
          </article>
        ))}
      </div>
    );
  }

  function renderReceipts() {
    return (
      <>
        <div className="admin-kpi-grid">
          <KpiCard
            icon={FileText}
            label="Comprobantes emitidos"
            value={billingSummary?.receipts_total ?? 0}
            meta="Pasarela simulada (proyecto escolar)"
            accent="billing"
          />
          <KpiCard
            icon={CreditCard}
            label="Ingresos simulados"
            value={billingSummary?.simulated_revenue_label ?? "$0.00 MXN"}
            meta="No representa cobros reales"
            accent="billing"
          />
        </div>

        {(billingSummary?.by_plan || []).length > 0 && (
          <div className="admin-stats-grid admin-stats-grid--compact">
            {billingSummary.by_plan.map((p) => (
              <StatCard
                key={p.plan_slug}
                label={`${p.plan_name} (${p.receipts_count})`}
                value={p.simulated_revenue_label}
              />
            ))}
          </div>
        )}

        <div className="admin-table-wrap">
          <table className="admin-table admin-table--compact">
            <thead>
              <tr>
                <th>Folio</th>
                <th>Usuario</th>
                <th>Plan</th>
                <th>Importe</th>
                <th>Correo</th>
                <th>Fecha</th>
              </tr>
            </thead>
            <tbody>
              {(billingReceipts.items || []).map((r) => (
                <tr key={r.id}>
                  <td>
                    <code>{r.receipt_number}</code>
                  </td>
                  <td>{r.user_email}</td>
                  <td>{r.plan_name}</td>
                  <td>{r.amount_label}</td>
                  <td>
                    {r.email_status === "sent"
                      ? "Enviado"
                      : r.email_status === "not_configured"
                        ? "Sin SMTP"
                        : "Falló"}
                  </td>
                  <td>{formatDate(r.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="admin-muted admin-export-status">
          Total registrados: {billingReceipts.total ?? 0}. Documentos académicos, no factura fiscal.
        </p>
      </>
    );
  }

  function renderContent() {
    if (loading) {
      return (
        <div className="admin-page admin-page--loading">
          <Loader2 className="spin" size={24} />
          <p>Cargando…</p>
        </div>
      );
    }
    switch (section) {
      case "overview":
        return renderOverview();
      case "users":
        return renderUsers();
      case "plans":
        return renderPlans();
      case "subscriptions":
        return (
          <div className="admin-table-wrap">
            <table className="admin-table admin-table--compact">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Usuario</th>
                  <th>Plan</th>
                  <th>Estado</th>
                  <th>Fin período</th>
                </tr>
              </thead>
              <tbody>
                {(subscriptions.items || []).map((s) => (
                  <tr key={s.id}>
                    <td>{s.id}</td>
                    <td>{s.user_email}</td>
                    <td>{s.plan_name}</td>
                    <td>{s.status}</td>
                    <td>{formatDate(s.current_period_end)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        );
      case "receipts":
        return renderReceipts();
      case "analyses":
        return (
          <div className="admin-table-wrap">
            <table className="admin-table admin-table--compact">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Usuario</th>
                  <th>Archivo</th>
                  <th>Modelo</th>
                  <th>Fecha</th>
                </tr>
              </thead>
              <tbody>
                {(analyses.items || []).map((a) => (
                  <tr key={a.id}>
                    <td>{a.id}</td>
                    <td>{a.user_email}</td>
                    <td>{a.original_filename}</td>
                    <td>{a.is_demo_model ? "Demo" : "Real"}</td>
                    <td>{formatDate(a.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        );
      case "home-projects":
        return (
          <div className="admin-table-wrap">
            <table className="admin-table admin-table--compact">
              <thead>
                <tr>
                  <th>Proyecto</th>
                  <th>Cliente</th>
                  <th>Propietario</th>
                  <th>Estado</th>
                  <th>Etapa</th>
                  <th>Docs</th>
                </tr>
              </thead>
              <tbody>
                {(homeProjects.items || []).map((p) => (
                  <tr key={p.id}>
                    <td>{p.name}</td>
                    <td>{p.client_name || "—"}</td>
                    <td>{p.owner_email}</td>
                    <td>{p.status}</td>
                    <td>{p.current_stage}</td>
                    <td>{p.documents_count}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        );
      case "chats":
        return (
          <div className="admin-table-wrap">
            <table className="admin-table admin-table--compact">
              <thead>
                <tr>
                  <th>Usuario</th>
                  <th>Título</th>
                  <th>Mensajes</th>
                  <th>Actualizado</th>
                </tr>
              </thead>
              <tbody>
                {(chats.items || []).map((c) => (
                  <tr key={c.id}>
                    <td>{c.user_email}</td>
                    <td>{c.title}</td>
                    <td>{c.messages_count}</td>
                    <td>{formatDate(c.updated_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        );
      case "activity":
        return (
          <div className="admin-table-wrap">
            <table className="admin-table admin-table--compact">
              <thead>
                <tr>
                  <th>Fecha</th>
                  <th>Proyecto</th>
                  <th>Evento</th>
                  <th>Actor</th>
                </tr>
              </thead>
              <tbody>
                {(activity.items || []).map((e) => (
                  <tr key={e.id}>
                    <td>{formatDate(e.created_at)}</td>
                    <td>{e.project_name}</td>
                    <td>{EVENT_LABELS[e.event_type] || e.event_type}</td>
                    <td>{e.actor_email || "Sistema"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        );
      case "system":
        return (
          <>
            <div className="admin-stats-grid">
              <StatCard label="Sesiones invitado" value={stats?.guest_trials ?? 0} />
              <StatCard label="Análisis invitados" value={guestTrials.totals?.analyses ?? 0} />
              <StatCard label="Preguntas invitados" value={guestTrials.totals?.asks ?? 0} />
              <StatCard label="Período" value={stats?.period_key ?? "—"} />
            </div>
            <div className="admin-table-wrap">
              <table className="admin-table admin-table--compact">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Análisis</th>
                    <th>Preguntas</th>
                    <th>Última visita</th>
                  </tr>
                </thead>
                <tbody>
                  {(guestTrials.items || []).map((g) => (
                    <tr key={g.id}>
                      <td>{g.id.slice(0, 8)}…</td>
                      <td>{g.analyses_count}</td>
                      <td>{g.asks_count}</td>
                      <td>{formatDate(g.last_seen_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        );
      default:
        return null;
    }
  }

  return (
    <div className="admin-page admin-page--layout">
      <header className="admin-head">
        <div>
          <p className="admin-kicker">Solo administradores</p>
          <h1>{sectionTitle}</h1>
          <p className="admin-muted">Administración completa del sitio ARCHITECT.</p>
        </div>
        <Shield size={24} strokeWidth={1.5} />
      </header>

      {error && <p className="admin-error">{error}</p>}

      <div className="admin-layout admin-layout--in-page">
        <aside className="admin-sidebar">
          <p className="admin-sidebar-kicker">Apartados</p>
          <nav className="admin-nav">
            {SECTIONS.map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                type="button"
                className={`admin-nav-item${section === id ? " is-active" : ""}`}
                onClick={() => setSection(id)}
              >
                <Icon size={16} />
                <span className="admin-nav-copy">
                  <strong>{label}</strong>
                </span>
              </button>
            ))}
          </nav>
        </aside>
        <section className="admin-content">{renderContent()}</section>
      </div>
    </div>
  );
}
