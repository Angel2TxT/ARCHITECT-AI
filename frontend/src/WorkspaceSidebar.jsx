import React, { useState } from "react";
import {
  Building2,
  ChevronLeft,
  LogOut,
  Menu,
  Settings,
  Shield,
  Sparkles,
  Workflow
} from "lucide-react";import PlansModal from "./PlansModal.jsx";
import { formatUsage } from "./subscription.js";

const TOKEN_KEY = "plano_ia_token";
const USER_KEY = "plano_ia_user";
const SUB_KEY = "plano_ia_subscription";
const SIDEBAR_KEY = "plano_ia_sidebar_collapsed";
function navigate(path) {
  if (path === "/app/admin") {
    window.location.href = path;
    return;
  }
  if (path.startsWith("http") || path.startsWith("/legacy-app")) {
    window.location.href = path;
    return;
  }
  window.history.pushState({}, "", path);
  window.dispatchEvent(new PopStateEvent("popstate"));
}

function clearSession() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
  localStorage.removeItem(SUB_KEY);
}

export default function WorkspaceSidebar({
  path,
  user,
  subscription,
  onSubscriptionChange,
  collapsed,
  onToggleCollapsed
}) {
  const [plansOpen, setPlansOpen] = useState(false);
  const isAdmin = user?.role === "admin";
  const isSupport = user?.role === "support";
  const canOpenStaffPanel = isAdmin || isSupport;
  const isWorkspace = path === "/app" || path === "/app/";
  const isProjects = path.startsWith("/app/projects");
  const isAdminRoute = path.startsWith("/app/admin");
  const usage = formatUsage(subscription);

  const initials = (user?.full_name || user?.email || "U")
    .split(" ")
    .map((w) => w[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();

  return (
    <>
      {collapsed && (
        <button
          type="button"
          className="workspace-sidebar-float"
          onClick={onToggleCollapsed}
          aria-label="Mostrar panel"
          title="Mostrar panel lateral"
        >
          <Menu size={18} />
        </button>
      )}

      <aside className={`workspace-sidebar${collapsed ? " is-collapsed" : ""}`}>
        <div className="workspace-sidebar-brand">
          <div className="workspace-sidebar-brand-text">
            <strong>ARCHITECT</strong>
          </div>
          <button
            type="button"
            className="workspace-sidebar-toggle"
            onClick={onToggleCollapsed}
            aria-label="Minimizar panel"
            title="Minimizar panel lateral"
          >
            <ChevronLeft size={18} />
          </button>
        </div>
        {subscription && (
          <button
            type="button"
            className={`workspace-sidebar-usage${usage.limitReached ? " is-limit" : ""}`}
            onClick={() => setPlansOpen(true)}
            title="Ver planes y uso"
          >
            <div className="workspace-sidebar-usage-row">
              <span>{usage.planName}</span>
              <span>{usage.usageLabel}</span>
            </div>
            <div className="workspace-sidebar-usage-bar">
              <span style={{ width: `${usage.pct}%` }} />
            </div>
            <div className="workspace-sidebar-usage-asks">{usage.asksLabel}</div>
          </button>
        )}

        <nav className="workspace-sidebar-nav" aria-label="Herramientas">
          <button
            type="button"
            className={isWorkspace ? "is-active" : ""}
            onClick={() => navigate("/legacy-app")}
          >
            <Sparkles size={18} />
            Revisión IA
          </button>
          <button
            type="button"
            className={isProjects ? "is-active" : ""}
            onClick={() => navigate("/legacy-app?home-projects=1")}
          >
            <Building2 size={18} />
            Casa hogar
          </button>
          {canOpenStaffPanel && (
            <button
              type="button"
              className={isAdminRoute ? "is-active" : ""}
              onClick={() => navigate("/app/admin")}
            >
              <Shield size={18} />
              {isSupport ? "Bandeja soporte" : "Administración"}
            </button>
          )}
          <button type="button" onClick={() => setPlansOpen(true)}>
            <Workflow size={18} />
            Planes
          </button>
          <button type="button" onClick={() => navigate("/legacy-app")}>
            <Settings size={18} />
            Ajustes
          </button>
        </nav>

        <div className="workspace-sidebar-spacer" aria-hidden="true" />

        <div className="workspace-sidebar-footer">
          <div className="workspace-sidebar-user">
            <span className="workspace-sidebar-avatar">{initials}</span>
            <div>
              <strong>{user?.full_name || user?.email || "Usuario"}</strong>
              <small>
                {isAdmin ? "Administrador" : isSupport ? "Soporte" : usage.planName}
              </small>
            </div>
          </div>
          <button
            type="button"
            className="workspace-sidebar-logout"
            title="Cerrar sesión"
            onClick={() => {
              clearSession();
              navigate("/login");
            }}
          >
            <LogOut size={16} />
          </button>
        </div>
      </aside>

      <PlansModal
        open={plansOpen}
        onClose={() => setPlansOpen(false)}
        subscription={subscription}
        onSubscriptionChange={onSubscriptionChange}
      />
    </>
  );
}
