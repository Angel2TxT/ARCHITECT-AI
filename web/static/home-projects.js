
(function () {
  const $ = (sel) => document.querySelector(sel);

  let projects = [];
  let activeId = null;
  let viewedStage = null;
  let detailView = "stage";
  let sectionFilter = "all";
  let analysesPicker = [];
  let analysesLoaded = false;
  let activityEvents = [];
  let activityOffset = 0;
  let activityHasMore = false;
  let activityLoading = false;
  let projectSearchQuery = "";
  let expandedSectionId = null;
  let isProjectsDrawerOpen = false;
  let completionOverviewMode = false;
  let lastDetailView = "stage";

  function escapeHtml(s) {
    return String(s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function formatBytes(n) {
    const v = Number(n) || 0;
    if (v < 1024) return `${v} B`;
    if (v < 1024 * 1024) return `${(v / 1024).toFixed(1)} KB`;
    return `${(v / (1024 * 1024)).toFixed(1)} MB`;
  }

  function statusLabel(status) {
    const map = {
      pending: "Pendiente",
      in_progress: "En curso",
      completed: "Completada",
      blocked: "Bloqueada",
      active: "Activo",
      on_hold: "En pausa",
      canceled: "Cancelado",
    };
    return map[status] || status;
  }

  function sectionStatusLabel(status) {
    const map = {
      pending: "Sin documentación",
      in_progress: "En revisión",
      needs_details: "Con observaciones",
      needs_correction: "Corrección requerida",
      completed: "Correcto",
    };
    return map[status] || status;
  }

  function sectionMatchesFilter(sec) {
    if (sectionFilter === "all") return true;
    if (sectionFilter === "no_docs") return !sectionHasDocuments(sec);
    if (sectionFilter === "corrections") {
      return sec.status === "needs_correction" || sec.status === "needs_details";
    }
    if (sectionFilter === "completed") return sec.status === "completed";
    if (sectionFilter === "in_review") return sec.status === "in_progress";
    return sec.status === sectionFilter;
  }

  function renderLastReview(sec) {
    const lr = sec.last_review;
    if (!lr || !lr.created_at) return "";
    return `
      <p class="home-last-review text-xs mt-2 opacity-75">
        <span class="font-semibold">Última revisión:</span>
        ${escapeHtml(lr.author_name)} · ${sectionStatusLabel(lr.status)}
        · ${formatShortDate(lr.created_at)}
        ${lr.comment_preview ? ` — «${escapeHtml(lr.comment_preview)}»` : ""}
      </p>`;
  }

  const EVENT_LABELS = {
    section_assigned: "asignó un responsable",
    section_status_changed: "cambió el estado de revisión",
    section_reopened: "reabrió un apartado",
    section_comment_added: "añadió un comentario",
    section_comment_deleted: "eliminó un comentario",
    document_uploaded: "subió un documento",
    document_deleted: "eliminó un documento",
    member_invited: "invitó a un colaborador",
    member_joined: "se unió al proyecto",
    member_removed: "quitó a un colaborador",
    stage_completed: "completó una etapa",
    stage_reopened: "reabrió una etapa",
    stage_advanced: "avanzó a la siguiente etapa",
  };

  function formatEventLine(ev) {
    const who = escapeHtml(ev.actor_name || "Alguien");
    const action = EVENT_LABELS[ev.event_type] || ev.event_type;
    const section = ev.section_title ? ` en «${escapeHtml(ev.section_title)}»` : "";
    const meta = ev.metadata || {};
    let extra = "";
    if (ev.event_type === "section_status_changed" && meta.to) {
      extra = ` → ${sectionStatusLabel(meta.to)}`;
    } else if (ev.event_type === "section_reopened" && meta.to) {
      extra = ` → ${sectionStatusLabel(meta.to)}`;
      if (meta.reason) extra += ` — «${escapeHtml(meta.reason)}»`;
    } else if (ev.event_type === "stage_reopened" && meta.stage_number) {
      extra = ` (etapa ${meta.stage_number})`;
      if (meta.reason) extra += ` — «${escapeHtml(meta.reason)}»`;
    } else if (ev.event_type === "stage_advanced" && meta.to_stage) {
      extra = ` → etapa ${meta.to_stage}`;
    } else if (ev.event_type === "stage_completed" && meta.stage_number) {
      extra = ` (etapa ${meta.stage_number})`;
    } else if (ev.event_type === "member_removed" && meta.email) {
      extra = `: ${escapeHtml(meta.email)}`;
    } else if (ev.event_type === "document_uploaded" && meta.filename) {
      extra = `: ${escapeHtml(meta.filename)}`;
    } else if (ev.event_type === "member_invited" && meta.email) {
      extra = `: ${escapeHtml(meta.email)}`;
    } else if (meta.preview) {
      extra = ` — «${escapeHtml(meta.preview)}»`;
    } else if (meta.comment_preview) {
      extra = ` — «${escapeHtml(meta.comment_preview)}»`;
    }
    return `<strong>${who}</strong> ${action}${section}${extra}`;
  }

  function getDetailScrollEl() {
    return document.querySelector("#homeProjectDetailScroll");
  }

  function resetDetailScroll() {
    const scrollEl = getDetailScrollEl();
    if (scrollEl) scrollEl.scrollTop = 0;
  }

  function renderActivityBlock(project) {
    const items = activityEvents.length
      ? activityEvents
          .map(
            (ev) => `
          <li class="home-activity-item">
            <p class="home-activity-text">${formatEventLine(ev)}</p>
            <time class="home-activity-time">${formatShortDate(ev.created_at)}</time>
          </li>`
          )
          .join("")
      : `<li class="home-activity-empty text-sm opacity-50">Sin actividad registrada aún.</li>`;

    return `
      <div class="home-activity-block">
        <div class="flex flex-wrap items-center justify-between gap-2 mb-4">
          <div>
            <p class="home-section-title">Actividad del proyecto</p>
            <p class="text-xs opacity-60 mt-1">Historial de revisiones, archivos e invitaciones.</p>
          </div>
          ${
            activityHasMore
              ? `<button type="button" class="btn-secondary text-xs py-2 px-3" id="btnLoadMoreActivity">Cargar más</button>`
              : ""
          }
        </div>
        <ul class="home-activity-list">${items}</ul>
      </div>`;
  }

  function renderCommentsHistory(project, sec) {
    const comments = sec.comments || [];
    const currentUserId = PlanoAuth.getUser()?.id;
    const isOwner = project.my_role === "owner";
    const canDeleteComment = canEdit(project);
    const items = comments.length
      ? comments
          .map((c) => {
            const canDelete = canDeleteComment && (isOwner || c.user_id === currentUserId);
            return `
            <li class="home-comment-item" data-comment-id="${c.id}">
              <div class="home-comment-meta">
                <strong class="home-comment-author">${escapeHtml(c.author_name)}</strong>
                <span class="home-comment-date">${formatShortDate(c.created_at)}</span>
                ${
                  canDelete
                    ? `<button type="button" class="home-comment-delete text-xs text-red-600" data-section-id="${sec.id}" data-comment-id="${c.id}">Eliminar</button>`
                    : ""
                }
              </div>
              <p class="home-comment-body">${escapeHtml(c.body)}</p>
            </li>`;
          })
          .join("")
      : "";

    if (!items) return "";

    return `
      <div class="home-comments-history mt-3">
        <p class="text-xs font-semibold uppercase tracking-wide opacity-50 mb-2">Historial (${sec.comments_count ?? comments.length})</p>
        <ul class="home-comment-list space-y-2">${items}</ul>
      </div>`;
  }

  function renderReviewBlock(project, sec, editable) {
    if (!sectionHasDocuments(sec)) {
      return `<p class="text-xs opacity-50 mt-3 pt-3 border-t border-[var(--border)]">Sube documentación para habilitar la revisión y los comentarios.</p>`;
    }

    const history = renderCommentsHistory(project, sec);
    const canReopen = canReopenSection(project);

    if (sec.status === "completed" && canReopen) {
      return `
        <div class="home-review-block home-reopen-block mt-3 pt-3 border-t border-[var(--border)]" data-section-id="${sec.id}">
          <p class="text-xs font-semibold uppercase tracking-wide opacity-50 mb-2">Apartado completado</p>
          <p class="text-xs opacity-70 mb-2">Solo el propietario o un administrador pueden reabrirlo.</p>
          <label class="text-xs opacity-70 block mb-1">Nuevo estado</label>
          <select class="home-section-reopen-status rounded-lg border px-2 py-1.5 text-xs w-full max-w-sm" data-section-id="${sec.id}">
            <option value="in_progress">En revisión</option>
            <option value="needs_details">Con observaciones</option>
            <option value="needs_correction">Corrección requerida</option>
          </select>
          <label class="text-xs opacity-70 block mt-2 mb-1">Motivo de reapertura (obligatorio)</label>
          <textarea class="home-section-reopen-reason rounded-lg border px-2 py-1.5 text-xs w-full" data-section-id="${sec.id}" rows="2" maxlength="4000" placeholder="Explica por qué se reabre este apartado (mín. 10 caracteres)"></textarea>
          <button type="button" class="btn-secondary text-xs py-1.5 px-2.5 mt-2 home-section-reopen-submit" data-section-id="${sec.id}">Reabrir apartado</button>
          ${history}
        </div>`;
    }

    if (!editable) {
      return `
        <div class="home-review-block mt-3 pt-3 border-t border-[var(--border)]">
          <p class="text-xs opacity-70">Estado de revisión: <strong>${sectionStatusLabel(sec.status)}</strong></p>
          ${history}
        </div>`;
    }

    if (sec.status === "completed") {
      return `
        <div class="home-review-block mt-3 pt-3 border-t border-[var(--border)]">
          <p class="text-xs opacity-70">Estado de revisión: <strong>${sectionStatusLabel(sec.status)}</strong></p>
          <p class="text-xs opacity-50 mt-1">Apartado cerrado. Contacta al propietario para reabrirlo.</p>
          ${history}
        </div>`;
    }

    return `
      <div class="home-review-block mt-3 pt-3 border-t border-[var(--border)]" data-section-id="${sec.id}">
        <p class="text-xs font-semibold uppercase tracking-wide opacity-50 mb-2">Revisión documental</p>
        <label class="text-xs opacity-70 block mb-1">Estado</label>
        <select class="home-section-review-status rounded-lg border px-2 py-1.5 text-xs w-full max-w-sm" data-section-id="${sec.id}">
          <option value="in_progress" ${sec.status === "in_progress" ? "selected" : ""}>En revisión</option>
          <option value="needs_details" ${sec.status === "needs_details" ? "selected" : ""}>Con observaciones</option>
          <option value="needs_correction" ${sec.status === "needs_correction" ? "selected" : ""}>Corrección requerida</option>
          <option value="completed" ${sec.status === "completed" ? "selected" : ""}>Correcto</option>
        </select>
        <label class="text-xs opacity-70 block mt-2 mb-1">Comentario</label>
        <textarea class="home-section-review-comment rounded-lg border px-2 py-1.5 text-xs w-full" data-section-id="${sec.id}" rows="2" maxlength="4000" placeholder="Añade aquí el comentario de revisión, corrección o aprobación. Usa @correo para mencionar."></textarea>
        <button type="button" class="btn-primary text-xs py-1.5 px-2.5 mt-2 home-section-review-submit" data-section-id="${sec.id}">Guardar revisión</button>
        ${history}
        ${sec.comments_count > (sec.comments || []).length ? `<button type="button" class="btn-secondary text-xs py-1 px-2 mt-2 home-section-load-comments" data-section-id="${sec.id}">Ver todos los comentarios (${sec.comments_count})</button>` : ""}
      </div>`;
  }

  function sectionHasDocuments(sec) {
    return !!(sec.has_documents || (sec.documents && sec.documents.length > 0));
  }

  function formatShortDate(iso) {
    if (!iso) return "";
    try {
      return new Date(iso).toLocaleString("es", {
        day: "2-digit",
        month: "short",
        hour: "2-digit",
        minute: "2-digit",
      });
    } catch {
      return "";
    }
  }

  function formatLongDate(iso) {
    if (!iso) return "—";
    try {
      return new Date(iso).toLocaleDateString("es", {
        day: "numeric",
        month: "long",
        year: "numeric",
      });
    } catch {
      return "—";
    }
  }

  function isProjectCompleted(project) {
    if (!project) return false;
    if (project.status === "completed") return true;
    const stages = project.stages || [];
    if (!stages.length) return false;
    return stages.every((s) => s.status === "completed");
  }

  function projectCompletionStats(project) {
    const stages = project.stages || [];
    let totalSections = 0;
    let completedSections = 0;
    stages.forEach((s) => {
      const sp = s.sections_progress || {};
      const secs = s.sections || [];
      totalSections += sp.total || secs.length;
      completedSections +=
        sp.done || secs.filter((sec) => sec.status === "completed").length;
    });
    const lastStage = stages[stages.length - 1];
    return {
      totalStages: stages.length,
      completedStages: stages.filter((s) => s.status === "completed").length,
      totalSections,
      completedSections,
      completedAt: lastStage?.completed_at || project.updated_at || project.created_at,
      filesCount: (project.files || []).length,
      membersCount: (project.members || []).length,
    };
  }

  function renderCompletionBlock(project) {
    const stats = projectCompletionStats(project);
    const stages = project.stages || [];
    const files = (project.files || []).slice(0, 8);
    const members = project.members || [];

    const stageTimeline = stages
      .map(
        (s) => `
        <li class="home-completion-stage-item ${s.status === "completed" ? "is-done" : ""}">
          <span class="home-completion-stage-num">${s.stage_number}</span>
          <div class="home-completion-stage-copy">
            <p class="home-completion-stage-title">${escapeHtml(s.title)}</p>
            <p class="home-completion-stage-meta">${s.completed_at ? formatShortDate(s.completed_at) : "Pendiente"}</p>
          </div>
          ${
            s.status === "completed"
              ? '<span class="material-symbols-outlined home-completion-stage-check" aria-hidden="true">check_circle</span>'
              : '<span class="material-symbols-outlined home-completion-stage-check is-pending" aria-hidden="true">radio_button_unchecked</span>'
          }
        </li>`
      )
      .join("");

    const fileList = files.length
      ? files
          .map(
            (f) => `
          <li class="home-completion-file-item">
            <button type="button" class="home-doc-name" data-dl-url="${escapeHtml(f.download_url)}" data-dl-name="${escapeHtml(f.filename)}">${escapeHtml(f.filename)}</button>
            <span class="home-completion-file-meta">Etapa ${f.stage_number}${f.section_title ? " · " + escapeHtml(f.section_title) : ""} · ${formatBytes(f.file_size)}</span>
          </li>`
          )
          .join("")
      : '<li class="text-sm opacity-50 py-2">Sin archivos en el proyecto.</li>';

    const memberList = members.length
      ? members
          .map(
            (m) => `
          <li class="home-completion-member">
            <span class="home-completion-member-avatar" aria-hidden="true">${escapeHtml((m.full_name || m.email || "?").charAt(0).toUpperCase())}</span>
            <div>
              <p class="home-completion-member-name">${escapeHtml(m.full_name || m.email)}</p>
              <p class="home-completion-member-role">${m.role === "owner" ? "Propietario" : m.role === "editor" ? "Editor" : "Lector"}</p>
            </div>
          </li>`
          )
          .join("")
      : '<li class="text-sm opacity-50 py-2">Sin colaboradores adicionales.</li>';

    return `
      <article class="home-completion-card">
        <div class="home-completion-hero">
          <div class="home-completion-hero-icon" aria-hidden="true">
            <span class="material-symbols-outlined">verified</span>
          </div>
          <div>
            <p class="home-completion-kicker">Proyecto completado</p>
            <h4 class="home-completion-title">${escapeHtml(project.name)}</h4>
            <p class="home-completion-subtitle">
              ${escapeHtml(project.client_name || "Cliente no indicado")}${project.location ? " · " + escapeHtml(project.location) : ""}
            </p>
            <p class="home-completion-date">Cierre: ${formatLongDate(stats.completedAt)}</p>
          </div>
        </div>

        <div class="home-completion-stats">
          <div class="home-completion-stat">
            <span class="home-completion-stat-value">${stats.completedStages}/${stats.totalStages}</span>
            <span class="home-completion-stat-label">Etapas</span>
          </div>
          <div class="home-completion-stat">
            <span class="home-completion-stat-value">${stats.completedSections}/${stats.totalSections}</span>
            <span class="home-completion-stat-label">Apartados</span>
          </div>
          <div class="home-completion-stat">
            <span class="home-completion-stat-value">${stats.filesCount}</span>
            <span class="home-completion-stat-label">Archivos</span>
          </div>
          <div class="home-completion-stat">
            <span class="home-completion-stat-value">${stats.membersCount}</span>
            <span class="home-completion-stat-label">Colaboradores</span>
          </div>
        </div>

        <div class="home-completion-grid">
          <section class="home-completion-panel">
            <div class="home-completion-panel-head">
              <p class="home-section-title">Recorrido del proyecto</p>
              <p class="text-xs opacity-60 mt-1">Las 9 etapas metodológicas completadas.</p>
            </div>
            <ol class="home-completion-stage-list">${stageTimeline}</ol>
          </section>

          <section class="home-completion-panel">
            <div class="home-completion-panel-head">
              <p class="home-section-title">Entregables recientes</p>
              <button type="button" class="home-completion-link-btn" id="btnCompletionAllFiles">Ver todos (${stats.filesCount})</button>
            </div>
            <ul class="home-completion-file-list">${fileList}</ul>
          </section>
        </div>

        <section class="home-completion-panel mt-5">
          <div class="home-completion-panel-head">
            <p class="home-section-title">Equipo</p>
            <button type="button" class="home-completion-link-btn" id="btnCompletionTeam">Gestionar equipo</button>
          </div>
          <ul class="home-completion-member-list">${memberList}</ul>
        </section>

        <div class="home-completion-actions">
          <button type="button" class="btn-secondary text-xs py-2 px-4" id="btnCompletionActivity">Ver actividad</button>
          <button type="button" class="btn-secondary text-xs py-2 px-4" id="btnCompletionBrowseStages">Revisar etapas</button>
        </div>
      </article>`;
  }

  function renderAssigneeSelect(project, sec, editable) {
    const members = project.members || [];
    const currentId = sec.assigned_to_user_id || "";
    const assignee = sec.assigned_to;
    if (!editable) {
      if (!assignee) {
        return `<p class="text-xs opacity-60 mt-2">Sin responsable asignado</p>`;
      }
      return `<p class="text-xs mt-2"><span class="opacity-60">Responsable:</span> <strong>${escapeHtml(assignee.full_name)}</strong></p>`;
    }
    const options = [`<option value="">Sin asignar</option>`]
      .concat(
        members.map(
          (m) =>
            `<option value="${m.user_id}" ${currentId === m.user_id ? "selected" : ""}>${escapeHtml(m.full_name)}</option>`
        )
      )
      .join("");
    return `
      <label class="text-xs opacity-70 block mt-2 mb-1">Responsable</label>
      <select class="home-section-assignee rounded-lg border px-2 py-1.5 text-xs w-full max-w-xs" data-section-id="${sec.id}">
        ${options}
      </select>`;
  }


  function canEdit(project) {
    return project?.permissions?.can_edit ?? (project?.my_role === "owner" || project?.my_role === "editor");
  }

  function canReview(project) {
    return project?.permissions?.can_review ?? canEdit(project);
  }

  function canWorkSection(project, section) {
    if (!canEdit(project)) return false;
    if (section?.assigned_to_user_id) return true;
    return project?.my_role === "owner" || project?.my_role === "admin";
  }

  function canAssign(project) {
    return (
      project?.permissions?.can_assign ??
      (project?.my_role === "owner" || project?.my_role === "admin")
    );
  }

  function canManageTeam(project) {
    return (
      project?.permissions?.can_manage_team ??
      (project?.my_role === "owner" || project?.my_role === "admin")
    );
  }

  function canAdvanceStage(project) {
    return (
      project?.permissions?.can_advance_stage ??
      (project?.my_role === "owner" || project?.my_role === "admin")
    );
  }

  function canDeleteProject(project) {
    return (
      project?.permissions?.can_delete_project ??
      (project?.my_role === "owner" || project?.my_role === "admin")
    );
  }

  function canDeleteSection(project) {
    return (
      project?.permissions?.can_delete_section ??
      (project?.my_role === "owner" || project?.my_role === "admin")
    );
  }

  function canReopenSection(project) {
    return (
      project?.permissions?.can_reopen_section ??
      (project?.my_role === "owner" || project?.my_role === "admin")
    );
  }

  function canReopenStage(project) {
    return (
      project?.permissions?.can_reopen_stage ??
      (project?.my_role === "owner" || project?.my_role === "admin")
    );
  }

  async function promptReopenReason(actionLabel) {
    return PlanoDialog.prompt({
      title: actionLabel,
      message: "Indica el motivo de reapertura:",
      minLength: 10,
      multiline: true,
      confirmLabel: "Continuar",
    });
  }

  function syncHomeProjectsUrl(active, projectId) {
    const url = new URL(window.location.href);
    if (active) {
      url.searchParams.set("home-projects", "1");
      if (projectId) url.searchParams.set("project", projectId);
      else url.searchParams.delete("project");
    } else {
      url.searchParams.delete("home-projects");
      url.searchParams.delete("project");
    }
    const next = url.pathname + url.search;
    if (window.location.pathname + window.location.search !== next) {
      window.history.replaceState({}, "", next);
    }
  }

  function open() {
    const hasToken = typeof PlanoAuth?.getToken === "function" && PlanoAuth.getToken();
    if ((typeof window.getIsGuestMode === "function" && window.getIsGuestMode()) || !hasToken) {
      sessionStorage.setItem("open_home_projects", "1");
      window.location.href = "/login?next=" + encodeURIComponent("/legacy-app?home-projects=1");
      return;
    }
    syncHomeProjectsUrl(true, activeId);
    $("#homeProjectsPanel")?.removeAttribute("hidden");
    $("#homeProjectsPanel")?.classList.remove("hidden");
    $("#chatArea")?.setAttribute("hidden", "");
    $("#chatArea")?.classList.add("hidden");
    $("#composerDock")?.classList.add("hidden");
    document.body.classList.add("home-projects-mode");
    closeProjectsDrawer();
    window.setNavActive?.("home-projects");
    loadProjects();
  }

  function close() {
    syncHomeProjectsUrl(false);
    $("#homeProjectsPanel")?.setAttribute("hidden", "");
    $("#homeProjectsPanel")?.classList.add("hidden");
    $("#chatArea")?.removeAttribute("hidden");
    $("#chatArea")?.classList.remove("hidden");
    $("#composerDock")?.classList.remove("hidden");
    document.body.classList.remove("home-projects-mode");
    closeProjectsDrawer();
  }

  function isMobileViewport() {
    return window.matchMedia("(max-width: 900px)").matches;
  }

  function openProjectsDrawer() {
    if (!isMobileViewport()) return;
    const mainSidebarOpen = !document.body.classList.contains("sidebar-collapsed");
    if (mainSidebarOpen) {
      document.querySelector("#btnMenu")?.click();
    }
    isProjectsDrawerOpen = true;
    $("#homeProjectsPanel")?.classList.add("is-drawer-open");
  }

  function closeProjectsDrawer() {
    isProjectsDrawerOpen = false;
    $("#homeProjectsPanel")?.classList.remove("is-drawer-open");
  }

  function toggleProjectsDrawer() {
    if (isProjectsDrawerOpen) closeProjectsDrawer();
    else openProjectsDrawer();
  }

  async function ensureAnalysesPicker() {
    if (analysesLoaded) return analysesPicker;
    try {
      const res = await PlanoAuth.apiFetch("/api/home-projects/analyses-picker");
      if (res.ok) {
        analysesPicker = await res.json();
        analysesLoaded = true;
      }
    } catch {
      analysesPicker = [];
    }
    return analysesPicker;
  }

  async function loadProjects() {
    try {
      const res = await PlanoAuth.apiFetch("/api/home-projects");
      if (!res.ok) throw new Error("No se pudieron cargar los proyectos");
      projects = await res.json();
      renderList();
      const urlProject = new URLSearchParams(window.location.search).get("project");
      if (urlProject && projects.find((p) => p.id === urlProject)) {
        selectProject(urlProject);
      } else if (activeId && projects.find((p) => p.id === activeId)) {
        const p = projects.find((x) => x.id === activeId);
        viewedStage = viewedStage || p.current_stage;
        renderDetail(p);
      } else if (projects.length && !activeId) {
        selectProject(projects[0].id);
      } else {
        activeId = null;
        viewedStage = null;
        renderDetail(null);
      }
    } catch (err) {
      window.showToast?.(err.message || "Error al cargar proyectos");
    }
  }

  function renderList() {
    const list = $("#homeProjectsList");
    if (!list) return;
    list.innerHTML = "";
    const q = projectSearchQuery.trim().toLowerCase();
    const visible = q
      ? projects.filter((p) => {
          const hay = [
            p.name,
            p.client_name,
            p.location,
            p.my_role,
          ]
            .filter(Boolean)
            .join(" ")
            .toLowerCase();
          return hay.includes(q);
        })
      : projects;

    if (!visible.length) {
      list.innerHTML =
        q
          ? '<li class="text-xs opacity-60 px-2 py-4 text-center">Sin resultados</li>'
          : '<li class="text-xs opacity-60 px-2 py-4 text-center">Sin proyectos aún</li>';
      return;
    }
    visible.forEach((p) => {
      const li = document.createElement("li");
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className =
        "home-project-item w-full text-left rounded-md border p-3 transition-colors" +
        (p.id === activeId ? " is-active" : "");
      const roleHint =
        p.my_role && p.my_role !== "owner"
          ? ` · ${p.my_role === "editor" ? "Colaborador" : "Lector"}`
          : "";
      const isDone = isProjectCompleted(p);
      const progressLabel = isDone
        ? `Completado · ${p.progress_percent}%`
        : `Etapa ${p.current_stage}/${p.stages?.length || 9} · ${p.progress_percent}%`;
      btn.innerHTML = `
        <span class="block font-semibold text-sm truncate">${escapeHtml(p.name)}</span>
        <span class="block text-[11px] opacity-60 mt-1 truncate">${escapeHtml(p.location || p.client_name || "Sin ubicación")}${roleHint}</span>
        <span class="home-project-progress mt-2 block text-[10px] font-bold uppercase tracking-wider ${isDone ? "is-completed" : ""}">
          ${progressLabel}
        </span>
        <span class="home-project-progress-track mt-2 block" aria-hidden="true">
          <span class="home-project-progress-fill" style="width:${Math.max(0, Math.min(100, Number(p.progress_percent) || 0))}%"></span>
        </span>`;
      btn.onclick = () => selectProject(p.id);
      li.appendChild(btn);
      list.appendChild(li);
    });
  }

  function selectProject(id) {
    activeId = id;
    const project = projects.find((p) => p.id === id);
    viewedStage = project?.current_stage || 1;
    detailView = "stage";
    sectionFilter = "all";
    expandedSectionId = null;
    completionOverviewMode = isProjectCompleted(project);
    activityEvents = [];
    activityOffset = 0;
    activityHasMore = false;
    syncHomeProjectsUrl(true, id);
    renderList();
    renderDetail(project || null);
    closeProjectsDrawer();
  }

  function renderDocList(docs, projectId, editable) {
    if (!docs.length) {
      return '<li class="text-xs opacity-50 py-1">Sin archivos aún</li>';
    }
    return docs
      .map(
        (d) => `
        <li class="home-doc-item">
          <button type="button" class="home-doc-name" data-dl-url="${escapeHtml(d.download_url)}" data-dl-name="${escapeHtml(d.filename)}">${escapeHtml(d.filename)}</button>
          <span class="home-doc-meta">${formatBytes(d.file_size)}</span>
          ${
            editable
              ? `<button type="button" class="home-doc-delete" data-doc-id="${d.id}" title="Eliminar">×</button>`
              : ""
          }
        </li>`
      )
      .join("");
  }

  function renderSectionsBlock(stage, project, editable) {
    const sections = (stage.sections || []).filter(sectionMatchesFilter);
    const progress = stage.sections_progress || {
      done: 0,
      total: 0,
      with_files: 0,
      assigned: 0,
      needs_action: 0,
      without_docs: 0,
    };

    const allSecs = stage.sections || [];
    const counts = {
      all: allSecs.length,
      no_docs: allSecs.filter((s) => !sectionHasDocuments(s)).length,
      in_review: allSecs.filter((s) => s.status === "in_progress").length,
      corrections: allSecs.filter(
        (s) => s.status === "needs_correction" || s.status === "needs_details"
      ).length,
      completed: allSecs.filter((s) => s.status === "completed").length,
    };

    const cards = sections.length
      ? sections
          .map((sec) => {
            const statusCls = `home-section-status is-${sec.status}`;
            const needsAttention =
              sec.status === "needs_correction" || sec.status === "needs_details";
            const docsCount = sec.documents_count ?? (sec.documents || []).length;
            const commentsCount = sec.comments_count ?? (sec.comments || []).length;
            const assigneeName = sec.assigned_to?.full_name || null;
            const accentCls =
              sec.status === "completed"
                ? "is-success"
                : sec.status === "in_progress" || sec.status === "needs_correction" || sec.status === "needs_details"
                  ? "is-warning"
                  : "is-neutral";
            return `
            <article class="home-section-card home-module-card ${needsAttention ? "needs-attention" : ""} ${accentCls}" data-section-id="${sec.id}">
              <header class="home-section-card-head">
                <div class="flex-1 min-w-0">
                  <h5 class="home-section-card-title">${escapeHtml(sec.title)}</h5>
                  ${
                    sec.description
                      ? `<p class="home-section-card-desc is-truncated">${escapeHtml(sec.description)}</p>`
                      : ""
                  }
                  <div class="home-module-meta-row home-module-meta-stack">
                    <span class="home-module-files">${docsCount ? `${docsCount} archivo${docsCount === 1 ? "" : "s"}` : "Subir documento"}</span>
                    <span class="home-module-assignee">${assigneeName ? `Asignado: ${escapeHtml(assigneeName)}` : "Sin asignar"}</span>
                    <span class="home-module-comments">${commentsCount} comentario${commentsCount === 1 ? "" : "s"}</span>
                  </div>
                </div>
                <div class="home-module-right">
                  <span class="${statusCls}">${sectionStatusLabel(sec.status)}</span>
                  <button type="button" class="home-module-expand-btn" data-open-section="${sec.id}" aria-label="Abrir apartado">⋯</button>
                </div>
              </header>
            </article>`;
          })
          .join("")
      : `<p class="text-sm opacity-60">${sectionFilter === "all" ? "No hay apartados en esta etapa." : "Ningún apartado coincide con el filtro."}</p>`;

    return `
      <div class="home-sections-block">
        <div class="flex flex-wrap items-center justify-between gap-2 mb-3">
          <div>
            <p class="home-sections-heading">Apartados documentales</p>
            <p class="text-xs opacity-60 mt-1">${progress.done}/${progress.total} completados · ${progress.with_files} con archivos · ${progress.needs_action || 0} requieren acción · ${progress.without_docs || 0} sin docs</p>
          </div>
          ${
            editable
              ? `<button type="button" class="btn-primary text-xs py-2 px-3" id="btnAddSection">Nuevo</button>`
              : ""
          }
        </div>
        <div class="home-section-filters flex flex-wrap gap-2 mb-3">
          ${[
            ["all", `Todos (${counts.all})`],
            ["no_docs", `Sin documentación (${counts.no_docs})`],
            ["in_review", `En revisión (${counts.in_review})`],
            ["corrections", `Correcciones (${counts.corrections})`],
            ["completed", `Aprobado (${counts.completed})`],
          ]
            .map(
              ([id, label]) =>
                `<button type="button" class="home-section-filter ${sectionFilter === id ? "is-active" : ""}" data-filter="${id}">${label}</button>`
            )
            .join("")}
        </div>
        <div class="home-sections-grid" id="homeSectionsGrid">
          ${cards}
          ${
            editable
              ? `<button type="button" class="home-module-create-card" id="homeCreateSectionCard">
                  <span class="home-module-create-icon">+</span>
                  <span>Crear apartado</span>
                </button>`
              : ""
          }
        </div>
      </div>`;
  }

  function renderModuleOverlay(project, openSection, editable) {
    if (!openSection) return "";
    const sectionWorkable = canWorkSection(project, openSection);
    const canDeleteSec = canDeleteSection(project);
    return `<div class="home-module-overlay" id="homeModuleOverlay">
      <article class="home-module-float" data-section-id="${openSection.id}" role="dialog" aria-modal="true">
        <div class="home-module-float-head">
          <div>
            <p class="home-module-float-kicker">Apartado</p>
            <h4 class="home-module-float-title">${escapeHtml(openSection.title)}</h4>
          </div>
          <div class="home-module-float-actions">
            <span class="home-section-status is-${openSection.status}">${sectionStatusLabel(openSection.status)}</span>
            <button type="button" class="home-module-close-btn" id="btnCloseModuleOverlay" aria-label="Cerrar">✕</button>
          </div>
        </div>
        ${
          openSection.description
            ? `<p class="home-module-float-desc">${escapeHtml(openSection.description)}</p>`
            : ""
        }
        <div class="home-module-details">
          ${
            !sectionWorkable
              ? `<p class="text-xs opacity-70 mb-2">Sin responsable asignado: solo la persona propietaria del proyecto puede trabajar este apartado hasta asignar responsable.</p>`
              : ""
          }
          ${renderLastReview(openSection)}
          ${renderAssigneeSelect(project, openSection, canAssign(project))}
          <ul class="home-doc-list space-y-1 mb-2 mt-2">${renderDocList(openSection.documents || [], project.id, editable)}</ul>
          ${
            editable && sectionWorkable
              ? `<div class="home-section-actions flex flex-wrap gap-2 items-center">
                  <label class="home-doc-upload btn-secondary text-xs py-1.5 px-2.5 inline-flex cursor-pointer">
                    <input type="file" class="home-section-file-input" data-section-id="${openSection.id}" accept=".pdf,.png,.jpg,.jpeg,.webp,.gif,.tif,.tiff,.doc,.docx,.xls,.xlsx" hidden />
                    Subir archivo
                  </label>
                  <button type="button" class="btn-secondary text-xs py-1.5 px-2.5 text-red-600 home-section-delete" data-section-id="${openSection.id}" ${canDeleteSec ? "" : "hidden"}>Eliminar apartado</button>
                </div>`
              : ""
          }
          ${renderReviewBlock(project, openSection, canReview(project) && sectionWorkable)}
        </div>
      </article>
    </div>`;
  }

  function renderAnalysisBlock(stage) {
    if (!stage.plan_review) return "";
    const linked = stage.analysis;
    const options = analysesPicker
      .map(
        (a) =>
          `<option value="${a.id}" ${stage.analysis_id === a.id ? "selected" : ""}>${escapeHtml(a.filename)} (${a.counts?.errors || 0} err / ${a.counts?.warnings || 0} adv)</option>`
      )
      .join("");
    return `
      <div class="home-analysis-block p-3 rounded-xl border border-dashed">
        <p class="home-section-title">Revisión de planos</p>
        ${
          linked
            ? `<p class="text-sm mb-2 mt-2"><strong>${escapeHtml(linked.filename)}</strong><br/>
               <span class="text-xs opacity-65">${linked.errors || 0} errores · ${linked.warnings || 0} advertencias</span></p>
               <a class="text-xs underline opacity-80" href="/legacy-app" rel="noopener">Abrir en Revisión IA</a>`
            : `<p class="text-xs opacity-65 mt-2 mb-2">Analiza un plano en Revisión IA y vincúlalo aquí.</p>`
        }
        <label class="block text-xs font-semibold mt-3 mb-1">Vincular análisis</label>
        <div class="flex flex-wrap gap-2 items-center">
          <select class="home-analysis-select flex-1 min-w-[12rem] rounded-lg border px-2 py-2 text-sm" id="homeAnalysisSelect">
            <option value="">— Sin vincular —</option>
            ${options}
          </select>
          <button type="button" class="btn-secondary text-xs py-2 px-3" id="btnLinkAnalysis">Vincular</button>
        </div>
      </div>`;
  }

  function renderTeamBlock(project, editable) {
    const members = project.members || [];
    const list = members
      .map(
        (m) => `
        <li class="home-member-item">
          <div class="home-member-avatar">${escapeHtml((m.full_name || m.email || "?")[0].toUpperCase())}</div>
          <div class="home-member-info">
            <span class="home-member-name">${escapeHtml(m.full_name || m.email)}</span>
            <span class="home-member-email">${escapeHtml(m.email)}</span>
          </div>
          <span class="home-member-role">${m.role === "owner" ? "Propietario" : m.role === "editor" ? "Editor" : "Lector"}</span>
          ${
            editable && m.role !== "owner"
              ? `<button type="button" class="home-member-remove" data-user-id="${m.user_id}" title="Quitar">×</button>`
              : ""
          }
        </li>`
      )
      .join("");

    return `
      <div class="home-team-block">
        <div class="flex flex-wrap items-center justify-between gap-2 mb-4">
          <div>
            <p class="home-section-title">Equipo del proyecto</p>
            <p class="text-xs opacity-60 mt-1">Invita arquitectos, ingenieros o al cliente para colaborar.</p>
          </div>
          ${
            editable
              ? `<button type="button" class="btn-primary text-xs py-2 px-3" id="btnInviteMember">Invitar</button>`
              : ""
          }
        </div>
        <ul class="home-member-list">${list}</ul>
        <p class="text-xs opacity-50 mt-4">Los editores pueden crear apartados y subir archivos. Los lectores solo consultan.</p>
      </div>`;
  }

  function renderFilesBlock(project, editable) {
    const files = project.files || [];
    const rows = files.length
      ? files
          .map(
            (f) => `
          <tr>
            <td><button type="button" class="home-doc-name" data-dl-url="${escapeHtml(f.download_url)}" data-dl-name="${escapeHtml(f.filename)}">${escapeHtml(f.filename)}</button></td>
            <td class="text-xs opacity-70">Etapa ${f.stage_number}${f.section_title ? " · " + escapeHtml(f.section_title) : ""}</td>
            <td class="text-xs opacity-60">${formatBytes(f.file_size)}</td>
            <td class="text-right">${editable ? `<button type="button" class="home-doc-delete" data-doc-id="${f.id}">×</button>` : ""}</td>
          </tr>`
          )
          .join("")
      : `<tr><td colspan="4" class="text-sm opacity-50 py-4 text-center">Sin archivos en el proyecto</td></tr>`;

    return `
      <div class="home-files-block">
        <p class="home-section-title mb-3">Archivos del proyecto</p>
        <div class="home-files-table-wrap overflow-x-auto">
          <table class="home-files-table w-full text-sm">
            <thead>
              <tr>
                <th class="text-left">Archivo</th>
                <th class="text-left">Ubicación</th>
                <th class="text-left">Tamaño</th>
                <th></th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      </div>`;
  }

  function renderDetail(project) {
    const detail = $("#homeProjectsDetail");
    const empty = $("#homeProjectsEmpty");
    if (!detail) return;
    if (!project) {
      detail.innerHTML = "";
      if (empty) {
        empty.classList.remove("hidden");
        detail.appendChild(empty);
      }
      return;
    }
    if (empty) empty.classList.add("hidden");

    const shouldResetScroll = detailView !== lastDetailView;

    const editable = canEdit(project);
    const teamEditable = canManageTeam(project);
    const stageAdvanceable = canAdvanceStage(project);
    const projectDeletable = canDeleteProject(project);
    const stageReopenable = canReopenStage(project);
    const isCompleted = isProjectCompleted(project);
    const stageNum = viewedStage || project.current_stage;
    const stage =
      project.stages.find((s) => s.stage_number === stageNum) || project.stages[0];
    const openSection =
      detailView === "stage" && expandedSectionId != null
        ? (stage?.sections || []).find((s) => s.id === expandedSectionId) || null
        : null;
    if (!stage) {
      detail.innerHTML =
        '<p class="text-sm opacity-60 p-4">No se pudieron cargar las etapas del proyecto.</p>';
      return;
    }

    const viewTabs = [
      { id: "stage", label: "Etapa" },
      { id: "files", label: `Archivos (${(project.files || []).length})` },
      { id: "team", label: `Equipo (${(project.members || []).length})` },
      { id: "activity", label: "Actividad" },
    ];

    let mainContent = "";
    if (detailView === "files") {
      mainContent = renderFilesBlock(project, editable);
    } else if (detailView === "team") {
      mainContent = renderTeamBlock(project, teamEditable);
    } else if (detailView === "activity") {
      mainContent = renderActivityBlock(project);
    } else if (isCompleted && completionOverviewMode) {
      mainContent = renderCompletionBlock(project);
    } else {
      const completionBanner =
        isCompleted && !completionOverviewMode
          ? `<div class="home-completion-banner mb-4">
              <button type="button" class="home-completion-back" id="btnCompletionOverview">
                <span class="material-symbols-outlined" aria-hidden="true">arrow_back</span>
                Resumen de cierre
              </button>
            </div>`
          : "";
      mainContent = `
        ${completionBanner}
        <article class="glass-card home-stage-card p-4 md:p-5">
          <p class="text-[10px] font-bold uppercase tracking-widest opacity-50">Etapa ${stage.stage_number} de ${project.stages.length}</p>
          <h4 class="text-xl font-semibold mt-1">${escapeHtml(stage.title)}</h4>
          <p class="text-sm opacity-70 mt-2 leading-relaxed">${escapeHtml(stage.summary || "")}</p>
          <p class="mt-3 text-xs font-semibold uppercase tracking-wide opacity-50">Estado: ${statusLabel(stage.status)} · ${stage.sections_progress?.done || 0}/${stage.sections_progress?.total || 0} apartados</p>

          <div class="home-section mt-5">${renderSectionsBlock(stage, project, editable)}</div>

          ${
            (stage.documents || []).length
              ? `<div class="home-section mt-5">
                  <p class="home-section-title">Archivos generales de etapa</p>
                  <ul class="home-doc-list space-y-1 mb-2">${renderDocList(stage.documents, project.id, editable)}</ul>
                </div>`
              : ""
          }

          ${stage.plan_review && editable ? `<div class="home-section mt-5">${renderAnalysisBlock(stage)}</div>` : ""}

          <div class="home-section home-notes-section mt-5">
            <label class="home-notes-title block">Notas de etapa</label>
            <textarea class="home-notes-input home-notes-textarea mt-2 w-full border p-3 text-sm min-h-[88px]" id="homeStageNotes" placeholder="Añade notas, observaciones o requerimientos especiales para esta etapa del proyecto..." ${editable ? "" : "readonly"}>${escapeHtml(stage.notes || "")}</textarea>
          </div>

          ${
            editable
              ? `<div class="home-notes-actions flex flex-wrap gap-2 mt-5 pt-4 border-t border-black/10 dark:border-white/10">
                  <button type="button" class="btn-secondary home-notes-btn-secondary text-xs py-2 px-4" id="btnMarkInProgress">Marcar en curso</button>
                  <button type="button" class="btn-primary home-notes-btn-primary text-xs py-2 px-4" id="btnSaveStage">Guardar notas</button>
                  ${
                    stageReopenable && stage.status === "completed"
                      ? `<button type="button" class="btn-secondary text-xs py-2 px-4" id="btnReopenStage">Reabrir etapa</button>`
                      : ""
                  }
                </div>`
              : ""
          }
        </article>`;
    }

    detail.innerHTML = `
      <header class="home-project-header mb-0">
        <div class="home-project-header-top">
          <div class="home-project-header-copy">
            <p class="text-[10px] font-bold uppercase tracking-widest opacity-50">Proyecto · ${project.my_role === "admin" ? "Administrador" : project.my_role === "owner" ? "Propietario" : project.my_role === "editor" ? "Editor" : "Lector"}</p>
            <h3 class="home-project-title text-2xl font-semibold tracking-tight">${escapeHtml(project.name)}</h3>
            <div class="home-project-header-meta">
              <p class="home-project-subtitle text-sm opacity-65">${escapeHtml(project.client_name || "Cliente no indicado")}${project.location ? " · " + escapeHtml(project.location) : ""}</p>
              ${
                isCompleted
                  ? '<p class="home-project-status-badge is-completed">Proyecto completado</p>'
                  : ""
              }
            </div>
          </div>
          <div class="flex flex-wrap gap-2 home-header-actions">
            <button type="button" class="btn-secondary text-xs py-2 px-3" id="btnBackToIA">Volver a IA</button>
            ${
              isCompleted
                ? `<button type="button" class="btn-secondary text-xs py-2 px-3" id="btnCompletionOverviewHeader">Resumen de cierre</button>`
                : `<button type="button" class="btn-secondary text-xs py-2 px-3 ${stageAdvanceable ? "" : "home-action-disabled"}" id="btnAdvanceStage" ${stageAdvanceable ? "" : "disabled"} title="${stageAdvanceable ? "Completar etapa actual" : "Solo propietario o administrador"}">Completar etapa</button>`
            }
            <button type="button" class="btn-secondary text-xs py-2 px-3 text-red-600 dark:text-red-400 ${projectDeletable ? "" : "home-action-disabled"}" id="btnDeleteProject" ${projectDeletable ? "" : "disabled"} title="${projectDeletable ? "Eliminar proyecto" : "Solo propietario o administrador"}">Eliminar</button>
          </div>
        </div>
        <div class="home-view-tabs flex flex-wrap gap-2 mt-4 pb-1">
          ${viewTabs
            .map(
              (t) =>
                `<button type="button" class="home-view-tab ${detailView === t.id ? "is-active" : ""}" data-view="${t.id}">${t.label}</button>`
            )
            .join("")}
        </div>
      </header>
      ${
        detailView === "stage"
          ? `<div class="home-stage-rail">
              <div class="home-stage-track" id="homeStageTrack">
                ${project.stages
                  .map((s) => {
                    const cls = [
                      "home-stage-dot",
                      s.status === "completed" ? "is-done" : "",
                      !completionOverviewMode && s.stage_number === stageNum ? "is-current" : "",
                      completionOverviewMode && isCompleted ? "is-overview" : "",
                    ]
                      .filter(Boolean)
                      .join(" ");
                    return `<button type="button" class="${cls}" data-stage="${s.stage_number}" title="${escapeHtml(s.title)}">${s.stage_number}</button>`;
                  })
                  .join("")}
              </div>
            </div>`
          : ""
      }

      <div class="home-stage-layout" id="homeProjectDetailScroll">${mainContent}</div>
      ${detailView === "stage" && !completionOverviewMode ? renderModuleOverlay(project, openSection, editable) : ""}`;

    const track = detail.querySelector("#homeStageTrack");
    if (track) {
      const totalStages = project.stages.length;
      const progressStage = completionOverviewMode && isCompleted ? totalStages : stageNum;
      const pct =
        totalStages > 1
          ? Math.max(0, Math.min(100, ((progressStage - 1) / (totalStages - 1)) * 100))
          : 0;
      track.style.gridTemplateColumns = `repeat(${totalStages}, minmax(0, 1fr))`;
      track.style.setProperty("--hp-stage-progress", String(pct / 100));
    }

    detail.querySelectorAll(".home-view-tab").forEach((btn) => {
      btn.onclick = () => {
        detailView = btn.dataset.view;
        if (detailView === "stage" && isProjectCompleted(project)) {
          completionOverviewMode = true;
        }
        if (detailView === "activity") {
          loadActivity(project.id, true).then(() => renderDetail(project));
          return;
        }
        renderDetail(project);
      };
    });

    detail.querySelectorAll(".home-section-filter").forEach((btn) => {
      btn.onclick = () => {
        sectionFilter = btn.dataset.filter || "all";
        expandedSectionId = null;
        renderDetail(project);
      };
    });

    bindClick("#btnLoadMoreActivity", async () => {
      await loadActivity(project.id, false);
      renderDetail(project);
    });

    detail.querySelector("#homeStageTrack")?.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-stage]");
      if (!btn) return;
      viewedStage = Number(btn.dataset.stage);
      completionOverviewMode = false;
      renderDetail(project);
    });

    function bindClick(selector, handler) {
      const el = detail.querySelector(selector);
      if (el) el.onclick = handler;
    }

    bindClick("#btnSaveStage", () => saveStage(project.id, stage.stage_number));
    bindClick("#btnMarkInProgress", () =>
      patchStage(project.id, stage.stage_number, { status: "in_progress" }));
    bindClick("#btnBackToIA", () => close());
    bindClick("#btnAdvanceStage", () => advanceStage(project.id));
    bindClick("#btnCompletionOverview", () => {
      completionOverviewMode = true;
      renderDetail(project);
    });
    bindClick("#btnCompletionOverviewHeader", () => {
      completionOverviewMode = true;
      detailView = "stage";
      renderDetail(project);
    });
    bindClick("#btnCompletionAllFiles", () => {
      detailView = "files";
      renderDetail(project);
    });
    bindClick("#btnCompletionTeam", () => {
      detailView = "team";
      renderDetail(project);
    });
    bindClick("#btnCompletionActivity", () => {
      detailView = "activity";
      loadActivity(project.id, true).then(() => renderDetail(project));
    });
    bindClick("#btnCompletionBrowseStages", () => {
      completionOverviewMode = false;
      viewedStage = project.current_stage || project.stages.length;
      renderDetail(project);
    });
    bindClick("#btnReopenStage", () => reopenStage(project.id, stage.stage_number));
    bindClick("#btnDeleteProject", () => deleteProject(project.id));
    bindClick("#btnInviteMember", () => openInviteModal(project.id));
    bindClick("#btnAddSection", () => openSectionModal(project.id, stage.stage_number));
    bindClick("#homeCreateSectionCard", () => openSectionModal(project.id, stage.stage_number));
    bindClick("#btnCloseModuleOverlay", () => {
      expandedSectionId = null;
      rerenderDetailPreservingScroll(project);
    });

    detail.querySelector("#homeModuleOverlay")?.addEventListener("click", (e) => {
      if (e.target.id === "homeModuleOverlay") {
        expandedSectionId = null;
        rerenderDetailPreservingScroll(project);
      }
    });

    const overlay = detail.querySelector("#homeModuleOverlay");
    if (overlay) {
      overlay.setAttribute("tabindex", "-1");
      overlay.focus();
      overlay.addEventListener("keydown", (e) => {
        if (e.key === "Escape" && expandedSectionId != null) {
          expandedSectionId = null;
          rerenderDetailPreservingScroll(project);
        }
      });
    }

    detail.querySelectorAll("[data-open-section]").forEach((btn) => {
      btn.onclick = (e) => {
        e.stopPropagation();
        const sectionId = Number(btn.dataset.openSection);
        if (!sectionId) return;
        expandedSectionId = expandedSectionId === sectionId ? null : sectionId;
        rerenderDetailPreservingScroll(project);
      };
    });

    detail.querySelectorAll(".home-module-card").forEach((card) => {
      card.onclick = (e) => {
        const target = e.target;
        if (
          target.closest("button") ||
          target.closest("input") ||
          target.closest("select") ||
          target.closest("textarea") ||
          target.closest("label") ||
          target.closest("a")
        ) {
          return;
        }
        const sectionId = Number(card.dataset.sectionId);
        if (!sectionId) return;
        expandedSectionId = sectionId;
        rerenderDetailPreservingScroll(project);
      };
    });

    bindClick("#btnLinkAnalysis", () => {
      const sel = detail.querySelector("#homeAnalysisSelect");
      const val = sel?.value;
      patchStage(project.id, stage.stage_number, { analysis_id: val ? Number(val) : 0 });
    });

    detail.querySelectorAll(".home-section-file-input").forEach((input) => {
      input.addEventListener("change", (e) => {
        const file = e.target.files?.[0];
        const sectionId = Number(input.dataset.sectionId);
        if (file && sectionId) uploadDocument(project.id, stage.stage_number, file, sectionId);
        e.target.value = "";
      });
    });

    detail.querySelectorAll(".home-section-delete").forEach((btn) => {
      btn.onclick = async () => {
        if (
          !(await PlanoDialog.confirm(
            "¿Eliminar este apartado y sus archivos? Solo el propietario o un administrador pueden hacerlo.",
            { title: "Eliminar apartado", variant: "danger", confirmLabel: "Eliminar" }
          ))
        ) {
          return;
        }
        deleteSection(project.id, Number(btn.dataset.sectionId));
      };
    });

    detail.querySelectorAll(".home-section-reopen-submit").forEach((btn) => {
      btn.onclick = async () => {
        const sectionId = Number(btn.dataset.sectionId);
        const block = btn.closest(".home-reopen-block");
        const status = block?.querySelector(".home-section-reopen-status")?.value || "in_progress";
        const reason = (block?.querySelector(".home-section-reopen-reason")?.value || "").trim();
        if (reason.length < 10) {
          window.showToast?.("Indica el motivo de reapertura (mínimo 10 caracteres)");
          block?.querySelector(".home-section-reopen-reason")?.focus();
          return;
        }
        if (
          !(await PlanoDialog.confirm(
            "¿Reabrir este apartado completado? La etapa también se reabrirá si estaba cerrada.",
            { title: "Reabrir apartado", confirmLabel: "Reabrir" }
          ))
        ) {
          return;
        }
        patchSection(project.id, sectionId, {
          status,
          reopen_reason: reason,
        });
      };
    });

    detail.querySelectorAll(".home-section-assignee").forEach((sel) => {
      sel.addEventListener("change", () => {
        const sectionId = Number(sel.dataset.sectionId);
        const val = sel.value;
        const payload =
          val === "" ? { assigned_to_user_id: null } : { assigned_to_user_id: Number(val) };
        patchSection(project.id, sectionId, payload);
      });
    });

    detail.querySelectorAll(".home-section-load-comments").forEach((btn) => {
      btn.onclick = () => loadSectionComments(project.id, Number(btn.dataset.sectionId));
    });

    detail.querySelectorAll(".home-section-review-submit").forEach((btn) => {
      btn.onclick = () => {
        const sectionId = Number(btn.dataset.sectionId);
        const card = btn.closest(".home-review-block");
        const statusSel = card?.querySelector(".home-section-review-status");
        const commentEl = card?.querySelector(".home-section-review-comment");
        const status = statusSel?.value || "in_progress";
        const reviewComment = (commentEl?.value || "").trim();
        if (
          (status === "needs_details" || status === "needs_correction") &&
          !reviewComment
        ) {
          window.showToast?.(
            "Añade un comentario explicando qué se debe corregir u observar"
          );
          commentEl?.focus();
          return;
        }
        const payload = { status };
        if (reviewComment) payload.review_comment = reviewComment;
        patchSection(project.id, sectionId, payload).then(() => {
          if (commentEl) commentEl.value = "";
        });
      };
    });

    detail.querySelectorAll(".home-comment-delete").forEach((btn) => {
      btn.onclick = async () => {
        const sectionId = Number(btn.dataset.sectionId);
        const commentId = Number(btn.dataset.commentId);
        if (!sectionId || !commentId) return;
        if (
          !(await PlanoDialog.confirm("¿Eliminar este comentario?", {
            title: "Eliminar comentario",
            variant: "danger",
            confirmLabel: "Eliminar",
          }))
        ) {
          return;
        }
        deleteComment(project.id, sectionId, commentId);
      };
    });

    detail.querySelectorAll(".home-doc-delete").forEach((btn) => {
      btn.onclick = async () => {
        const docId = Number(btn.dataset.docId);
        if (!docId) return;
        if (
          !(await PlanoDialog.confirm("¿Eliminar este archivo?", {
            title: "Eliminar archivo",
            variant: "danger",
            confirmLabel: "Eliminar",
          }))
        ) {
          return;
        }
        deleteDocument(project.id, docId);
      };
    });

    detail.querySelectorAll(".home-doc-name[data-dl-url]").forEach((btn) => {
      btn.onclick = () => downloadDocument(btn.dataset.dlUrl, btn.dataset.dlName);
    });

    detail.querySelectorAll(".home-member-remove").forEach((btn) => {
      btn.onclick = async () => {
        const uid = Number(btn.dataset.userId);
        if (!uid) return;
        if (
          !(await PlanoDialog.confirm("¿Quitar a esta persona del proyecto?", {
            title: "Quitar colaborador",
            variant: "danger",
            confirmLabel: "Quitar",
          }))
        ) {
          return;
        }
        removeMember(project.id, uid);
      };
    });

    if (stage.plan_review && editable && !analysesLoaded) {
      ensureAnalysesPicker().then(() => {
        const latest = projects.find((p) => p.id === project.id);
        if (latest && activeId === project.id) renderDetail(latest);
      });
    }

    if (shouldResetScroll) resetDetailScroll();
    lastDetailView = detailView;
  }

  function rerenderDetailPreservingScroll(project) {
    const scrollEl = getDetailScrollEl();
    const currentScroll = scrollEl ? scrollEl.scrollTop : 0;
    renderDetail(project);
    const nextScroll = getDetailScrollEl();
    if (nextScroll) nextScroll.scrollTop = currentScroll;
  }

  async function downloadDocument(url, filename) {
    try {
      const res = await PlanoAuth.apiFetch(url);
      if (!res.ok) throw new Error("No se pudo descargar");
      const blob = await res.blob();
      const objUrl = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = objUrl;
      a.download = filename || "documento";
      a.click();
      URL.revokeObjectURL(objUrl);
    } catch (err) {
      window.showToast?.(err.message || "Error al descargar");
    }
  }

  async function saveStage(projectId, stageNumber) {
    const notes = $("#homeStageNotes")?.value || "";
    await patchStage(projectId, stageNumber, { notes });
  }

  async function patchStage(projectId, stageNumber, payload) {
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/stages/${stageNumber}`,
      { method: "PATCH", body: JSON.stringify(payload) }
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo actualizar la etapa");
      return;
    }
    const idx = projects.findIndex((p) => p.id === projectId);
    if (idx >= 0) projects[idx] = data;
    renderList();
    renderDetail(projects[idx]);
    if (payload.reopen_reason) {
      window.showToast?.("Etapa reabierta");
    } else if (payload.analysis_id !== undefined) {
      window.showToast?.(payload.analysis_id ? "Análisis vinculado" : "Análisis desvinculado");
    } else if (payload.notes !== undefined) {
      window.showToast?.("Notas guardadas");
    }
  }

  async function loadActivity(projectId, reset) {
    if (activityLoading) return;
    activityLoading = true;
    try {
      const offset = reset ? 0 : activityOffset;
      const res = await PlanoAuth.apiFetch(
        `/api/home-projects/${encodeURIComponent(projectId)}/events?limit=30&offset=${offset}`
      );
      const data = await res.json();
      if (!res.ok) {
        window.showToast?.(data.detail || "No se pudo cargar la actividad");
        return;
      }
      activityEvents = reset ? data.events || [] : activityEvents.concat(data.events || []);
      activityOffset = data.next_offset || activityEvents.length;
      activityHasMore = !!data.has_more;
    } finally {
      activityLoading = false;
    }
  }

  async function loadSectionComments(projectId, sectionId) {
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/sections/${sectionId}/comments?limit=200&offset=0`
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudieron cargar los comentarios");
      return;
    }
    const project = projects.find((p) => p.id === projectId);
    if (!project) return;
    for (const stage of project.stages || []) {
      const sec = (stage.sections || []).find((s) => s.id === sectionId);
      if (sec) {
        sec.comments = data.comments || [];
        break;
      }
    }
    renderDetail(project);
  }

  async function patchSection(projectId, sectionId, payload) {
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/sections/${sectionId}`,
      { method: "PATCH", body: JSON.stringify(payload) }
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo actualizar el apartado");
      return;
    }
    const idx = projects.findIndex((p) => p.id === projectId);
    if (idx >= 0) projects[idx] = data;
    renderDetail(projects[idx]);
    if (payload.reopen_reason) {
      window.showToast?.("Apartado reabierto");
    } else if (Object.prototype.hasOwnProperty.call(payload, "assigned_to_user_id")) {
      window.showToast?.(
        payload.assigned_to_user_id == null ? "Responsable quitado" : "Responsable asignado"
      );
    } else if (payload.status || payload.review_comment) {
      window.showToast?.("Revisión guardada");
    } else {
      window.showToast?.("Cambios guardados");
    }
  }

  async function deleteSection(projectId, sectionId) {
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/sections/${sectionId}`,
      { method: "DELETE" }
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo eliminar");
      return;
    }
    const idx = projects.findIndex((p) => p.id === projectId);
    if (idx >= 0) projects[idx] = data;
    renderDetail(projects[idx]);
    window.showToast?.("Apartado eliminado");
  }

  async function addComment(projectId, sectionId, body) {
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/sections/${sectionId}/comments`,
      { method: "POST", body: JSON.stringify({ body }) }
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo publicar el comentario");
      return;
    }
    const idx = projects.findIndex((p) => p.id === projectId);
    if (idx >= 0) projects[idx] = data;
    renderDetail(projects[idx]);
    window.showToast?.("Comentario añadido");
  }

  async function deleteComment(projectId, sectionId, commentId) {
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/sections/${sectionId}/comments/${commentId}`,
      { method: "DELETE" }
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo eliminar el comentario");
      return;
    }
    const idx = projects.findIndex((p) => p.id === projectId);
    if (idx >= 0) projects[idx] = data;
    renderDetail(projects[idx]);
    window.showToast?.("Comentario eliminado");
  }

  async function uploadDocument(projectId, stageNumber, file, sectionId) {
    const fd = new FormData();
    fd.append("file", file);
    if (sectionId) fd.append("section_id", String(sectionId));
    try {
      const res = await PlanoAuth.apiFetch(
        `/api/home-projects/${encodeURIComponent(projectId)}/stages/${stageNumber}/documents`,
        { method: "POST", body: fd }
      );
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || "No se pudo subir el archivo");
      const idx = projects.findIndex((p) => p.id === projectId);
      if (idx >= 0) projects[idx] = data.project || data;
      renderDetail(projects[idx]);
      window.showToast?.("Archivo subido");
    } catch (err) {
      window.showToast?.(err.message || "Error al subir");
    }
  }

  async function deleteDocument(projectId, documentId) {
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/documents/${documentId}`,
      { method: "DELETE" }
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo eliminar");
      return;
    }
    const idx = projects.findIndex((p) => p.id === projectId);
    if (idx >= 0) projects[idx] = data;
    renderDetail(projects[idx]);
    window.showToast?.("Archivo eliminado");
  }

  async function advanceStage(projectId) {
    if (
      !(await PlanoDialog.confirm(
        "¿Marcar la etapa actual como completada y avanzar a la siguiente? Solo el propietario o un administrador pueden hacerlo.",
        { title: "Completar etapa", confirmLabel: "Completar" }
      ))
    ) {
      return;
    }
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/advance`,
      { method: "POST" }
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo avanzar");
      return;
    }
    const idx = projects.findIndex((p) => p.id === projectId);
    if (idx >= 0) projects[idx] = data;
    viewedStage = data.current_stage;
    const justCompleted = isProjectCompleted(data);
    completionOverviewMode = justCompleted;
    if (justCompleted) {
      window.showToast?.("¡Proyecto completado!", {
        variant: "success",
        icon: "celebration",
        duration: 6200,
      });
    } else {
      window.showToast?.("Etapa avanzada", { variant: "success", icon: "flag" });
    }
    renderList();
    renderDetail(projects[idx]);
  }

  async function reopenStage(projectId, stageNumber) {
    const reason = await promptReopenReason("Reabrir etapa completada");
    if (!reason) return;
    if (
      !(await PlanoDialog.confirm("¿Confirmas la reapertura de esta etapa?", {
        title: "Reabrir etapa",
        confirmLabel: "Reabrir",
      }))
    ) {
      return;
    }
    await patchStage(projectId, stageNumber, {
      status: "in_progress",
      reopen_reason: reason,
    });
  }

  async function deleteProject(projectId) {
    if (
      !(await PlanoDialog.confirm(
        "¿Eliminar este proyecto? No se puede deshacer. Solo el propietario o un administrador pueden hacerlo.",
        { title: "Eliminar proyecto", variant: "danger", confirmLabel: "Eliminar" }
      ))
    ) {
      return;
    }
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}`,
      { method: "DELETE" }
    );
    if (!res.ok) {
      const data = await res.json();
      window.showToast?.(data.detail || "No se pudo eliminar");
      return;
    }
    activeId = null;
    viewedStage = null;
    await loadProjects();
    window.showToast?.("Proyecto eliminado");
  }

  async function removeMember(projectId, userId) {
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/members/${userId}`,
      { method: "DELETE" }
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo quitar al miembro");
      return;
    }
    const idx = projects.findIndex((p) => p.id === projectId);
    if (idx >= 0) projects[idx] = data;
    renderDetail(projects[idx]);
    window.showToast?.("Miembro eliminado");
  }

  let pendingSectionProjectId = null;
  let pendingSectionStage = null;
  let pendingInviteProjectId = null;

  function openSectionModal(projectId, stageNumber) {
    pendingSectionProjectId = projectId;
    pendingSectionStage = stageNumber;
    $("#homeSectionTitle") && ($("#homeSectionTitle").value = "");
    $("#homeSectionDescription") && ($("#homeSectionDescription").value = "");
    const dlg = $("#homeSectionModal");
    if (!dlg) return;
    if (typeof dlg.showModal === "function") dlg.showModal();
    else dlg.setAttribute("open", "");
  }

  function closeSectionModal() {
    pendingSectionProjectId = null;
    pendingSectionStage = null;
    const dlg = $("#homeSectionModal");
    if (!dlg) return;
    if (typeof dlg.close === "function") dlg.close();
    else dlg.removeAttribute("open");
  }

  async function createSectionFromForm(event) {
    event.preventDefault();
    const title = ($("#homeSectionTitle")?.value || "").trim();
    const description = ($("#homeSectionDescription")?.value || "").trim();
    if (!pendingSectionProjectId || !pendingSectionStage) return;
    if (title.length < 2) {
      window.showToast?.("El título debe tener al menos 2 caracteres");
      return;
    }
    const projectId = pendingSectionProjectId;
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/stages/${pendingSectionStage}/sections`,
      { method: "POST", body: JSON.stringify({ title, description }) }
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo crear el apartado");
      return;
    }
    closeSectionModal();
    const idx = projects.findIndex((p) => p.id === projectId);
    if (idx >= 0) projects[idx] = data;
    renderDetail(projects[idx]);
    window.showToast?.("Apartado creado");
  }

  function buildInviteUrl(token) {
    return `${window.location.origin}/legacy-app?invite=${encodeURIComponent(token)}`;
  }

  function resetInviteModal() {
    $("#homeInviteForm")?.classList.remove("hidden");
    $("#homeInviteResult")?.classList.add("hidden");
    $("#homeInviteResult")?.setAttribute("hidden", "");
    $("#homeInviteEmail") && ($("#homeInviteEmail").value = "");
    $("#homeInviteLink") && ($("#homeInviteLink").value = "");
  }

  function showInviteLink(email, token) {
    const form = $("#homeInviteForm");
    const result = $("#homeInviteResult");
    const link = buildInviteUrl(token);
    if (form) form.classList.add("hidden");
    if (result) {
      result.classList.remove("hidden");
      result.removeAttribute("hidden");
    }
    const emailEl = $("#homeInviteResultEmail");
    const linkEl = $("#homeInviteLink");
    if (emailEl) emailEl.textContent = email;
    if (linkEl) linkEl.value = link;
  }

  async function handlePendingInvite() {
    const params = new URLSearchParams(window.location.search);
    const token = params.get("invite") || sessionStorage.getItem("pending_invite");
    if (!token) return;
    if (typeof PlanoAuth?.getToken !== "function" || !PlanoAuth.getToken()) {
      sessionStorage.setItem("pending_invite", token);
      return;
    }
    try {
      const res = await PlanoAuth.apiFetch("/api/home-projects/invites/accept", {
        method: "POST",
        body: JSON.stringify({ token }),
      });
      const data = await res.json();
      sessionStorage.removeItem("pending_invite");
      window.history.replaceState({}, "", "/legacy-app");
      if (!res.ok) {
        window.showToast?.(data.detail || "No se pudo aceptar la invitación");
        return;
      }
      activeId = data.id;
      viewedStage = data.current_stage || 1;
      await loadProjects();
      open();
      window.showToast?.("Te uniste al proyecto");
    } catch (err) {
      window.showToast?.(err.message || "Error al aceptar invitación");
    }
  }

  function openInviteModal(projectId) {
    pendingInviteProjectId = projectId;
    resetInviteModal();
    const dlg = $("#homeInviteModal");
    if (!dlg) return;
    if (typeof dlg.showModal === "function") dlg.showModal();
    else dlg.setAttribute("open", "");
  }

  function closeInviteModal() {
    pendingInviteProjectId = null;
    resetInviteModal();
    const dlg = $("#homeInviteModal");
    if (!dlg) return;
    if (typeof dlg.close === "function") dlg.close();
    else dlg.removeAttribute("open");
  }

  async function inviteFromForm(event) {
    event.preventDefault();
    const email = ($("#homeInviteEmail")?.value || "").trim();
    const role = $("#homeInviteRole")?.value || "editor";
    if (!pendingInviteProjectId || !email) return;
    const projectId = pendingInviteProjectId;
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/members/invite`,
      { method: "POST", body: JSON.stringify({ email, role }) }
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo invitar");
      return;
    }
    if (data.status === "invite_created") {
      showInviteLink(email, data.token);
      window.showToast?.(
        data.email_sent
          ? `Invitación enviada por correo a ${email}`
          : `Invitación creada para ${email} (copia el enlace manualmente)`
      );
    } else {
      closeInviteModal();
      window.showToast?.(`${email} añadido al proyecto`);
      await loadProjects();
      selectProject(projectId || activeId);
    }
  }

  async function copyInviteLink() {
    const link = $("#homeInviteLink")?.value;
    if (!link) return;
    try {
      await navigator.clipboard.writeText(link);
      window.showToast?.("Enlace copiado");
    } catch {
      $("#homeInviteLink")?.select();
      document.execCommand("copy");
      window.showToast?.("Enlace copiado");
    }
  }

  function openCreateModal() {
    const dlg = $("#homeProjectCreateModal");
    if (!dlg) return;
    $("#homeProjectCreateForm")?.reset();
    if (typeof dlg.showModal === "function") dlg.showModal();
    else dlg.setAttribute("open", "");
  }

  function closeCreateModal() {
    const dlg = $("#homeProjectCreateModal");
    if (!dlg) return;
    if (typeof dlg.close === "function") dlg.close();
    else dlg.removeAttribute("open");
  }

  async function createProjectFromForm(event) {
    event.preventDefault();
    const name = ($("#hpCreateName")?.value || "").trim();
    const clientName = ($("#hpCreateClient")?.value || "").trim();
    const location = ($("#hpCreateLocation")?.value || "").trim();
    const description = ($("#hpCreateDescription")?.value || "").trim();
    if (name.length < 2) {
      window.showToast?.("El nombre debe tener al menos 2 caracteres");
      return;
    }
    const res = await PlanoAuth.apiFetch("/api/home-projects", {
      method: "POST",
      body: JSON.stringify({ name, client_name: clientName, location, description }),
    });
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo crear el proyecto");
      return;
    }
    closeCreateModal();
    projects.unshift(data);
    viewedStage = 1;
    selectProject(data.id);
    renderList();
    window.showToast?.("Proyecto creado");
  }

  $("#btnNewHomeProject")?.addEventListener("click", openCreateModal);
  $("#btnCloseHomeProjectCreate")?.addEventListener("click", closeCreateModal);
  $("#btnCancelHomeProjectCreate")?.addEventListener("click", closeCreateModal);
  $("#homeProjectCreateForm")?.addEventListener("submit", createProjectFromForm);

  $("#btnCloseHomeSection")?.addEventListener("click", closeSectionModal);
  $("#btnCancelHomeSection")?.addEventListener("click", closeSectionModal);
  $("#homeSectionForm")?.addEventListener("submit", createSectionFromForm);

  $("#btnCloseHomeInvite")?.addEventListener("click", closeInviteModal);
  $("#btnCancelHomeInvite")?.addEventListener("click", closeInviteModal);
  $("#btnCloseInviteResult")?.addEventListener("click", closeInviteModal);
  $("#btnCopyInviteLink")?.addEventListener("click", copyInviteLink);
  $("#homeInviteForm")?.addEventListener("submit", inviteFromForm);

  $("#homeProjectsSearch")?.addEventListener("input", (e) => {
    projectSearchQuery = e.target.value || "";
    renderList();
  });

  $("#btnSwitchToMainSidebar")?.addEventListener("click", () => {
    const isCollapsed = document.body.classList.contains("sidebar-collapsed");
    if (!isCollapsed) {
      window.showToast?.("El panel principal ya está abierto");
      return;
    }
    closeProjectsDrawer();
    document.querySelector("#btnMenuFloat")?.click();
  });
  $("#btnHomeProjectsDrawerToggle")?.addEventListener("click", toggleProjectsDrawer);
  $("#homeProjectsDrawerBackdrop")?.addEventListener("click", closeProjectsDrawer);
  $("#btnMenu")?.addEventListener("click", () => {
    const isCollapsed = document.body.classList.contains("sidebar-collapsed");
    if (isMobileViewport() && isCollapsed) {
      closeProjectsDrawer();
    }
  });
  $("#btnMenuFloat")?.addEventListener("click", () => {
    if (isMobileViewport()) {
      closeProjectsDrawer();
    }
  });
  window.addEventListener("resize", () => {
    if (!isMobileViewport()) closeProjectsDrawer();
  });

  handlePendingInvite();

  window.HomeProjectsUI = { open, close, loadProjects };
})();
