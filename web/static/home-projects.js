
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
  let completionOverviewMode = false;
  let lastDetailView = "stage";
  let assistChatOpen = false;
  /** @type {Record<string, Array<{role: string, text: string}>>} */
  let assistChatHistory = {};
  let assistChatBusy = false;

  function assistChatKey(projectId, stageNumber) {
    return `${projectId}:${stageNumber}`;
  }

  function getAssistHistory(projectId, stageNumber) {
    const key = assistChatKey(projectId, stageNumber);
    if (!assistChatHistory[key]) assistChatHistory[key] = [];
    return assistChatHistory[key];
  }

  function currentAssistContext() {
    const project = projects.find((p) => p.id === activeId);
    if (!project) return null;
    const stageNum = viewedStage || project.current_stage || 1;
    const stage = project.stages?.find((s) => s.stage_number === stageNum);
    if (!stage || stage.ai_ask === false) return null;
    const editable =
      project.my_role === "owner" ||
      project.my_role === "editor" ||
      project.my_role === "admin";
    return { project, stage, editable, stageNum };
  }

  function ensureAssistFab() {
    let root = document.getElementById("homeAssistFabRoot");
    if (root) return root;
    root = document.createElement("div");
    root.id = "homeAssistFabRoot";
    root.className = "home-assist-fab-root";
    root.hidden = true;
    root.innerHTML = `
      <div class="home-assist-chat" id="homeAssistChat" hidden>
        <header class="home-assist-chat-head">
          <div>
            <p class="home-assist-chat-title">Asistente IA</p>
            <p class="home-assist-chat-sub" id="homeAssistChatSub">Dudas de esta etapa</p>
          </div>
          <div class="home-assist-chat-head-actions">
            <span class="home-ai-scope-badge">Apoyo</span>
            <button type="button" class="home-assist-chat-close" id="btnHomeAssistClose" aria-label="Cerrar chat">✕</button>
          </div>
        </header>
        <div class="home-assist-chat-messages" id="homeAssistChatMessages" role="log" aria-live="polite"></div>
        <p class="home-assist-chat-disclaimer">No lee el contenido de tus PDF/Office; usa el contexto de la etapa.</p>
        <form class="home-assist-chat-composer" id="homeAssistChatForm">
          <textarea id="homeAiQuestion" class="home-assist-chat-input" rows="2" maxlength="2000" placeholder="Pregunta sobre esta etapa…"></textarea>
          <button type="submit" class="home-assist-chat-send" id="btnHomeAssist" aria-label="Enviar">
            <span class="material-symbols-outlined" aria-hidden="true">send</span>
          </button>
        </form>
      </div>
      <button type="button" class="home-assist-fab" id="btnHomeAssistFab" aria-label="Abrir asistente IA" title="Asistente IA">
        <span class="material-symbols-outlined" aria-hidden="true">smart_toy</span>
        <span class="home-assist-fab-label">IA</span>
      </button>
    `;
    document.body.appendChild(root);

    root.querySelector("#btnHomeAssistFab")?.addEventListener("click", () => {
      assistChatOpen = !assistChatOpen;
      syncAssistChatUi();
      if (assistChatOpen) {
        root.querySelector("#homeAiQuestion")?.focus();
      }
    });
    root.querySelector("#btnHomeAssistClose")?.addEventListener("click", () => {
      assistChatOpen = false;
      syncAssistChatUi();
    });
    root.querySelector("#homeAssistChatForm")?.addEventListener("submit", (e) => {
      e.preventDefault();
      const ctx = currentAssistContext();
      if (!ctx || !ctx.editable) return;
      askStageAssist(ctx.project.id, ctx.stageNum);
    });
    root.querySelector("#homeAiQuestion")?.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        root.querySelector("#homeAssistChatForm")?.requestSubmit();
      }
    });
    return root;
  }

  function renderAssistMessages(projectId, stageNumber, stage) {
    const box = document.getElementById("homeAssistChatMessages");
    if (!box) return;
    const history = getAssistHistory(projectId, stageNumber);
    if (!history.length && stage?.ai_guidance) {
      history.push({ role: "assistant", text: stage.ai_guidance });
    }
    if (!history.length) {
      box.innerHTML = `
        <div class="home-assist-msg home-assist-msg--bot">
          <p>Hola. Puedo orientarte sobre esta etapa con normas y buenas prácticas. ¿Qué necesitas?</p>
        </div>`;
      return;
    }
    box.innerHTML = history
      .map(
        (m) => `
      <div class="home-assist-msg home-assist-msg--${m.role === "user" ? "user" : "bot"}">
        <p>${escapeHtml(m.text)}</p>
      </div>`
      )
      .join("");
    box.scrollTop = box.scrollHeight;
  }

  function syncAssistChatUi() {
    const root = ensureAssistFab();
    const inHome = document.body.classList.contains("home-projects-mode");
    const ctx = currentAssistContext();
    const show = inHome && !!activeId && !!ctx && detailView === "stage" && !completionOverviewMode;
    root.hidden = !show;
    if (!show) {
      assistChatOpen = false;
    }
    const chat = root.querySelector("#homeAssistChat");
    const fab = root.querySelector("#btnHomeAssistFab");
    if (chat) chat.hidden = !assistChatOpen;
    if (fab) {
      fab.classList.toggle("is-open", assistChatOpen);
      fab.setAttribute("aria-expanded", assistChatOpen ? "true" : "false");
    }
    if (show && ctx) {
      const sub = root.querySelector("#homeAssistChatSub");
      if (sub) {
        sub.textContent = `Etapa ${ctx.stage.stage_number}: ${ctx.stage.title}`;
      }
      const input = root.querySelector("#homeAiQuestion");
      const send = root.querySelector("#btnHomeAssist");
      if (input) input.disabled = !ctx.editable || assistChatBusy;
      if (send) send.disabled = !ctx.editable || assistChatBusy;
      if (assistChatOpen) {
        renderAssistMessages(ctx.project.id, ctx.stageNum, ctx.stage);
      }
    }
  }

  function escapeHtml(s) {
    return String(s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function apiErrorMessage(data, fallback) {
    if (!data) return fallback;
    if (typeof data.detail === "string") return data.detail;
    if (data.detail?.message) return data.detail.message;
    return fallback;
  }

  function planCaps() {
    const sub = window.PlanoAuth?.getSubscription?.() || null;
    const caps = sub?.plan?.capabilities || sub?.plan?.features || {};
    return {
      homeProjects: caps.home_projects !== false,
      teamInvites: !!caps.team_invites,
      maxProjects: Number(caps.max_projects ?? 1),
      export: !!caps.export,
      mobileApp: !!caps.mobile_app,
    };
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
      pending: "Sin entregar",
      in_progress: "En revisión",
      needs_details: "Faltan datos",
      needs_correction: "Corregir",
      completed: "Aprobado",
    };
    return map[status] || status;
  }

  function sectionReviewCriteria(sec, stage) {
    const slots = (sec?.slots || []).filter((s) => s.key !== "_other");
    if (slots.length) {
      return slots.map((s) => (s.required ? `${s.title} (obligatorio)` : s.title));
    }
    const title = (sec?.title || "").toLowerCase();
    const stageTitle = (stage?.title || "").toLowerCase();
    const base = ["Archivo correcto", "Info completa", "Cuadra con la etapa"];
    if (title.includes("necesidad") || title.includes("programa") || title.includes("cliente")) {
      return ["Espacios documentados", "Restricciones / plazos", "Acuerdo del cliente"];
    }
    if (title.includes("terreno") || title.includes("sitio") || title.includes("foto")) {
      return ["Evidencia del sitio", "Accesos / servicios", "Restricciones del predio"];
    }
    if (title.includes("plano") || title.includes("planta") || stageTitle.includes("arquitect")) {
      return ["Planta legible", "Cotas suficientes", "IA de planta si aplica"];
    }
    if (title.includes("presupuesto") || title.includes("cronograma") || title.includes("costo")) {
      return ["Partidas claras", "Alineado al ejecutivo", "Montos / fechas"];
    }
    return base;
  }

  function renderCriteriaChips(sec, stage) {
    return `<div class="home-review-chips" aria-label="Criterios">${sectionReviewCriteria(sec, stage)
      .map((c) => `<span class="home-review-chip">${escapeHtml(c)}</span>`)
      .join("")}</div>`;
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
    section_status_changed: "cambió el estado de revisión del equipo",
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
    ai_review_created: "lanzó una revisión IA de plano",
    ai_finding_updated: "actualizó un hallazgo de IA",
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

  function sectionPlanReviewDocs(sec, stage) {
    if (!(stage?.ai_plan_review || stage?.plan_review)) return [];
    return (sec.documents || []).filter((d) => isPlanReviewableDoc(d.filename));
  }

  function renderSectionAiAssistBar(sec, stage, editable) {
    if (!editable || stage?.ai_ask === false) return "";
    const planDocs = sectionPlanReviewDocs(sec, stage);
    const planBtn = planDocs.length
      ? `<button type="button" class="home-ai-tool home-section-ai-plan" data-section-id="${sec.id}" data-doc-id="${planDocs[0].id}" title="Revisar planta 2D">
          <span class="material-symbols-outlined" aria-hidden="true">architecture</span>
          Plano
        </button>`
      : "";
    return `
      <div class="home-section-ai-bar">
        <span class="home-section-ai-bar-label">IA</span>
        <div class="home-section-ai-bar-actions">
          <button type="button" class="home-ai-tool home-section-ai-ask" data-section-id="${sec.id}" title="Orientación sobre este apartado">
            <span class="material-symbols-outlined" aria-hidden="true">psychology</span>
            Orientar
          </button>
          <button type="button" class="home-ai-tool home-section-ai-draft" data-section-id="${sec.id}" title="Borrador de comentario">
            <span class="material-symbols-outlined" aria-hidden="true">edit_note</span>
            Borrador
          </button>
          ${planBtn}
        </div>
      </div>`;
  }

  function renderReviewBlock(project, sec, editable, stage) {
    const history = renderCommentsHistory(project, sec);
    const canReopen = canReopenSection(project);
    const hasDocs = sectionHasDocuments(sec);
    const chips = renderCriteriaChips(sec, stage);
    const aiBar = renderSectionAiAssistBar(sec, stage, editable);

    if (!hasDocs) {
      return `
        <section class="home-review-panel">
          <div class="home-review-panel-head home-review-panel-head--row">
            <p class="home-review-panel-title">Decisión</p>
            <p class="home-review-panel-hint">Sube un archivo para validar</p>
          </div>
          ${chips}
          ${aiBar}
        </section>`;
    }

    if (sec.status === "completed" && canReopen) {
      return `
        <section class="home-review-panel home-reopen-block" data-section-id="${sec.id}">
          <div class="home-review-panel-head home-review-panel-head--row">
            <p class="home-review-panel-title">Aprobado</p>
            <p class="home-review-panel-hint">Reabrir si hace falta</p>
          </div>
          <div class="home-review-action-row home-review-action-row--compact" role="group" aria-label="Reabrir apartado">
            <button type="button" class="home-review-pill home-section-reopen-choice is-active" data-status="in_progress" data-section-id="${sec.id}">En revisión</button>
            <button type="button" class="home-review-pill home-section-reopen-choice" data-status="needs_details" data-section-id="${sec.id}">Faltan datos</button>
            <button type="button" class="home-review-pill home-section-reopen-choice is-warn" data-status="needs_correction" data-section-id="${sec.id}">Corregir</button>
          </div>
          <input type="hidden" class="home-section-reopen-status" value="in_progress" data-section-id="${sec.id}" />
          <textarea class="home-section-reopen-reason home-review-comment" data-section-id="${sec.id}" rows="2" maxlength="4000" placeholder="Motivo de reapertura (mín. 10)"></textarea>
          <button type="button" class="btn-secondary text-xs py-1.5 px-2.5 mt-2 home-section-reopen-submit" data-section-id="${sec.id}">Reabrir</button>
          ${history}
        </section>`;
    }

    if (sec.status === "completed") {
      return `
        <section class="home-review-panel">
          <div class="home-review-panel-head home-review-panel-head--row">
            <p class="home-review-panel-title">Aprobado</p>
            <p class="home-review-panel-hint">Cerrado</p>
          </div>
          ${history}
        </section>`;
    }

    if (!editable) {
      return `
        <section class="home-review-panel">
          <div class="home-review-panel-head home-review-panel-head--row">
            <p class="home-review-panel-title">Decisión</p>
            <p class="home-review-panel-hint">${sectionStatusLabel(sec.status)}</p>
          </div>
          ${chips}
          ${history}
        </section>`;
    }

    return `
      <section class="home-review-panel home-review-block" data-section-id="${sec.id}">
        <div class="home-review-panel-head home-review-panel-head--row">
          <p class="home-review-panel-title">Decisión</p>
          ${aiBar}
        </div>
        ${chips}
        <input type="hidden" class="home-section-review-status" value="${escapeHtml(sec.status === "pending" ? "in_progress" : sec.status)}" data-section-id="${sec.id}" />
        <div class="home-review-action-row home-review-action-row--compact" role="group" aria-label="Decisión">
          <button type="button" class="home-review-pill home-review-choice ${sec.status === "completed" ? "is-active" : ""}" data-status="completed" data-section-id="${sec.id}">Aprobar</button>
          <button type="button" class="home-review-pill home-review-choice ${sec.status === "needs_details" ? "is-active" : ""}" data-status="needs_details" data-section-id="${sec.id}">Pedir datos</button>
          <button type="button" class="home-review-pill home-review-choice is-warn ${sec.status === "needs_correction" ? "is-active" : ""}" data-status="needs_correction" data-section-id="${sec.id}">Corregir</button>
          <button type="button" class="home-review-pill home-review-choice ${sec.status === "in_progress" || sec.status === "pending" ? "is-active" : ""}" data-status="in_progress" data-section-id="${sec.id}">En revisión</button>
        </div>
        <textarea id="homeReviewComment-${sec.id}" class="home-section-review-comment home-review-comment" data-section-id="${sec.id}" rows="2" maxlength="4000" placeholder="Comentario… (@correo para mencionar)"></textarea>
        <div class="home-review-submit-row">
          <button type="button" class="btn-primary text-xs py-2 px-3 home-section-review-submit" data-section-id="${sec.id}">Registrar</button>
        </div>
        ${history}
        ${sec.comments_count > (sec.comments || []).length ? `<button type="button" class="btn-secondary text-xs py-1 px-2 mt-2 home-section-load-comments" data-section-id="${sec.id}">Ver comentarios (${sec.comments_count})</button>` : ""}
      </section>`;
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

  function canDeleteThisSection(project, sec) {
    if (!project || !sec) return false;
    if (canDeleteSection(project)) return true;
    // Editores pueden borrar apartados creados a mano (no catálogo).
    if (sec.is_catalog) return false;
    return !!(project.permissions?.can_edit || project.my_role === "editor");
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

  function setSidebarHomeMode(active) {
    const panel = $("#sidebarHomeProjects");
    if (!panel) return;
    if (active) {
      panel.classList.remove("hidden");
      panel.removeAttribute("hidden");
    } else {
      panel.classList.add("hidden");
      panel.setAttribute("hidden", "");
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
    setSidebarHomeMode(true);
    window.setNavActive?.("home-projects");
    ensureAssistFab();
    loadProjects();
    syncAssistChatUi();
  }

  function close() {
    syncHomeProjectsUrl(false);
    $("#homeProjectsPanel")?.setAttribute("hidden", "");
    $("#homeProjectsPanel")?.classList.add("hidden");
    $("#chatArea")?.removeAttribute("hidden");
    $("#chatArea")?.classList.remove("hidden");
    $("#composerDock")?.classList.remove("hidden");
    document.body.classList.remove("home-projects-mode");
    setSidebarHomeMode(false);
    assistChatOpen = false;
    syncAssistChatUi();
  }

  function isMobileViewport() {
    return window.matchMedia("(max-width: 900px)").matches;
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
    if (isMobileViewport() && !document.body.classList.contains("sidebar-collapsed")) {
      document.querySelector("#btnMenu")?.click();
    }
  }

  function isPlanReviewableDoc(filename) {
    const ext = (filename || "").split(".").pop()?.toLowerCase() || "";
    return ["png", "jpg", "jpeg", "webp", "bmp", "tif", "tiff", "pdf"].includes(ext);
  }

  function renderDocList(docs, projectId, editable, stage, opts) {
    const options = opts || {};
    if (!docs.length) {
      return `<li class="text-xs opacity-50 py-1">${escapeHtml(options.emptyHint || "Sin archivos aún")}</li>`;
    }
    const allowAi = !!(
      stage?.ai_plan_review ||
      stage?.plan_review ||
      options.aiPlan
    );
    return docs
      .map((d) => {
        const canAi = allowAi && editable && isPlanReviewableDoc(d.filename);
        return `
        <li class="home-doc-item">
          <button type="button" class="home-doc-name" data-dl-url="${escapeHtml(d.download_url)}" data-dl-name="${escapeHtml(d.filename)}">${escapeHtml(d.filename)}</button>
          <span class="home-doc-meta">${formatBytes(d.file_size)}</span>
          ${
            canAi
              ? `<button type="button" class="btn-secondary text-xs py-1 px-2 home-doc-ai-review" data-doc-id="${d.id}" data-section-id="${d.section_id || ""}" title="Revisar planta 2D con IA">Revisar con IA</button>`
              : ""
          }
          ${
            editable
              ? `<button type="button" class="home-doc-delete" data-doc-id="${d.id}" title="Eliminar">×</button>`
              : ""
          }
        </li>`;
      })
      .join("");
  }

  function slotAcceptAttr(accept) {
    const list = Array.isArray(accept) ? accept.filter(Boolean) : [];
    if (!list.length) {
      return ".pdf,.png,.jpg,.jpeg,.webp,.bmp,.tif,.tiff,.doc,.docx,.xls,.xlsx,.dxf,.dwg";
    }
    return list.join(",");
  }

  function renderSectionSlots(sec, project, editable, stage) {
    const slots = sec.slots || [];
    const manageBar = editable
      ? `<div class="home-slots-manage">
          <button type="button" class="btn-secondary text-xs py-1.5 px-2.5 home-slot-add" data-section-id="${sec.id}">+ Agregar espacio</button>
        </div>`
      : "";
    if (!slots.length) {
      const docs = sec.documents || [];
      return `
        <ul class="home-doc-list home-doc-list--panel">${renderDocList(docs, project.id, editable, stage)}</ul>
        ${
          editable
            ? `<div class="home-section-actions flex flex-wrap gap-2 items-center mt-2">
                <label class="home-doc-upload btn-secondary text-xs py-1.5 px-2.5 inline-flex cursor-pointer">
                  <input type="file" class="home-section-file-input" data-section-id="${sec.id}" accept="${slotAcceptAttr([])}" hidden />
                  Subir archivo
                </label>
              </div>`
            : ""
        }
        ${manageBar}`;
    }
    const named = slots.filter((s) => s.key !== "_other");
    const filled = named.filter((s) => s.filled).length;
    const requiredTotal = named.filter((s) => s.required).length;
    const requiredFilled = named.filter((s) => s.required && s.filled).length;
    const hint =
      requiredTotal > 0
        ? `${requiredFilled}/${requiredTotal} obligatorios · ${filled} con archivo`
        : `${filled}/${named.length} con archivo`;
    const rows = slots
      .map((slot) => {
        const docs = slot.documents || [];
        const canUpload = editable && slot.key !== "_other";
        const canRemoveSlot = editable && slot.key !== "_other";
        const statusLabel = slot.filled ? "Listo" : slot.required ? "Falta" : "Opcional";
        const acceptLabel = (slot.accept || []).join(", ") || "varios formatos";
        return `
        <div class="home-slot-row ${slot.filled ? "is-filled" : ""} ${slot.required && !slot.filled ? "is-missing" : ""}" data-slot-key="${escapeHtml(slot.key)}">
          <div class="home-slot-head">
            <div>
              <p class="home-slot-title">${escapeHtml(slot.title)}${slot.required ? " *" : ""}</p>
              <p class="home-slot-formats">${escapeHtml(acceptLabel)}</p>
            </div>
            <div class="home-slot-head-actions">
              <span class="home-slot-status">${statusLabel}</span>
              ${
                canRemoveSlot
                  ? `<button type="button" class="home-slot-delete" data-section-id="${sec.id}" data-slot-key="${escapeHtml(slot.key)}" data-slot-title="${escapeHtml(slot.title)}" title="Eliminar espacio">×</button>`
                  : ""
              }
            </div>
          </div>
          <ul class="home-doc-list home-doc-list--panel">${renderDocList(docs, project.id, editable, stage, {
            emptyHint: "Aún sin archivo",
            aiPlan: !!slot.ai_plan_review,
          })}</ul>
          ${
            canUpload
              ? `<label class="home-doc-upload btn-secondary text-xs py-1.5 px-2.5 inline-flex cursor-pointer mt-2">
                  <input type="file" class="home-section-file-input" data-section-id="${sec.id}" data-slot-key="${escapeHtml(slot.key)}" accept="${escapeHtml(slotAcceptAttr(slot.accept))}" hidden />
                  Subir aquí
                </label>`
              : ""
          }
        </div>`;
      })
      .join("");
    return `
      <p class="home-review-panel-hint home-slots-hint">${escapeHtml(hint)}</p>
      <div class="home-slots-list">${rows}</div>
      ${manageBar}`;
  }

  function renderFindingActions(reviewId, finding, editable) {
    if (!editable || finding.status !== "open") {
      const st =
        finding.status === "accepted"
          ? "Aceptado (corregir)"
          : finding.status === "dismissed"
            ? "Descartado"
            : finding.status || "";
      return st ? `<span class="home-ai-finding-status">${escapeHtml(st)}</span>` : "";
    }
    return `
      <div class="home-ai-finding-actions">
        <button type="button" class="btn-secondary text-xs py-1 px-2 home-ai-finding-accept" data-review-id="${reviewId}" data-finding-id="${escapeHtml(finding.id)}">Aceptar</button>
        <button type="button" class="btn-secondary text-xs py-1 px-2 home-ai-finding-dismiss" data-review-id="${reviewId}" data-finding-id="${escapeHtml(finding.id)}">Descartar</button>
      </div>`;
  }

  function shortFilename(name, max) {
    const text = String(name || "");
    const limit = max || 36;
    if (text.length <= limit) return text;
    const ext = text.includes(".") ? text.slice(text.lastIndexOf(".")) : "";
    const base = text.slice(0, Math.max(8, limit - ext.length - 1));
    return `${base}…${ext}`;
  }

  function renderAiReviewsBlock(stage, editable) {
    if (!(stage.ai_plan_review || stage.plan_review)) return "";
    const scope = stage.ai_plan_scope || {};
    const covers = (scope.covers || []).map((c) => `<li>${escapeHtml(c)}</li>`).join("");
    const exclusions = (scope.exclusions || [])
      .map((c) => `<li>${escapeHtml(c)}</li>`)
      .join("");
    const reviews = stage.ai_reviews || [];
    const openFindings = Number(stage.open_ai_findings || 0);
    const reviewsHtml = reviews.length
      ? `<div class="home-ai-reviews-list">${reviews
          .map((r) => {
            const verdict = r.verdict || {};
            const openCount = Number(r.open_findings || 0);
            const findings = (r.findings || [])
              .map((f) => {
                const steps = Array.isArray(f.fix_steps) ? f.fix_steps : [];
                const fixBlock =
                  f.fix || steps.length
                    ? `<div class="home-ai-finding-fix">
                        ${f.fix ? `<p class="home-ai-finding-fix-sum">${escapeHtml(f.fix)}</p>` : ""}
                        ${
                          steps.length
                            ? `<ol class="home-ai-finding-fix-steps">${steps
                                .map((s) => `<li>${escapeHtml(s)}</li>`)
                                .join("")}</ol>`
                            : ""
                        }
                      </div>`
                    : "";
                return `
              <li class="home-ai-finding home-ai-finding--${escapeHtml(f.severity || "info")} home-ai-finding--${escapeHtml(f.status || "open")}">
                <div class="home-ai-finding-top">
                  <p class="home-ai-finding-label">${escapeHtml(f.label || f.code || "Hallazgo")}</p>
                  <span class="home-ai-finding-sev">${escapeHtml((f.severity || "info").toUpperCase())}</span>
                </div>
                <p class="home-ai-finding-msg">${escapeHtml(f.message || "")}</p>
                ${f.norm_ref ? `<p class="home-ai-finding-ref">${escapeHtml(f.norm_ref)}</p>` : ""}
                ${fixBlock}
                ${renderFindingActions(r.id, f, editable)}
              </li>`;
              })
              .join("");
            return `
            <article class="home-ai-review-card">
              <div class="home-ai-review-card-head">
                <div>
                  <p class="home-ai-review-card-title">Revisión #${r.id}</p>
                  <p class="home-ai-review-card-sub">${escapeHtml(verdict.headline || "Sin veredicto")}</p>
                </div>
                <div class="home-ai-review-card-meta">
                  <span class="home-ai-chip ${openCount ? "is-warn" : "is-ok"}">${openCount} abiertos</span>
                  <span class="home-ai-chip">${escapeHtml(r.status || "open")}</span>
                </div>
              </div>
              <div class="home-ai-review-card-actions">
                <a class="home-ai-review-link" href="${escapeHtml(r.workspace_url || "/legacy-app")}" rel="noopener">Abrir en Revisión IA</a>
              </div>
              ${findings ? `<ul class="home-ai-findings">${findings}</ul>` : `<p class="home-ai-empty-inline">Sin hallazgos.</p>`}
            </article>`;
          })
          .join("")}</div>`
      : `<div class="home-ai-empty">
          <p class="home-ai-empty-title">Sin revisiones aún</p>
          <p class="home-ai-empty-copy">Sube una planta (imagen o PDF) en un entregable y usa <strong>Revisar con IA</strong> en ese archivo.</p>
        </div>`;

    return `
      <section class="home-ai-panel">
        <header class="home-ai-panel-head">
          <div>
            <p class="home-ai-panel-kicker">Apoyo IA</p>
            <h3 class="home-ai-panel-title">Revisiones de plano</h3>
            <p class="home-ai-panel-sub">${escapeHtml(scope.title || "Habitabilidad en planta 2D")}</p>
          </div>
          <div class="home-ai-panel-stats">
            <span class="home-ai-chip">${reviews.length} revisión${reviews.length === 1 ? "" : "es"}</span>
            ${
              openFindings
                ? `<span class="home-ai-chip is-warn">${openFindings} abiertos</span>`
                : `<span class="home-ai-chip is-muted">Sin abiertos</span>`
            }
          </div>
        </header>
        <details class="home-ai-scope">
          <summary class="home-ai-scope-summary">
            <span>Alcance de la revisión</span>
            <span class="home-ai-scope-chevron" aria-hidden="true">▾</span>
          </summary>
          <div class="home-ai-scope-grid">
            <div class="home-ai-scope-col">
              <p class="home-ai-scope-label is-ok">Qué sí revisa</p>
              <ul>${covers || "<li>Planta 2D</li>"}</ul>
            </div>
            <div class="home-ai-scope-col">
              <p class="home-ai-scope-label is-off">Qué no revisa</p>
              <ul>${exclusions || "<li>Fuera de alcance</li>"}</ul>
            </div>
          </div>
        </details>
        ${
          openFindings
            ? `<p class="home-ai-alert">Hay <strong>${openFindings}</strong> hallazgo(s) abiertos. Acéptalos o descártalos antes de avanzar, o confirma al cerrar la etapa.</p>`
            : ""
        }
        ${reviewsHtml}
        ${renderAnalysisLinkLegacy(stage, editable)}
      </section>`;
  }

  function renderAnalysisLinkLegacy(stage, editable) {
    if (!editable) return "";
    const linked = stage.analysis;
    const options = analysesPicker
      .map((a) => {
        const label = `${shortFilename(a.filename, 42)} · ${a.counts?.errors || 0} err / ${a.counts?.warnings || 0} adv`;
        return `<option value="${a.id}" ${stage.analysis_id === a.id ? "selected" : ""}>${escapeHtml(label)}</option>`;
      })
      .join("");
    return `
      <details class="home-ai-link" ${linked ? "open" : ""}>
        <summary class="home-ai-link-summary">
          <span>${linked ? "Análisis vinculado del workspace" : "Vincular análisis del workspace"}</span>
          <span class="home-ai-scope-chevron" aria-hidden="true">▾</span>
        </summary>
        <div class="home-ai-link-body">
          ${
            linked
              ? `<div class="home-ai-linked">
                  <div>
                    <p class="home-ai-linked-name" title="${escapeHtml(linked.filename)}">${escapeHtml(shortFilename(linked.filename, 48))}</p>
                    <p class="home-ai-linked-meta">${linked.errors || 0} errores · ${linked.warnings || 0} advertencias</p>
                  </div>
                  <button type="button" class="btn-secondary text-xs py-1.5 px-2.5" id="btnUnlinkAnalysis">Quitar</button>
                </div>`
              : `<p class="home-ai-link-hint">Opcional: conecta un análisis ya hecho en Revisión IA.</p>`
          }
          <div class="home-ai-link-row">
            <select class="home-analysis-select" id="homeAnalysisSelect" aria-label="Análisis del workspace">
              <option value="">— Elegir análisis —</option>
              ${options}
            </select>
            <button type="button" class="btn-secondary text-xs py-2 px-3" id="btnLinkAnalysis">${linked ? "Cambiar" : "Vincular"}</button>
          </div>
        </div>
      </details>`;
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
            const namedSlots = (sec.slots || []).filter((s) => s.key !== "_other");
            const filesLabel = namedSlots.length
              ? `${namedSlots.filter((s) => s.filled).length}/${namedSlots.length} entregables`
              : docsCount
                ? `${docsCount} archivo${docsCount === 1 ? "" : "s"}`
                : "Subir documento";
            const accentCls =
              sec.status === "completed"
                ? "is-success"
                : sec.status === "in_progress" || sec.status === "needs_correction" || sec.status === "needs_details"
                  ? "is-warning"
                  : "is-neutral";
            return `
            <article class="home-section-card home-module-card ${needsAttention ? "needs-attention" : ""} ${accentCls}" data-section-id="${sec.id}">
              <header class="home-section-card-head">
                <div class="home-section-card-topline">
                  <h5 class="home-section-card-title">${escapeHtml(sec.title)}</h5>
                  <button type="button" class="home-module-expand-btn" data-open-section="${sec.id}" aria-label="Abrir apartado">⋯</button>
                </div>
                <span class="${statusCls}">${sectionStatusLabel(sec.status)}</span>
                ${
                  sec.description
                    ? `<p class="home-section-card-desc is-truncated">${escapeHtml(sec.description)}</p>`
                    : ""
                }
                <div class="home-module-meta-row home-module-meta-stack">
                  <span class="home-module-files">${filesLabel}</span>
                  <span class="home-module-assignee">${assigneeName ? `Asignado: ${escapeHtml(assigneeName)}` : "Sin asignar"}</span>
                  <span class="home-module-comments">${commentsCount} comentario${commentsCount === 1 ? "" : "s"}</span>
                </div>
              </header>
            </article>`;
          })
          .join("")
      : `<p class="text-sm opacity-60">${sectionFilter === "all" ? "No hay apartados en esta etapa." : "Ningún apartado coincide con el filtro."}</p>`;

    return `
      <div class="home-sections-block">
        <div class="home-sections-toolbar">
          <div class="home-sections-toolbar-copy">
            <p class="home-sections-heading">Apartados documentales</p>
            <p class="home-sections-progress"><span class="hp-progress-full">${progress.done}/${progress.total} completados · ${progress.with_files} con archivos · ${progress.needs_action || 0} requieren acción · ${progress.without_docs || 0} sin docs</span><span class="hp-progress-short">${progress.done}/${progress.total} listos · ${progress.without_docs || 0} sin docs</span></p>
          </div>
          ${
            editable
              ? `<button type="button" class="btn-primary home-sections-new-btn" id="btnAddSection">Nuevo</button>`
              : ""
          }
        </div>
        <div class="home-section-filters" role="toolbar" aria-label="Filtros de apartados">
          ${[
            ["all", `Todos (${counts.all})`],
            ["no_docs", `Sin entregar (${counts.no_docs})`],
            ["in_review", `En revisión (${counts.in_review})`],
            ["corrections", `Corregir (${counts.corrections})`],
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

  function renderModuleOverlay(project, openSection, editable, stage) {
    if (!openSection) return "";
    const sectionWorkable = canWorkSection(project, openSection);
    const canDeleteSec = canDeleteThisSection(project, openSection);
    const docs = openSection.documents || [];
    const docsCount = docs.length;
    const slots = openSection.slots || [];
    const stageLabel = stage
      ? `Etapa ${stage.stage_number} · ${stage.title}`
      : `Etapa ${openSection.stage_number || "?"}`;
    const deliverableHint = slots.length
      ? "Sube cada archivo en su espacio · puedes agregar o quitar espacios"
      : docsCount
        ? `${docsCount} archivo(s) listo(s) para validar`
        : "Aún no hay archivo en este apartado";
    return `<div class="home-module-overlay" id="homeModuleOverlay">
      <article class="home-module-float home-module-float--review" data-section-id="${openSection.id}" role="dialog" aria-modal="true">
        <div class="home-module-float-head">
          <div>
            <p class="home-module-float-kicker">${escapeHtml(stageLabel)} · Entregable</p>
            <h4 class="home-module-float-title">${escapeHtml(openSection.title)}</h4>
          </div>
          <div class="home-module-float-actions">
            <span class="home-section-status is-${openSection.status}">${sectionStatusLabel(openSection.status)}</span>
            ${
              editable && canDeleteSec
                ? `<details class="home-module-more">
                    <summary class="home-module-more-btn" aria-label="Más opciones">⋯</summary>
                    <div class="home-module-more-menu" role="menu">
                      <button type="button" class="home-section-delete home-module-more-danger" data-section-id="${openSection.id}" role="menuitem">Eliminar apartado</button>
                    </div>
                  </details>`
                : ""
            }
            <button type="button" class="home-module-close-btn" id="btnCloseModuleOverlay" aria-label="Cerrar">✕</button>
          </div>
        </div>
        ${
          openSection.description
            ? `<p class="home-module-float-desc">${escapeHtml(openSection.description)}</p>`
            : `<p class="home-module-float-desc">Archivos separados por tipo de entregable + decisión del equipo.</p>`
        }
        <div class="home-module-details">
          ${
            !sectionWorkable
              ? `<p class="home-module-banner">Sin responsable asignado: solo el propietario puede trabajar este apartado hasta asignar a alguien.</p>`
              : ""
          }
          <section class="home-deliverable-panel">
            <div class="home-deliverable-head">
              <div>
                <p class="home-review-panel-title">Entregables</p>
                <p class="home-review-panel-hint">${escapeHtml(deliverableHint)}</p>
              </div>
            </div>
            ${renderAssigneeSelect(project, openSection, canAssign(project))}
            ${renderLastReview(openSection)}
            ${renderSectionSlots(openSection, project, editable && sectionWorkable, stage)}
          </section>
          ${renderReviewBlock(project, openSection, canReview(project) && sectionWorkable, stage)}
        </div>
      </article>
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
              ? planCaps().teamInvites
                ? `<button type="button" class="btn-primary text-xs py-2 px-3" id="btnInviteMember">Invitar</button>`
                : `<button type="button" class="btn-secondary text-xs py-2 px-3" id="btnInviteUpgrade">Invitar (Enterprise)</button>`
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

  function homeFooterMarkup() {
    return `
      <footer class="home-projects-footer" id="homeProjectsFooter">
        <div class="home-projects-footer-inner">
          <div class="home-projects-footer-brand">
            <img src="/static/brand/architect-logo.png?v=3" alt="ARCHITECT" class="brand-logo-img brand-logo-img--footer" />
            <p class="home-projects-footer-desc">
              Gestión de vivienda unifamiliar por etapas, documentos y equipo. Herramienta de apoyo; no reemplaza proyecto ejecutivo firmado.
            </p>
            <p class="home-projects-footer-copy">© 2026 ARCHITECT</p>
          </div>
          <nav class="home-projects-footer-links" aria-label="Enlaces de Casa hogar">
            <div class="home-projects-footer-col">
              <h4>Plataforma</h4>
              <a href="#" data-home-footer="workspace">Revisión IA</a>
              <a href="#" data-home-footer="home" aria-current="page">Casa hogar</a>
              <a href="/docs" target="_blank" rel="noopener" class="home-footer-link--desktop">API</a>
            </div>
            <div class="home-projects-footer-col">
              <h4>Cuenta</h4>
              <a href="#" data-home-footer="plans">Planes</a>
              <a href="#" data-home-footer="account">Mi cuenta</a>
              <a href="/" class="home-footer-link--desktop">Landing</a>
            </div>
          </nav>
        </div>
      </footer>`;
  }

  function renderDetail(project) {
    const detail = $("#homeProjectsDetail");
    const empty = $("#homeProjectsEmpty");
    if (!detail) return;
    if (!project) {
      detail.innerHTML = `
        <div class="home-project-scroll home-project-scroll--empty" id="homeProjectDetailScroll">
          <div class="home-projects-empty flex flex-1 flex-col items-center justify-center text-center opacity-60" id="homeProjectsEmpty">
            <span class="material-symbols-outlined text-4xl mb-2">home_work</span>
            <p class="text-sm">Selecciona un proyecto o crea uno nuevo</p>
          </div>
          ${homeFooterMarkup()}
        </div>`;
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
        <article class="home-stage-card">
          <p class="home-stage-kicker">Etapa ${stage.stage_number} de ${project.stages.length}</p>
          <h4 class="home-stage-title">${escapeHtml(stage.title)}</h4>
          <p class="home-stage-summary">${escapeHtml(stage.summary || "")}</p>
          <p class="home-stage-status-line">Estado: ${statusLabel(stage.status)} · ${stage.sections_progress?.done || 0}/${stage.sections_progress?.total || 0} apartados</p>

          <div class="home-section home-section--apartados">${renderSectionsBlock(stage, project, editable)}</div>

          ${
            (stage.documents || []).length
              ? `<div class="home-section">
                  <p class="home-section-title">Archivos generales de etapa</p>
                  <ul class="home-doc-list">${renderDocList(stage.documents, project.id, editable, stage)}</ul>
                </div>`
              : ""
          }

          ${
            stage.ai_plan_review || stage.plan_review
              ? `<div class="home-section">${renderAiReviewsBlock(stage, editable)}</div>`
              : ""
          }

          <div class="home-section home-notes-section">
            <label class="home-notes-title" for="homeStageNotes">Notas de etapa</label>
            <textarea class="home-notes-input home-notes-textarea" id="homeStageNotes" placeholder="Añade notas, observaciones o requerimientos especiales para esta etapa..." ${editable ? "" : "readonly"}>${escapeHtml(stage.notes || "")}</textarea>
          </div>

          ${
            editable
              ? `<div class="home-notes-actions">
                  <button type="button" class="btn-secondary home-notes-btn-secondary" id="btnMarkInProgress"><span class="hp-btn-full">Marcar en curso</span><span class="hp-btn-short">En curso</span></button>
                  <button type="button" class="btn-primary home-notes-btn-primary" id="btnSaveStage"><span class="hp-btn-full">Guardar notas</span><span class="hp-btn-short">Guardar</span></button>
                  ${
                    stageReopenable && stage.status === "completed"
                      ? `<button type="button" class="btn-secondary home-notes-btn-secondary" id="btnReopenStage">Reabrir etapa</button>`
                      : ""
                  }
                </div>`
              : ""
          }
        </article>`;
    }

    detail.innerHTML = `
      <div class="home-project-scroll" id="homeProjectDetailScroll">
      <header class="home-project-header mb-0">
        <div class="home-project-header-top">
          <div class="home-project-header-copy">
            <p class="text-[10px] font-bold uppercase tracking-widest opacity-50">Proyecto · ${project.my_role === "admin" ? "Administrador" : project.my_role === "owner" ? "Propietario" : project.my_role === "editor" ? "Editor" : "Lector"}</p>
            <h3 class="home-project-title font-semibold tracking-tight">${escapeHtml(project.name)}</h3>
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
            <button type="button" class="btn-secondary text-xs py-2 px-3" id="btnBackToIA"><span class="hp-btn-full">Volver a IA</span><span class="hp-btn-short">Volver</span></button>
            ${
              isCompleted
                ? `<button type="button" class="btn-secondary text-xs py-2 px-3" id="btnCompletionOverviewHeader"><span class="hp-btn-full">Resumen de cierre</span><span class="hp-btn-short">Resumen</span></button>`
                : `<button type="button" class="btn-secondary text-xs py-2 px-3 ${stageAdvanceable ? "" : "home-action-disabled"}" id="btnAdvanceStage" ${stageAdvanceable ? "" : "disabled"} title="${stageAdvanceable ? "Completar etapa actual" : "Solo propietario o administrador"}"><span class="hp-btn-full">Completar etapa</span><span class="hp-btn-short">Completar</span></button>`
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

      <div class="home-stage-layout">${mainContent}</div>
      ${homeFooterMarkup()}
      </div>
      ${detailView === "stage" && !completionOverviewMode ? renderModuleOverlay(project, openSection, editable, stage) : ""}`;

    const track = detail.querySelector("#homeStageTrack");
    if (track) {
      const totalStages = project.stages.length;
      const progressStage = completionOverviewMode && isCompleted ? totalStages : stageNum;
      const pct =
        totalStages > 1
          ? Math.max(0, Math.min(100, ((progressStage - 1) / (totalStages - 1)) * 100))
          : 0;
      track.style.setProperty("--hp-stage-progress", String(pct / 100));
      if (window.matchMedia("(max-width: 900px)").matches) {
        track.style.display = "flex";
        track.style.removeProperty("grid-template-columns");
      } else {
        track.style.display = "";
        track.style.gridTemplateColumns = `repeat(${totalStages}, minmax(0, 1fr))`;
      }
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
    bindClick("#btnBackToIA", () => {
      if (typeof window.goToWorkspace === "function") window.goToWorkspace();
      else close();
    });
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
    bindClick("#btnInviteUpgrade", () => {
      window.showToast?.("Las invitaciones de equipo están en el plan Enterprise.");
      document.getElementById("btnPlans")?.click();
    });
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
    bindClick("#btnUnlinkAnalysis", () => {
      patchStage(project.id, stage.stage_number, { analysis_id: 0 });
    });

    detail.querySelectorAll(".home-doc-ai-review").forEach((btn) => {
      btn.onclick = () => {
        const docId = Number(btn.dataset.docId);
        const sectionId = btn.dataset.sectionId ? Number(btn.dataset.sectionId) : null;
        if (docId) runDocAiReview(project.id, stage.stage_number, docId, sectionId);
      };
    });

    detail.querySelectorAll(".home-ai-finding-accept").forEach((btn) => {
      btn.onclick = () =>
        updateAiFinding(
          project.id,
          Number(btn.dataset.reviewId),
          btn.dataset.findingId,
          "accept"
        );
    });

    detail.querySelectorAll(".home-ai-finding-dismiss").forEach((btn) => {
      btn.onclick = async () => {
        const note = await PlanoDialog.prompt({
          title: "Descartar hallazgo",
          message: "Indica el motivo para descartarlo:",
          placeholder: "Motivo…",
          minLength: 5,
          multiline: true,
          confirmLabel: "Descartar",
        });
        if (note == null) return;
        updateAiFinding(
          project.id,
          Number(btn.dataset.reviewId),
          btn.dataset.findingId,
          "dismiss",
          note
        );
      };
    });

    detail.querySelectorAll(".home-section-file-input").forEach((input) => {
      input.addEventListener("change", (e) => {
        const file = e.target.files?.[0];
        const sectionId = Number(input.dataset.sectionId);
        const slotKey = input.dataset.slotKey || null;
        if (file && sectionId) {
          uploadDocument(project.id, stage.stage_number, file, sectionId, slotKey);
        }
        e.target.value = "";
      });
    });

    detail.querySelectorAll(".home-slot-add").forEach((btn) => {
      btn.onclick = () => {
        const sectionId = Number(btn.dataset.sectionId);
        openSlotModal(project.id, sectionId);
      };
    });

    detail.querySelectorAll(".home-slot-delete").forEach((btn) => {
      btn.onclick = async () => {
        const sectionId = Number(btn.dataset.sectionId);
        const slotKey = btn.dataset.slotKey;
        const slotTitle = btn.dataset.slotTitle || "este espacio";
        if (
          !(await PlanoDialog.confirm(
            `¿Eliminar el espacio «${slotTitle}» y sus archivos?`,
            { title: "Eliminar espacio", variant: "danger", confirmLabel: "Eliminar" }
          ))
        ) {
          return;
        }
        deleteSectionSlot(project.id, sectionId, slotKey);
      };
    });

    detail.querySelectorAll(".home-section-delete").forEach((btn) => {
      btn.onclick = async () => {
        if (
          !(await PlanoDialog.confirm(
            "¿Eliminar este apartado y todos sus archivos? Esta acción no se puede deshacer.",
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
        const status =
          block?.querySelector(".home-section-reopen-status")?.value || "in_progress";
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

    detail.querySelectorAll(".home-review-choice").forEach((btn) => {
      btn.onclick = () => {
        const block = btn.closest(".home-review-block");
        const statusInput = block?.querySelector(".home-section-review-status");
        const status = btn.dataset.status || "in_progress";
        if (statusInput) statusInput.value = status;
        block?.querySelectorAll(".home-review-choice").forEach((b) => {
          b.classList.toggle("is-active", b === btn);
        });
        const commentEl = block?.querySelector(".home-section-review-comment");
        if (
          (status === "needs_details" || status === "needs_correction") &&
          commentEl &&
          !commentEl.value.trim()
        ) {
          commentEl.focus();
        }
      };
    });

    detail.querySelectorAll(".home-section-ai-ask").forEach((btn) => {
      btn.onclick = () => {
        const sectionId = Number(btn.dataset.sectionId);
        const sec = (stage.sections || []).find((s) => s.id === sectionId);
        if (sec) openAssistForSection(project, stage, sec);
      };
    });

    detail.querySelectorAll(".home-section-ai-draft").forEach((btn) => {
      btn.onclick = () => {
        const sectionId = Number(btn.dataset.sectionId);
        const sec = (stage.sections || []).find((s) => s.id === sectionId);
        if (sec) suggestReviewComment(project, stage, sec);
      };
    });

    detail.querySelectorAll(".home-section-ai-plan").forEach((btn) => {
      btn.onclick = () => {
        const docId = Number(btn.dataset.docId);
        const sectionId = Number(btn.dataset.sectionId);
        if (docId) runDocAiReview(project.id, stage.stage_number, docId, sectionId);
      };
    });

    detail.querySelectorAll(".home-section-reopen-choice").forEach((btn) => {
      btn.onclick = () => {
        const block = btn.closest(".home-reopen-block");
        const statusInput = block?.querySelector(".home-section-reopen-status");
        if (statusInput) statusInput.value = btn.dataset.status || "in_progress";
        block?.querySelectorAll(".home-section-reopen-choice").forEach((b) => {
          b.classList.toggle("is-active", b === btn);
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
            "Añade un comentario explicando qué falta o qué hay que corregir"
          );
          commentEl?.focus();
          return;
        }
        const payload = { status };
        if (reviewComment) payload.review_comment = reviewComment;
        patchSection(project.id, sectionId, payload);
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

    if ((stage.ai_plan_review || stage.plan_review) && editable && !analysesLoaded) {
      ensureAnalysesPicker().then(() => {
        const latest = projects.find((p) => p.id === project.id);
        if (latest && activeId === project.id) renderDetail(latest);
      });
    }

    if (shouldResetScroll) resetDetailScroll();
    lastDetailView = detailView;
    syncAssistChatUi();
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
      window.showToast?.("Decisión registrada", { variant: "success" });
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
    if (expandedSectionId === sectionId) expandedSectionId = null;
    const idx = projects.findIndex((p) => p.id === projectId);
    if (idx >= 0) projects[idx] = data;
    renderDetail(projects[idx]);
    window.showToast?.("Apartado eliminado");
  }

  async function addSectionSlot(projectId, sectionId, title, opts) {
    const options = opts || {};
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/sections/${sectionId}/slots`,
      {
        method: "POST",
        body: JSON.stringify({
          title,
          required: !!options.required,
        }),
      }
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo agregar el espacio");
      return;
    }
    const idx = projects.findIndex((p) => p.id === projectId);
    if (idx >= 0) projects[idx] = data;
    renderDetail(projects[idx]);
    window.showToast?.("Espacio agregado");
  }

  async function deleteSectionSlot(projectId, sectionId, slotKey) {
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/sections/${sectionId}/slots/${encodeURIComponent(slotKey)}`,
      { method: "DELETE" }
    );
    const data = await res.json();
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo eliminar el espacio");
      return;
    }
    const idx = projects.findIndex((p) => p.id === projectId);
    if (idx >= 0) projects[idx] = data;
    renderDetail(projects[idx]);
    window.showToast?.("Espacio eliminado");
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

  async function uploadDocument(projectId, stageNumber, file, sectionId, slotKey) {
    const fd = new FormData();
    fd.append("file", file);
    if (sectionId) fd.append("section_id", String(sectionId));
    if (slotKey) fd.append("slot_key", String(slotKey));
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

  function stripAssistDisclaimer(text) {
    return String(text || "")
      .replace(/\n*—\n*\*\*Alcance del asistente:[\s\S]*$/i, "")
      .replace(/\*\*Revisión de plano[\s\S]*$/i, "")
      .trim();
  }

  function openAssistForSection(project, stage, sec) {
    ensureAssistFab();
    assistChatOpen = true;
    syncAssistChatUi();
    const criteria = sectionReviewCriteria(sec, stage).map((c) => `- ${c}`).join("\n");
    const files = (sec.documents || []).map((d) => d.filename).filter(Boolean).join(", ");
    const question =
      `Ayúdame a revisar el apartado «${sec.title}» de la etapa ${stage.stage_number} (${stage.title}).\n` +
      `Criterios a validar:\n${criteria}\n` +
      (files ? `Archivos subidos (solo nombres): ${files}.\n` : "") +
      `No leíste el contenido del archivo. Dime checklist práctico de qué mirar y señales de que falta info o hay que corregir.`;
    const input = document.getElementById("homeAiQuestion");
    if (input) {
      input.value = question;
      input.focus();
    }
    askStageAssist(project.id, stage.stage_number);
  }

  async function suggestReviewComment(project, stage, sec) {
    const panel = document.querySelector(`.home-review-block[data-section-id="${sec.id}"]`);
    const status =
      panel?.querySelector(".home-section-review-status")?.value ||
      sec.status ||
      "in_progress";
    const commentEl = panel?.querySelector(".home-section-review-comment");
    const draftBtn = panel?.querySelector(".home-section-ai-draft");
    const actionLabel =
      status === "completed"
        ? "aprobar"
        : status === "needs_details"
          ? "pedir datos faltantes"
          : status === "needs_correction"
            ? "pedir corrección"
            : "seguir revisando";
    const criteria = sectionReviewCriteria(sec, stage).join("; ");
    const files = (sec.documents || []).map((d) => d.filename).filter(Boolean).join(", ");
    const question =
      `Redacta un comentario breve de revisión humana (máx. 4 frases, tono profesional, en español) ` +
      `para ${actionLabel} el apartado «${sec.title}» (etapa ${stage.stage_number}). ` +
      `Criterios: ${criteria}. ` +
      (files ? `Archivo(s): ${files}. ` : "") +
      `No inventes contenido del documento (no lo leíste). ` +
      `Si la acción es pedir datos o corrección, indica qué evidencia debería aportar el equipo. ` +
      `Devuelve solo el texto del comentario, sin markdown ni disclaimers.`;

    if (draftBtn) draftBtn.disabled = true;
    window.showToast?.("Generando borrador…", { duration: 2500 });
    try {
      const res = await PlanoAuth.apiFetch(
        `/api/home-projects/${encodeURIComponent(project.id)}/stages/${stage.stage_number}/assist`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ question }),
        }
      );
      const data = await res.json();
      if (!res.ok) {
        window.showToast?.(apiErrorMessage(data, "No se pudo sugerir comentario"));
        return;
      }
      const draft = stripAssistDisclaimer(data.guidance || "");
      if (!draft) {
        window.showToast?.("La IA no devolvió un borrador útil");
        return;
      }
      if (commentEl) {
        commentEl.value = draft.slice(0, 4000);
        commentEl.focus();
      }
      const history = getAssistHistory(project.id, stage.stage_number);
      history.push({ role: "user", text: `Sugerir comentario para «${sec.title}» (${actionLabel})` });
      history.push({ role: "assistant", text: draft });
      if (history.length > 8) {
        assistChatHistory[assistChatKey(project.id, stage.stage_number)] = history.slice(-8);
      }
      window.showToast?.("Borrador listo: revísalo antes de registrar", {
        variant: "success",
      });
    } catch (err) {
      window.showToast?.(err.message || "Error al sugerir comentario");
    } finally {
      if (draftBtn) draftBtn.disabled = false;
    }
  }

  async function askStageAssist(projectId, stageNumber) {
    const input = document.getElementById("homeAiQuestion");
    const btn = document.getElementById("btnHomeAssist");
    const question = (input?.value || "").trim();
    if (!question) {
      window.showToast?.("Escribe una pregunta");
      input?.focus();
      return;
    }
    if (assistChatBusy) return;

    const history = getAssistHistory(projectId, stageNumber);
    history.push({ role: "user", text: question });
    if (input) input.value = "";
    assistChatOpen = true;
    assistChatBusy = true;
    syncAssistChatUi();
    const box = document.getElementById("homeAssistChatMessages");
    if (box) {
      box.insertAdjacentHTML(
        "beforeend",
        `<div class="home-assist-msg home-assist-msg--bot home-assist-msg--pending"><p>Pensando…</p></div>`
      );
      box.scrollTop = box.scrollHeight;
    }
    if (btn) btn.disabled = true;

    try {
      const res = await PlanoAuth.apiFetch(
        `/api/home-projects/${encodeURIComponent(projectId)}/stages/${stageNumber}/assist`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ question }),
        }
      );
      const data = await res.json();
      if (!res.ok) {
        history.pop();
        window.showToast?.(apiErrorMessage(data, "No se pudo consultar al asistente"));
        const idx = projects.findIndex((p) => p.id === projectId);
        const st = idx >= 0 ? projects[idx].stages?.find((s) => s.stage_number === stageNumber) : null;
        renderAssistMessages(projectId, stageNumber, st);
        return;
      }
      const answer = data.guidance || "Sin respuesta.";
      history.push({ role: "assistant", text: answer });
      // Mantén historial corto por etapa (últimos 8 mensajes).
      if (history.length > 8) {
        assistChatHistory[assistChatKey(projectId, stageNumber)] = history.slice(-8);
      }
      const idx = projects.findIndex((p) => p.id === projectId);
      if (idx >= 0) {
        const st = projects[idx].stages?.find((s) => s.stage_number === stageNumber);
        if (st) st.ai_guidance = answer;
      }
      renderAssistMessages(
        projectId,
        stageNumber,
        idx >= 0 ? projects[idx].stages?.find((s) => s.stage_number === stageNumber) : null
      );
    } catch (err) {
      history.pop();
      window.showToast?.(err.message || "Error al consultar");
      renderAssistMessages(projectId, stageNumber, null);
    } finally {
      assistChatBusy = false;
      syncAssistChatUi();
      input?.focus();
    }
  }

  async function runDocAiReview(projectId, stageNumber, documentId, sectionId) {
    if (
      !(await PlanoDialog.confirm(
        "Se revisará solo la planta 2D (puertas, ventanas, muros, recintos). No cubre CAD, cortes, estructura ni instalaciones. ¿Continuar?",
        { title: "Revisar plano con IA", confirmLabel: "Revisar" }
      ))
    ) {
      return;
    }
    window.showToast?.("Analizando plano…", { duration: 4000 });
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/stages/${stageNumber}/ai-reviews`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          document_id: documentId,
          section_id: sectionId || null,
          message: "",
        }),
      }
    );
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const detail = data.detail;
      window.showToast?.(
        typeof detail === "string" ? detail : detail?.message || "No se pudo revisar el plano"
      );
      return;
    }
    if (data.project) {
      const idx = projects.findIndex((p) => p.id === projectId);
      if (idx >= 0) projects[idx] = data.project;
      renderList();
      renderDetail(projects[idx] || data.project);
    }
    const openN = data.review?.open_findings || 0;
    window.showToast?.(
      openN ? `Revisión lista · ${openN} hallazgo(s) abiertos` : "Revisión lista · sin hallazgos abiertos",
      { variant: "success", icon: "fact_check" }
    );
  }

  async function updateAiFinding(projectId, reviewId, findingId, action, note = "") {
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/ai-reviews/${reviewId}/findings/${encodeURIComponent(findingId)}`,
      {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, note }),
      }
    );
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      window.showToast?.(data.detail || "No se pudo actualizar el hallazgo");
      return;
    }
    if (data.project) {
      const idx = projects.findIndex((p) => p.id === projectId);
      if (idx >= 0) projects[idx] = data.project;
      renderDetail(projects[idx] || data.project);
    }
    window.showToast?.(
      action === "accept" ? "Hallazgo aceptado" : action === "dismiss" ? "Hallazgo descartado" : "Hallazgo actualizado",
      { variant: "success" }
    );
  }

  async function advanceStage(projectId, acknowledgeOpenFindings = false) {
    if (!acknowledgeOpenFindings) {
      if (
        !(await PlanoDialog.confirm(
          "¿Marcar la etapa actual como completada y avanzar a la siguiente? Solo el propietario o un administrador pueden hacerlo.",
          { title: "Completar etapa", confirmLabel: "Completar" }
        ))
      ) {
        return;
      }
    }
    const res = await PlanoAuth.apiFetch(
      `/api/home-projects/${encodeURIComponent(projectId)}/advance`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ acknowledge_open_findings: acknowledgeOpenFindings }),
      }
    );
    const data = await res.json().catch(() => ({}));
    if (res.status === 409) {
      const detail = data.detail || {};
      const msg =
        detail.message ||
        "Hay hallazgos de revisión IA abiertos. ¿Avanzar de todas formas?";
      if (
        await PlanoDialog.confirm(msg, {
          title: "Hallazgos IA abiertos",
          confirmLabel: "Avanzar igual",
        })
      ) {
        return advanceStage(projectId, true);
      }
      return;
    }
    if (!res.ok) {
      window.showToast?.(
        typeof data.detail === "string" ? data.detail : "No se pudo avanzar"
      );
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
  let pendingSlotProjectId = null;
  let pendingSlotSectionId = null;

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

  function openSlotModal(projectId, sectionId) {
    pendingSlotProjectId = projectId;
    pendingSlotSectionId = sectionId;
    if ($("#homeSlotTitle")) $("#homeSlotTitle").value = "";
    if ($("#homeSlotRequired")) $("#homeSlotRequired").checked = false;
    const dlg = $("#homeSlotModal");
    if (!dlg) return;
    if (typeof dlg.showModal === "function") dlg.showModal();
    else dlg.setAttribute("open", "");
    setTimeout(() => $("#homeSlotTitle")?.focus(), 30);
  }

  function closeSlotModal() {
    pendingSlotProjectId = null;
    pendingSlotSectionId = null;
    const dlg = $("#homeSlotModal");
    if (!dlg) return;
    if (typeof dlg.close === "function") dlg.close();
    else dlg.removeAttribute("open");
  }

  async function createSlotFromForm(event) {
    event.preventDefault();
    const title = ($("#homeSlotTitle")?.value || "").trim();
    const required = !!$("#homeSlotRequired")?.checked;
    if (!pendingSlotProjectId || !pendingSlotSectionId) return;
    if (title.length < 2) {
      window.showToast?.("El nombre debe tener al menos 2 caracteres");
      return;
    }
    const projectId = pendingSlotProjectId;
    const sectionId = pendingSlotSectionId;
    closeSlotModal();
    await addSectionSlot(projectId, sectionId, title, { required });
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
    if (!planCaps().teamInvites) {
      window.showToast?.("Las invitaciones de equipo están en el plan Enterprise.");
      document.getElementById("btnPlans")?.click();
      return;
    }
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
      window.showToast?.(apiErrorMessage(data, "No se pudo invitar"));
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
      window.showToast?.(apiErrorMessage(data, "No se pudo crear el proyecto"));
      if (res.status === 402) document.getElementById("btnPlans")?.click();
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
  $("#btnCloseHomeSlot")?.addEventListener("click", closeSlotModal);
  $("#btnCancelHomeSlot")?.addEventListener("click", closeSlotModal);
  $("#homeSlotForm")?.addEventListener("submit", createSlotFromForm);

  $("#btnCloseHomeInvite")?.addEventListener("click", closeInviteModal);
  $("#btnCancelHomeInvite")?.addEventListener("click", closeInviteModal);
  $("#btnCloseInviteResult")?.addEventListener("click", closeInviteModal);
  $("#btnCopyInviteLink")?.addEventListener("click", copyInviteLink);
  $("#homeInviteForm")?.addEventListener("submit", inviteFromForm);

  $("#homeProjectsSearch")?.addEventListener("input", (e) => {
    projectSearchQuery = e.target.value || "";
    renderList();
  });

  $("#btnHomeBackToWorkspace")?.addEventListener("click", (e) => {
    e.preventDefault();
    if (typeof window.goToWorkspace === "function") {
      window.goToWorkspace();
    } else {
      close();
      window.setNavActive?.("workspace");
    }
  });

  $("#homeProjectsDetail")?.addEventListener("click", (e) => {
    const link = e.target.closest("[data-home-footer]");
    if (!link) return;
    e.preventDefault();
    const action = link.getAttribute("data-home-footer");
    if (action === "workspace") {
      $("#btnHomeBackToWorkspace")?.click();
    } else if (action === "plans") {
      document.getElementById("btnPlans")?.click();
    } else if (action === "account") {
      document.getElementById("btnAccount")?.click();
    }
  });

  handlePendingInvite();

  window.HomeProjectsUI = { open, close, loadProjects };
})();
