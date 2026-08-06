const SETTINGS_KEY = "plano_ia_settings";
const THEME_KEY = "plano_ia_theme";
const SIDEBAR_KEY = "plano_ia_sidebar_collapsed";

const $ = (sel) => document.querySelector(sel);

let chats = [];
let currentChatId = null;
let attachedFile = null;
let previewObjectUrl = null;
let previewRequestId = 0;
let pendingPrompt = null;
let settings = { weights: "", ppm: 100, conf: 0.25, autoCalibrate: true, lastAuto: null };
let isLoading = false;
let attachPreviewLoading = false;
let ensureChatInFlight = null;
const filePreviewCache = new Map();

let modelReady = false;
let currentToolMode = "default";
let isGuestMode = false;
window.getIsGuestMode = () => isGuestMode;
let guestTrial = null;

const GUEST_CHAT_ID = "guest-local";
const SESSION_CHAT_ID = "session-ephemeral";
/** Desactivado: no persistir ni listar chats en servidor. */
const CHAT_PERSISTENCE_ENABLED = false;

const TOOL_MODES = {
  default: "Revisión estructural · IA",
  errors: "Análisis de errores · IA",
  doors: "Revisión de puertas · IA",
  measures: "Cotas y medidas · IA",
};

const PLANO_EXTENSIONS = [
  ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff",
  ".pdf",
];
const PDF_EXTENSIONS = [".pdf"];
const FILE_INPUT_ACCEPT =
  "image/png,image/jpeg,image/webp,image/bmp,image/tiff,application/pdf,.pdf";

function getFileExt(name) {
  const n = (name || "").toLowerCase();
  const i = n.lastIndexOf(".");
  return i >= 0 ? n.slice(i) : "";
}

function isPlanoFile(file) {
  if (!file) return false;
  const ext = getFileExt(file.name);
  if (PLANO_EXTENSIONS.includes(ext)) return true;
  if (file.type?.startsWith("image/")) return true;
  return false;
}

function isPdfFile(file) {
  return (
    PDF_EXTENSIONS.includes(getFileExt(file.name)) ||
    file.type === "application/pdf"
  );
}

function needsServerPreview(file) {
  return isPdfFile(file);
}

function pickPlanoFile(fileList) {
  if (!fileList?.length) return null;
  for (const f of fileList) {
    if (isPlanoFile(f)) return f;
  }
  return null;
}

function handlePlanoFile(file, autoSend = false) {
  if (!isPlanoFile(file)) {
    showToast("Formato no soportado: PNG, JPG o PDF");
    return;
  }
  setAttachment(file);
  if (pendingPrompt || autoSend) {
    const p = pendingPrompt;
    pendingPrompt = null;
    sendMessage(p || undefined);
  } else {
    const label = isPdfFile(file) ? "PDF listo" : "Plano listo";
    showToast(`${label} — pulsa enviar o escribe un comando`);
  }
}

function showToast(msg, optionsOrMs) {
  if (window.PlanoToast?.show) {
    window.PlanoToast.show(msg, optionsOrMs);
    return;
  }
  if (typeof window.showToast === "function" && window.showToast !== showToast) {
    window.showToast(msg, optionsOrMs);
  }
}

function setToolMode(mode) {
  currentToolMode = TOOL_MODES[mode] ? mode : "default";
  const el = document.getElementById("modelName");
  if (el) el.textContent = TOOL_MODES[currentToolMode];
}

function setNavActive(which) {
  document.querySelectorAll(".nav-item").forEach((n) => {
    const id = n.id;
    n.classList.toggle("active", which === "workspace" && id === "btnWorkspace");
    n.classList.toggle("active", which === "home-projects" && id === "btnHomeProjects");
    n.classList.toggle("active", which === "admin" && id === "btnAdmin");
    n.classList.toggle("active", which === "plans" && id === "btnPlans");
    n.classList.toggle("active", which === "settings" && id === "btnSettings");
  });
}
window.setNavActive = setNavActive;

function ensureEphemeralChat() {
  let chat = chats.find((c) => c.id === SESSION_CHAT_ID);
  if (!chat) {
    chat = {
      id: SESSION_CHAT_ID,
      title: "Sesión actual",
      messages: [],
      messageCount: 0,
      updatedAt: Date.now(),
    };
    chats = [chat];
  }
  currentChatId = SESSION_CHAT_ID;
  return chat;
}

async function loadConfig() {
  try {
    const res = await fetch("/api/config");
    const cfg = await res.json();
    const saved = JSON.parse(localStorage.getItem(SETTINGS_KEY) || "{}");
    settings = {
      weights: saved.weights || cfg.weights,
      ppm: saved.ppm ?? (cfg.default_ppm || 100),
      conf: saved.conf ?? (cfg.default_conf || 0.25),
      autoCalibrate:
        saved.autoCalibrate ?? cfg.auto_calibrate_default ?? true,
      lastAuto: saved.lastAuto || null,
    };
    $("#weightsPath").value = settings.weights;
    $("#ppmInput").value = settings.ppm;
    $("#confInput").value = settings.conf;
    const autoEl = $("#autoCalibrate");
    if (autoEl) autoEl.checked = settings.autoCalibrate;
    syncCalibrationInputs();

    modelReady = cfg.weights_exists;
    const banner = $("#setupBanner");
    const sub = $("#welcomeSub");
    if (!modelReady) {
      banner.hidden = false;
      sub.hidden = false;
      sub.textContent =
        "Sin modelo aún. Ejecuta python scripts/train_demo.py y recarga la página.";
      banner.innerHTML =
        '<strong class="font-semibold">Sin modelo entrenado.</strong> ' +
        "<span>Terminal: <code class=\"rounded bg-black/10 px-1\">python scripts/train_demo.py</code></span>";
      const statusEl = document.getElementById("systemStatusText");
      if (statusEl) statusEl.textContent = "SYSTEM WAIT: modelo no cargado";
    } else {
      banner.hidden = true;
      sub.hidden = false;
      sub.textContent =
        "Pregunta sobre construcción (medidas, normativa, etc.) o sube un plano para revisarlo.";
      const statusEl = document.getElementById("systemStatusText");
      if (statusEl) statusEl.textContent = "SYSTEM READY: plano_ia_engine_v3.0";
    }
  } catch (_) {
    /* offline */
  }
}

function getTheme() {
  const t = localStorage.getItem(THEME_KEY);
  return t === "light" ? "light" : "dark";
}

function applyTheme(theme) {
  const next = theme === "dark" ? "dark" : "light";
  const root = document.documentElement;
  root.setAttribute("data-theme", next);
  root.classList.remove("light", "dark");
  root.classList.add(next);
  root.style.colorScheme = next;
  localStorage.setItem(THEME_KEY, next);

  document.querySelectorAll(".theme-option").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.theme === next);
  });
}

function updateLayoutMode() {
  const chat = getCurrentChat();
  const active = !!(chat && chat.messages.length);
  document.body.classList.toggle("chat-active", active);
}

function syncCalibrationInputs() {
  const auto = $("#autoCalibrate")?.checked ?? settings.autoCalibrate;
  settings.autoCalibrate = auto;
  const ppmEl = $("#ppmInput");
  const confEl = $("#confInput");
  if (ppmEl) ppmEl.disabled = auto;
  if (confEl) confEl.disabled = auto;
  const help = $("#autoCalHelp");
  if (help) {
    help.textContent = auto
      ? "Se estiman píxeles/m y confianza a partir de puertas y detecciones del plano."
      : "Desactivado: usa los valores manuales en cada análisis.";
  }
  const readout = $("#autoCalReadout");
  if (readout) {
    if (auto && settings.lastAuto) {
      readout.textContent = `Último plano: ${settings.lastAuto.ppm} px/m, confianza ${settings.lastAuto.conf}`;
      readout.classList.remove("hidden");
    } else {
      readout.classList.add("hidden");
    }
  }
}

function saveSettings() {
  settings.weights = $("#weightsPath").value.trim();
  settings.autoCalibrate = $("#autoCalibrate")?.checked ?? true;
  if (!settings.autoCalibrate) {
    settings.ppm = parseFloat($("#ppmInput").value) || 100;
    settings.conf = parseFloat($("#confInput").value) || 0.25;
  }
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
  syncCalibrationInputs();
  showToast("Ajustes guardados");
}

function rememberAutoCalibration(data) {
  const auto = data?.auto_calibration;
  if (!auto) return;
  settings.lastAuto = {
    ppm: Math.round(auto.pixels_per_meter),
    conf: Number(auto.confidence).toFixed(2),
  };
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
  syncCalibrationInputs();
}

const ISSUE_LABELS = {
  DOOR_WIDTH_MIN: "Ancho mínimo de puerta (acceso)",
  DOOR_HEIGHT_MIN: "Altura libre de vano / accesibilidad",
  DOOR_OFF_WALL: "Puerta sin muro de apoyo",
  DOOR_WINDOW_OVERLAP: "Puerta y ventana superpuestas",
  WINDOW_WIDTH_MIN: "Ancho mínimo de ventana",
  WINDOW_AREA_MIN: "Área mínima de ventana",
  WINDOW_LIGHT_RATIO: "Iluminación natural insuficiente (1/8)",
  ROOM_AREA_MIN: "Área mínima de pieza habitable",
  ROOM_DIMENSION_MIN: "Dimensión mínima de pieza (2.70 m)",
  ROOM_VENTILATION_OPENING: "Ventilación natural insuficiente",
  BUILDING_INCOMPLETE: "Plano sin recintos ni cerramiento",
  HABITABILITY_NO_WINDOWS: "Recintos sin ventanas",
  ROOM_NO_WINDOW: "Recinto sin ventana",
  ROOM_NO_DOOR_ACCESS: "Recinto sin acceso",
  WINDOW_PER_ROOM_LOW: "Pocas ventanas en el conjunto",
  DOOR_PER_ROOM_LOW: "Pocos accesos entre recintos",
  DWELLING_ROOM_COUNT: "Pocos recintos para vivienda",
  CORRIDOR_WIDTH_MIN: "Circulación estrecha",
  BATHROOM_VENTILATION: "Sanitario sin ventilación",
  KITCHEN_VENTILATION: "Cocina sin ventana",
  BEDROOM_LIGHTING: "Recámara sin iluminación",
  BUILT_AREA_MINOR_WORK: "Superficie / licencia de obra",
  WALL_COVERAGE_LOW: "Cerramiento insuficiente",
  CONSTRUCTION_MANUAL_REVIEW: "Revisión complementaria de proyecto",
};

function groupIssuesFromList(issues) {
  if (!issues?.length) return null;
  const map = new Map();
  for (const i of issues) {
    const prev = map.get(i.code);
    if (!prev) {
      map.set(i.code, {
        code: i.code,
        label: i.label || ISSUE_LABELS[i.code] || i.code,
        severity: i.severity,
        count: 1,
        sample_message: i.message,
        norm_ref: i.norm_ref || null,
      });
    } else {
      prev.count += 1;
    }
  }
  return [...map.values()].sort((a, b) => {
    const order = { error: 0, warning: 1, info: 2 };
    if (a.severity !== b.severity) {
      return (order[a.severity] ?? 9) - (order[b.severity] ?? 9);
    }
    return b.count - a.count;
  });
}

function groupDetectionsFromList(detections) {
  if (!detections?.length) return null;
  const labels = { door: "Puertas", window: "Ventanas", wall: "Muros", room: "Habitaciones" };
  const counts = {};
  for (const d of detections) {
    counts[d.class] = (counts[d.class] || 0) + 1;
  }
  return Object.entries(counts)
    .sort((a, b) => b[1] - a[1])
    .map(([cls, count]) => ({ class: cls, label: labels[cls] || cls, count }));
}

function findLastAnalysisId(chat) {
  if (!chat?.messages?.length) return chat?.lastAnalysisId || null;
  for (let i = chat.messages.length - 1; i >= 0; i--) {
    const m = chat.messages[i];
    if (m.analysisId) return m.analysisId;
  }
  return chat.lastAnalysisId || null;
}

function wantsPlanMeasures(text) {
  const p = (text || "").toLowerCase();
  if (!/medida|cota|dimensi[oó]n|ancho|alto|metro|superficie/.test(p)) return false;
  return /plano|este|ese|mi\s|adjunt|dibujo|l[aá]mina|todas?\s+las?\s+medidas|dame\s+las|listar|cu[aá]nto\s+mide/.test(p);
}

function looksLikeCorrection(text) {
  const t = (text || "").toLowerCase();
  if (t.length < 8) return false;
  return /no es|no hay|incorrecto|mal detect|equivocad|correg|corrige|en realidad|deber[ií]a ser|ahi hay|ah[ií] hay|falso positivo|aprende/.test(
    t,
  );
}

const CORRECTION_RELABEL_OPTIONS = [
  { class: "wall", label: "Es muro" },
  { class: "door", label: "Es puerta" },
  { class: "window", label: "Es ventana" },
  { class: "room", label: "Es recinto" },
];

function mapMessageFromApi(m) {
  const c = m.content || {};
  if (m.role === "assistant") {
    return {
      role: "assistant",
      text: c.text || "",
      steps: c.steps || null,
      imageUrl: c.image_base64 ? `data:image/jpeg;base64,${c.image_base64}` : null,
      stats: c.stats || null,
      issuesSummary: c.issues_summary || groupIssuesFromList(c.issues),
      detectionsSummary: c.detections_summary || groupDetectionsFromList(c.detections),
      scaleHint: c.scale_hint || null,
      autoCalibration: c.auto_calibration || null,
      constructionCoverage: c.construction_coverage || null,
      knowledgeReferences: c.knowledge_references || null,
      verdict: c.verdict || null,
      analysisIntent: c.analysis_intent || null,
      customFindings: c.custom_findings || null,
      measuresReport: c.measures_report || null,
      analysisId: c.analysis_id || m.analysis_id || null,
      localSources: c.local_sources || null,
      webSources: c.web_sources || null,
      municipality: c.municipality || null,
      conversionNote: c.conversion_note || null,
      detectionsList: c.detections_list || c.detections || [],
      correctionsCount: c.corrections_count || 0,
      assistantMode: c.assistant_mode || null,
    };
  }
  const filename = c.filename || "";
  const ext = getFileExt(filename);
  return {
    role: "user",
    text: c.text || "",
    analysisId: c.analysis_id || m.analysis_id || null,
    imageUrl: null,
    attachment: filename
      ? {
          name: filename,
          extLabel: (ext.replace(".", "") || "archivo").toUpperCase(),
          sizeLabel: "",
          kind: ext === ".pdf" ? "pdf" : "image",
        }
      : null,
  };
}

let askCapabilities = null;

async function loadAskCapabilities() {
  try {
    const res = await fetch("/api/ask/status");
    if (!res.ok) return;
    askCapabilities = await res.json();
    applyAskCapabilitiesUI();
  } catch {
    /* offline */
  }
}

function applyAskCapabilitiesUI() {
  const aiOn = askCapabilities?.architect_ai_enabled !== false;
  const hasLibrary = askCapabilities?.architect_ai_ready || (askCapabilities?.knowledge_pages || 0) > 0;
  const input = $("#messageInput");
  if (input) {
    const short = window.matchMedia("(max-width: 640px)").matches;
    input.placeholder = short
      ? "Pregunta a ARCHITECT…"
      : "Pregunta sobre arquitectura, normativa u obra…";
  }
  const hero = document.querySelector(".welcome-hero h2");
  if (hero && !isGuestMode) {
    hero.textContent = "¿En qué te ayudamos hoy?";
  }
  const welcomeSub = $("#welcomeSub");
  const setupBanner = $("#setupBanner");
  if (welcomeSub && (!setupBanner || setupBanner.hidden)) {
    if (isGuestMode) {
      welcomeSub.textContent =
        "Prueba gratis: pregunta lo que quieras o sube un plano. ARCHITECT responde con la información que ya tiene indexada.";
    } else if (modelReady !== false) {
      welcomeSub.textContent = hasLibrary
        ? "ARCHITECT responde con tus manuales, normas de Chiapas y fuentes indexadas. También puedes subir planos."
        : "ARCHITECT usa normas de Chiapas y búsqueda web. Indexa PDF en data/knowledge/raw para ampliar respuestas.";
    }
  }
  const badge = $("#assistantModeBadge");
  if (badge) {
    badge.hidden = !aiOn;
    badge.textContent = hasLibrary ? "IA ARCHITECT activa" : "IA ARCHITECT (normas + web)";
  }
}

function assistantModeLabel(mode) {
  if (mode === "architect" || mode === "rules") return "IA ARCHITECT";
  if (mode === "llm") return "IA conversacional";
  return "";
}

function parseApiDetail(data, fallback) {
  if (!data) return fallback;
  const d = data.detail;
  if (typeof d === "string") return d;
  if (d && typeof d === "object" && d.message) return d.message;
  return fallback;
}

function isTrialExhaustedResponse(data, status) {
  return (
    status === 402 &&
    data?.detail &&
    typeof data.detail === "object" &&
    data.detail.code === "trial_exhausted"
  );
}

function showTrialEndedModal() {
  const loginUrl = trialLoginUrl();
  const loginLink = $("#trialLoginLink");
  const registerLink = $("#trialRegisterLink");
  if (loginLink) loginLink.href = loginUrl;
  if (registerLink) registerLink.href = `${loginUrl}${loginUrl.includes("?") ? "&" : "?"}tab=register`;
  const modal = $("#trialModal");
  if (modal?.showModal) modal.showModal();
  else showToast("Tu prueba terminó. Inicia sesión o crea una cuenta en /login");
}

function trialLoginUrl() {
  const next = encodeURIComponent(window.location.pathname + window.location.search);
  return `/login?next=${next}`;
}
window.showTrialEndedModal = showTrialEndedModal;

async function guestFetch(url, options = {}) {
  return fetch(url, { ...options, credentials: "include" });
}

function updateGuestTrialUI() {
  const bar = $("#guestTrialBar");
  const text = $("#guestTrialText");
  if (!guestTrial) return;
  if (bar) bar.hidden = false;
  const parts = [];
  if (guestTrial.analyses_remaining > 0) {
    parts.push(
      `${guestTrial.analyses_remaining} análisis de plano`,
    );
  }
  if (guestTrial.asks_remaining > 0) {
    parts.push(`${guestTrial.asks_remaining} pregunta sin plano`);
  }
  if (text) {
    if (parts.length) {
      text.textContent = `Prueba gratuita: te queda ${parts.join(" y ")}.`;
    } else {
      text.textContent = "Prueba gratuita agotada.";
    }
  }
  const badge = $("#planBadge");
  if (badge) badge.textContent = "PRUEBA";
  if (guestTrial.trial_exhausted) {
    showTrialEndedModal();
  }
}

async function loadGuestTrialStatus() {
  try {
    const res = await guestFetch("/api/guest/status");
    guestTrial = await res.json();
    updateGuestTrialUI();
  } catch {
    guestTrial = {
      analyses_remaining: 1,
      asks_remaining: 1,
      trial_exhausted: false,
    };
  }
}

function ensureGuestChat() {
  let chat = chats.find((c) => c.id === GUEST_CHAT_ID);
  if (!chat) {
    chat = {
      id: GUEST_CHAT_ID,
      title: "Prueba gratuita",
      messages: [],
      messageCount: 0,
      updatedAt: Date.now(),
    };
    chats = [chat];
  }
  currentChatId = GUEST_CHAT_ID;
  return chat;
}

function updateGuestUI() {
  $("#guestSidebarActions")?.classList.remove("hidden");
  $("#guestSidebarActions")?.classList.add("flex");
  $("#btnLogout")?.classList.add("hidden");
  $("#usageBar")?.classList.add("hidden");
  const av = document.getElementById("userAvatar");
  if (av) {
    av.classList.remove("has-photo");
    av.style.removeProperty("background-image");
    av.textContent = "?";
  }
  const nameEl = document.getElementById("userName");
  if (nameEl) nameEl.textContent = "Modo prueba";
  const roleEl = document.getElementById("userRole");
  if (roleEl) roleEl.textContent = "Sin cuenta";
  const welcomeSub = document.getElementById("welcomeSub");
  if (welcomeSub) {
    welcomeSub.textContent =
      "Prueba gratis: pregunta lo que quieras o sube un plano. ARCHITECT responde con la información que ya tiene indexada.";
  }
}

async function initGuestApp(skipWorkspace = false) {
  isGuestMode = true;
  updateGuestUI();
  await checkBackendHealth();
  await Promise.allSettled([loadConfig(), loadAskCapabilities()]);
  await loadGuestTrialStatus();
  ensureGuestChat();
  if (!skipWorkspace) goToWorkspace();
  updateSendButton();
}

async function initAuthenticatedApp(skipWorkspace = false) {
  isGuestMode = false;
  await checkBackendHealth();
  try {
    await PlanoAuth.refreshMe();
  } catch (e) {
    console.warn("refreshMe:", e);
  }
  updateUserUI();
  const bootTasks = [loadConfig(), loadAskCapabilities()];
  if (CHAT_PERSISTENCE_ENABLED) {
    bootTasks.push(loadChats(), loadAnalysisHistory());
  } else {
    ensureEphemeralChat();
  }
  await Promise.allSettled(bootTasks);
  applyAskCapabilitiesUI();
  setAttachment(null);
  currentChatId = null;
  if (!skipWorkspace) goToWorkspace();
  updateSendButton();
  updateLayoutMode();
  measureLatency();
  setInterval(measureLatency, 15000);
}

async function loadChats() {
  if (!CHAT_PERSISTENCE_ENABLED && !isGuestMode) {
    chats = [];
    ensureEphemeralChat();
    return;
  }
  if (isGuestMode) {
    chats = [];
    renderChatList();
    return;
  }
  try {
    const res = await PlanoAuth.apiFetch("/api/chats");
    const rows = await res.json();
    chats = rows.map((c) => ({
      id: c.id,
      title: c.title,
      messages: [],
      messageCount: c.message_count || 0,
      updatedAt: new Date(c.updated_at).getTime() || Date.now(),
    }));
  } catch {
    chats = [];
  }
  renderChatList();
}

function saveChats() {
  renderChatList();
}

function previewCacheKey(file) {
  if (!file) return "";
  return `${file.name}|${file.size}|${file.lastModified}`;
}

async function ensureChat() {
  if (isGuestMode) return ensureGuestChat();
  if (!CHAT_PERSISTENCE_ENABLED) return ensureEphemeralChat();
  const existing = getCurrentChat();
  if (existing) return existing;
  if (ensureChatInFlight) return ensureChatInFlight;

  ensureChatInFlight = (async () => {
    const res = await PlanoAuth.apiFetch("/api/chats", {
      method: "POST",
      body: JSON.stringify({ title: "Nuevo chat" }),
    });
    if (!res.ok) throw new Error("No se pudo crear el chat");
    const c = await res.json();
    const chat = {
      id: c.id,
      title: c.title,
      messages: [],
      messageCount: 0,
      updatedAt: Date.now(),
    };
    chats.unshift(chat);
    currentChatId = chat.id;
    saveChats();
    return chat;
  })();

  try {
    return await ensureChatInFlight;
  } finally {
    ensureChatInFlight = null;
  }
}

async function newChat(showNotice = true) {
  if (!CHAT_PERSISTENCE_ENABLED && !isGuestMode) {
    chats = [];
    ensureEphemeralChat();
    $("#welcome").hidden = false;
    $("#messages").hidden = true;
    $("#messages").innerHTML = "";
    setAttachment(null);
    updateLayoutMode();
    if (showNotice) showToast("Nueva sesión");
    return;
  }
  if (isGuestMode) {
    chats = [];
    ensureGuestChat();
    $("#welcome").hidden = false;
    $("#messages").hidden = true;
    $("#messages").innerHTML = "";
    setAttachment(null);
    updateLayoutMode();
    renderChatList();
    if (showNotice) showToast("Nueva prueba en este chat");
    return;
  }
  try {
    const res = await PlanoAuth.apiFetch("/api/chats", {
      method: "POST",
      body: JSON.stringify({ title: "Nuevo chat" }),
    });
    const c = await res.json();
    const chat = {
      id: c.id,
      title: c.title,
      messages: [],
      messageCount: 0,
      updatedAt: Date.now(),
    };
    chats.unshift(chat);
    currentChatId = chat.id;
    saveChats();
    $("#welcome").hidden = false;
    $("#messages").hidden = true;
    $("#messages").innerHTML = "";
    setAttachment(null);
    updateLayoutMode();
    renderChatList();
    if (showNotice) showToast("Nuevo chat creado");
  } catch (err) {
    showToast(err.message || "Error al crear chat");
  }
}

function goToWorkspace() {
  window.HomeProjectsUI?.close?.();
  const url = new URL(window.location.href);
  url.searchParams.delete("home-projects");
  url.searchParams.delete("project");
  const next = url.pathname + url.search;
  if (window.location.pathname + window.location.search !== next) {
    window.history.replaceState({}, "", next);
  }
  setNavActive("workspace");
  $("#welcome").hidden = false;
  $("#messages").hidden = true;
  $("#messages").innerHTML = "";
  setAttachment(null);
  pendingPrompt = null;
  updateLayoutMode();
  renderChatList();
  setToolMode("default");
}
window.goToWorkspace = goToWorkspace;

async function persistMessage(role, text) {
  const chat = await ensureChat();
  if (!CHAT_PERSISTENCE_ENABLED && !isGuestMode) {
    chat.messageCount = (chat.messageCount || 0) + 1;
    chat.updatedAt = Date.now();
    if (role === "user") {
      chat.title = text.slice(0, 120) || chat.title;
    }
    return { id: `local-${Date.now()}`, role, text };
  }
  const res = await PlanoAuth.apiFetch(`/api/chats/${chat.id}/messages`, {
    method: "POST",
    body: JSON.stringify({ role, text }),
  });
  if (!res.ok) return null;
  const msg = await res.json();
  chat.messageCount = (chat.messageCount || 0) + 1;
  chat.updatedAt = Date.now();
  if (role === "user" && chat.title === "Nuevo chat") {
    chat.title = text.slice(0, 120);
  }
  return msg;
}

function getCurrentChat() {
  return chats.find((c) => c.id === currentChatId);
}

async function showChat(chat) {
  currentChatId = chat.id;
  const welcome = $("#welcome");
  const messages = $("#messages");

  if (!CHAT_PERSISTENCE_ENABLED && !isGuestMode && chat.id === SESSION_CHAT_ID) {
    if (!chat.messages.length) {
      welcome.hidden = false;
      messages.hidden = true;
      messages.innerHTML = "";
    } else {
      welcome.hidden = true;
      messages.hidden = false;
      messages.innerHTML = "";
      chat.messages.forEach((m) => appendMessageDOM(m, false));
      scrollToBottom();
    }
    updateLayoutMode();
    return;
  }

  if (isGuestMode && chat.id === GUEST_CHAT_ID) {
    if (!chat.messages.length) {
      welcome.hidden = false;
      messages.hidden = true;
      messages.innerHTML = "";
    } else {
      welcome.hidden = true;
      messages.hidden = false;
      messages.innerHTML = "";
      chat.messages.forEach((m) => appendMessageDOM(m, false));
      scrollToBottom();
    }
    updateLayoutMode();
    renderChatList();
    return;
  }

  try {
    const res = await PlanoAuth.apiFetch(`/api/chats/${chat.id}`);
    const data = await res.json();
    chat.title = data.chat.title;
    chat.messages = (data.messages || []).map(mapMessageFromApi);
    chat.updatedAt = new Date(data.chat.updated_at).getTime() || Date.now();
  } catch {
    chat.messages = chat.messages || [];
  }

  if (!chat.messages.length) {
    welcome.hidden = false;
    messages.hidden = true;
    messages.innerHTML = "";
  } else {
    welcome.hidden = true;
    messages.hidden = false;
    messages.innerHTML = "";
    chat.messages.forEach((m) => appendMessageDOM(m, false));
    scrollToBottom();
  }
  updateLayoutMode();
  renderChatList();
}

function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text ?? "";
  return div.innerHTML;
}

async function deleteChat(chatId, listItem) {
  if (!listItem || listItem.classList.contains("is-removing")) return;
  if (
    !(await PlanoDialog.confirm("¿Eliminar este chat y todo su historial?", {
      title: "Eliminar chat",
      variant: "danger",
      confirmLabel: "Eliminar",
    }))
  ) {
    return;
  }

  listItem.classList.add("is-removing");
  listItem.style.pointerEvents = "none";

  let res;
  try {
    res = await PlanoAuth.apiFetch(`/api/chats/${encodeURIComponent(chatId)}`, {
      method: "DELETE",
    });
  } catch (err) {
    listItem.classList.remove("is-removing");
    listItem.style.pointerEvents = "";
    showToast(err.message || "No se pudo eliminar el chat");
    return;
  }

  if (!res.ok) {
    let detail = "No se pudo eliminar el chat";
    try {
      const data = await res.json();
      detail = PlanoAuth.formatApiError(data, detail);
    } catch {
      /* sin cuerpo JSON */
    }
    listItem.classList.remove("is-removing");
    listItem.style.pointerEvents = "";
    showToast(detail);
    return;
  }

  const wasCurrent = currentChatId === chatId;
  chats = chats.filter((c) => c.id !== chatId);

  if (wasCurrent) {
    if (chats.length) {
      await showChat(chats[0]);
    } else {
      currentChatId = null;
      $("#welcome").hidden = false;
      $("#messages").hidden = true;
      $("#messages").innerHTML = "";
      updateLayoutMode();
    }
  }

  renderChatList();
  await loadAnalysisHistory();
  showToast("Chat eliminado");
}

function renderChatList() {
  if (!CHAT_PERSISTENCE_ENABLED) return;
  const list = $("#chatList");
  if (!list) return;
  const q = ($("#searchChats").value || "").toLowerCase();
  list.innerHTML = "";
  chats
    .filter((c) => !q || c.title.toLowerCase().includes(q))
    .forEach((c) => {
      const li = document.createElement("li");
      li.className = "chat-item";
      li.dataset.chatId = c.id;
      if (c.id === currentChatId) li.classList.add("active");

      const row = document.createElement("div");
      row.className = "chat-item-row";

      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "chat-item-btn";
      const meta =
        c.messageCount > 0
          ? `<span class="chat-meta">${c.messageCount} mensaje${c.messageCount === 1 ? "" : "s"}</span>`
          : "";
      btn.innerHTML = `<span class="chat-name">${escapeHtml(c.title)}</span>${meta}`;
      btn.onclick = () => showChat(c);

      const del = document.createElement("button");
      del.type = "button";
      del.className = "chat-item-delete";
      del.title = "Eliminar chat";
      del.setAttribute("aria-label", "Eliminar chat");
      del.innerHTML = '<span class="material-symbols-outlined">close</span>';
      del.onclick = (e) => {
        e.stopPropagation();
        deleteChat(c.id, li);
      };

      row.appendChild(btn);
      row.appendChild(del);
      li.appendChild(row);
      list.appendChild(li);
    });
}

function buildResultsPanel(msg) {
  const panel = document.createElement("div");
  panel.className = "results-panel";

  if (msg.verdict?.headline) {
    const box = document.createElement("div");
    box.className = `verdict-banner verdict-banner--${msg.verdict.tone || "caution"}`;
    box.innerHTML = `<strong>${escapeHtml(msg.verdict.headline)}</strong>`;
    if (msg.verdict.detail) {
      const det = document.createElement("p");
      det.className = "verdict-detail";
      det.textContent = msg.verdict.detail;
      box.appendChild(det);
    }
    panel.appendChild(box);
  } else if (msg.analysisIntent?.title) {
    const focus = document.createElement("p");
    focus.className = "results-focus";
    focus.textContent = `Enfoque: ${msg.analysisIntent.title}`;
    panel.appendChild(focus);
  }

  if (msg.customFindings?.length) {
    const cfSec = document.createElement("div");
    cfSec.className = "results-section";
    const cfTitle = document.createElement("h4");
    cfTitle.className = "results-section-title";
    cfTitle.textContent = "Tu pregunta";
    cfSec.appendChild(cfTitle);
    msg.customFindings.forEach((cf) => {
      const row = document.createElement("p");
      row.className = `custom-finding custom-finding--${cf.severity || "info"}`;
      row.textContent = (cf.severity === "ok" ? "✓ " : "• ") + (cf.message || "");
      cfSec.appendChild(row);
    });
    panel.appendChild(cfSec);
  }

  if (msg.stats) {
    const summary = document.createElement("div");
    summary.className = "results-summary";
    const verdict =
      msg.stats.errors > 0
        ? "fail"
        : msg.stats.warnings > 0
          ? "warn"
          : "ok";
    summary.innerHTML = `
      <div class="results-verdict results-verdict--${verdict}">
        <span class="results-verdict-num">${msg.stats.errors}</span>
        <span class="results-verdict-label">errores</span>
      </div>
      <div class="results-verdict results-verdict--warn">
        <span class="results-verdict-num">${msg.stats.warnings}</span>
        <span class="results-verdict-label">avisos</span>
      </div>
      <div class="results-verdict results-verdict--neutral">
        <span class="results-verdict-num">${msg.stats.detections}</span>
        <span class="results-verdict-label">detecciones</span>
      </div>
    `;
    panel.appendChild(summary);
  }

  if (msg.autoCalibration?.summary) {
    const cal = document.createElement("p");
    cal.className = "results-calibration";
    cal.textContent = msg.autoCalibration.summary;
    panel.appendChild(cal);
  }

  if (msg.scaleHint) {
    const hint = document.createElement("p");
    hint.className = "results-hint";
    hint.textContent = msg.scaleHint;
    panel.appendChild(hint);
  }

  if (msg.knowledgeReferences?.length) {
    const refSec = document.createElement("div");
    refSec.className = "results-section knowledge-refs";
    const refTitle = document.createElement("h4");
    refTitle.className = "results-section-title";
    refTitle.textContent = "Referencias de tus documentos";
    refSec.appendChild(refTitle);
    const list = document.createElement("ul");
    list.className = "knowledge-ref-list";
    msg.knowledgeReferences.forEach((r) => {
      const li = document.createElement("li");
      li.innerHTML = `<strong>${escapeHtml(r.doc_title || "Manual")}</strong> (pág. ${r.page})<br><span>${escapeHtml(r.snippet || "")}</span>`;
      list.appendChild(li);
    });
    refSec.appendChild(list);
    panel.appendChild(refSec);
  }

  if (msg.constructionCoverage?.length) {
    const okN = msg.constructionCoverage.filter((d) => d.status === "revisado").length;
    const incN = msg.constructionCoverage.filter((d) => d.status === "incidencias").length;
    const manN = msg.constructionCoverage.filter(
      (d) => d.status !== "revisado" && d.status !== "incidencias",
    ).length;

    const covSec = document.createElement("details");
    covSec.className = "results-section construction-coverage construction-coverage--folded";
    const summary = document.createElement("summary");
    summary.className = "construction-coverage-summary";
    summary.textContent =
      incN > 0
        ? `Ámbitos de construcción (${okN} OK, ${incN} con incidencias, ${manN} solo manual) — clic para ver`
        : `Ámbitos de construcción (${okN} revisados en planta, ${manN} requieren revisión manual) — clic para ver`;
    covSec.appendChild(summary);

    const hint = document.createElement("p");
    hint.className = "construction-coverage-hint";
    hint.textContent =
      "Las tarjetas «Manual» no se validan solo con la imagen; confirma en cortes, instalaciones o memoria de cálculo.";
    covSec.appendChild(hint);

    const grid = document.createElement("div");
    grid.className = "construction-grid";
    msg.constructionCoverage.forEach((d) => {
      const item = document.createElement("div");
      const st = d.status || "manual";
      item.className = `construction-item construction-item--${st}`;
      const badge =
        st === "revisado" ? "OK" : st === "incidencias" ? "Incidencia" : "Manual";
      item.innerHTML = `<span class="construction-badge">${badge}</span><strong>${escapeHtml(d.title)}</strong><span class="construction-scope">${escapeHtml(d.scope)}</span>`;
      grid.appendChild(item);
    });
    covSec.appendChild(grid);
    if (incN > 0) covSec.open = true;
    panel.appendChild(covSec);
  }

  if (msg.measuresReport?.items?.length) {
    const mSec = document.createElement("div");
    mSec.className = "results-section measures-table-section";
    const mTitle = document.createElement("h4");
    mTitle.className = "results-section-title";
    mTitle.textContent = "Medidas por elemento";
    mSec.appendChild(mTitle);
    const table = document.createElement("div");
    table.className = "measures-table";
    msg.measuresReport.items.forEach((it) => {
      const row = document.createElement("div");
      row.className = "measures-row";
      row.innerHTML = `
        <span class="measures-num">${it.num}</span>
        <span class="measures-type">${escapeHtml(it.tipo)}</span>
        <span class="measures-dim">${it.ancho_m} × ${it.largo_m} m</span>
        <span class="measures-area">${it.area_m2} m²</span>
      `;
      table.appendChild(row);
    });
    mSec.appendChild(table);
    panel.appendChild(mSec);
  }

  if (msg.detectionsSummary?.length) {
    const detSec = document.createElement("div");
    detSec.className = "results-section";
    const detTitle = document.createElement("h4");
    detTitle.className = "results-section-title";
    detTitle.textContent = "Elementos detectados";
    detSec.appendChild(detTitle);
    const chips = document.createElement("div");
    chips.className = "det-chips";
    msg.detectionsSummary.forEach((d) => {
      const chip = document.createElement("span");
      chip.className = "det-chip";
      chip.textContent = `${d.label || d.class}: ${d.count}`;
      chips.appendChild(chip);
    });
    detSec.appendChild(chips);
    panel.appendChild(detSec);
  }

  if (msg.analysisId && msg.detectionsList?.length && !isGuestMode) {
    const corrSec = document.createElement("div");
    corrSec.className = "results-section corrections-section";
    const corrTitle = document.createElement("h4");
    corrTitle.className = "results-section-title";
    corrTitle.textContent = "¿Algo está mal? Corrige y el sistema aprende";
    corrSec.appendChild(corrTitle);

    const corrHint = document.createElement("p");
    corrHint.className = "corrections-hint";
    corrHint.textContent =
      "Si el modelo se equivocó (por ejemplo ventana donde hay muro), marca la detección. También puedes escribir en el chat: «esa ventana no es ventana, ahí hay muro».";
    corrSec.appendChild(corrHint);

    if (msg.correctionsCount > 0) {
      const saved = document.createElement("p");
      saved.className = "corrections-saved";
      saved.textContent = `${msg.correctionsCount} corrección(es) guardada(s) en este plano.`;
      corrSec.appendChild(saved);
    }

    const list = document.createElement("div");
    list.className = "corrections-list";
    msg.detectionsList.forEach((det) => {
      const row = document.createElement("div");
      row.className = "correction-row";
      const conf = Math.round((det.confidence || 0) * 100);
      row.innerHTML = `
        <div class="correction-row-meta">
          <strong>${escapeHtml(det.label || det.class)}</strong>
          <span>${conf}% · ${Math.round(det.width_px || 0)}×${Math.round(det.height_px || 0)} px</span>
        </div>
      `;
      const actions = document.createElement("div");
      actions.className = "correction-row-actions";

      const rejectBtn = document.createElement("button");
      rejectBtn.type = "button";
      rejectBtn.className = "correction-btn correction-btn--reject";
      rejectBtn.textContent = "No es correcto";
      rejectBtn.onclick = () =>
        applyDetectionCorrection(msg.analysisId, det.idx, "reject", null, row);

      actions.appendChild(rejectBtn);
      CORRECTION_RELABEL_OPTIONS.forEach((opt) => {
        if (opt.class === det.class) return;
        const b = document.createElement("button");
        b.type = "button";
        b.className = "correction-btn";
        b.textContent = opt.label;
        b.onclick = () =>
          applyDetectionCorrection(msg.analysisId, det.idx, "relabel", opt.class, row);
        actions.appendChild(b);
      });

      row.appendChild(actions);
      list.appendChild(row);
    });
    corrSec.appendChild(list);
    panel.appendChild(corrSec);
  }

  if (msg.issuesSummary?.length) {
    const issSec = document.createElement("div");
    issSec.className = "results-section";
    const issTitle = document.createElement("h4");
    issTitle.className = "results-section-title";
    issTitle.textContent = "Incidencias por regla";
    issSec.appendChild(issTitle);

    const list = document.createElement("div");
    list.className = "issue-groups";
    msg.issuesSummary.forEach((g) => {
      const row = document.createElement("div");
      row.className = `issue-group issue-group--${g.severity}`;
      const badge =
        g.severity === "error"
          ? "Error"
          : g.severity === "info"
            ? "Revisión"
            : "Aviso";
      const countLabel = g.count > 1 ? ` ×${g.count}` : "";
      const norm = g.norm_ref ? `<span class="issue-group-norm">${escapeHtml(g.norm_ref)}</span>` : "";
      row.innerHTML = `
        <div class="issue-group-head">
          <span class="issue-group-badge">${badge}</span>
          <span class="issue-group-title">${escapeHtml(g.label || g.code)}${countLabel}</span>
        </div>
        <p class="issue-group-msg">${escapeHtml(g.sample_message || "")}</p>
        ${norm}
      `;
      list.appendChild(row);
    });
    issSec.appendChild(list);
    panel.appendChild(issSec);
  }

  return panel;
}

const imageViewerState = {
  scale: 1,
  panX: 0,
  panY: 0,
  minScale: 0.15,
  maxScale: 8,
};

function applyImageViewerTransform() {
  const img = $("#imageViewerImg");
  if (!img) return;
  img.style.transform = `translate(${imageViewerState.panX}px, ${imageViewerState.panY}px) scale(${imageViewerState.scale})`;
}

function updateImageViewerZoomLabel() {
  const el = $("#imageViewerZoomPct");
  if (el) el.textContent = `${Math.round(imageViewerState.scale * 100)}%`;
}

function resetImageViewerTransform() {
  imageViewerState.scale = 1;
  imageViewerState.panX = 0;
  imageViewerState.panY = 0;
  applyImageViewerTransform();
  updateImageViewerZoomLabel();
}

function fitImageViewerToStage() {
  const stage = $("#imageViewerStage");
  const img = $("#imageViewerImg");
  if (!stage || !img?.naturalWidth) return;
  const pad = 24;
  const sw = Math.max(stage.clientWidth - pad * 2, 100);
  const sh = Math.max(stage.clientHeight - pad * 2, 100);
  const scale = Math.min(sw / img.naturalWidth, sh / img.naturalHeight, 1);
  imageViewerState.scale = scale;
  imageViewerState.panX = 0;
  imageViewerState.panY = 0;
  applyImageViewerTransform();
  updateImageViewerZoomLabel();
}

function zoomImageViewerAt(factor, clientX, clientY) {
  const stage = $("#imageViewerStage");
  if (!stage) return;
  const rect = stage.getBoundingClientRect();
  const cx = clientX - rect.left - rect.width / 2;
  const cy = clientY - rect.top - rect.height / 2;
  const oldScale = imageViewerState.scale;
  const newScale = Math.min(
    imageViewerState.maxScale,
    Math.max(imageViewerState.minScale, oldScale * factor),
  );
  if (Math.abs(newScale - oldScale) < 0.001) return;
  const ratio = newScale / oldScale;
  imageViewerState.panX = cx - (cx - imageViewerState.panX) * ratio;
  imageViewerState.panY = cy - (cy - imageViewerState.panY) * ratio;
  imageViewerState.scale = newScale;
  applyImageViewerTransform();
  updateImageViewerZoomLabel();
}

function zoomImageViewer(factor) {
  const stage = $("#imageViewerStage");
  if (!stage) return;
  const rect = stage.getBoundingClientRect();
  zoomImageViewerAt(factor, rect.left + rect.width / 2, rect.top + rect.height / 2);
}

function openImageViewer(src, caption = "") {
  const modal = $("#imageViewerModal");
  const img = $("#imageViewerImg");
  const cap = $("#imageViewerCaption");
  if (!modal || !img) return;
  resetImageViewerTransform();
  if (cap) cap.textContent = caption || "Plano";
  img.onload = () => fitImageViewerToStage();
  img.src = src;
  modal.showModal();
}

function makeImageZoomable(img, caption) {
  if (!img?.src) return;
  img.classList.add("msg-media-zoomable");
  img.setAttribute("role", "button");
  img.tabIndex = 0;
  img.title = "Clic para ampliar y hacer zoom";
  const open = () => openImageViewer(img.src, caption);
  img.addEventListener("click", open);
  img.addEventListener("keydown", (e) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      open();
    }
  });
}

function touchDistance(touches) {
  const dx = touches[0].clientX - touches[1].clientX;
  const dy = touches[0].clientY - touches[1].clientY;
  return Math.hypot(dx, dy);
}

function setupImageViewer() {
  const modal = $("#imageViewerModal");
  const stage = $("#imageViewerStage");
  const img = $("#imageViewerImg");
  if (!modal || !stage || !img) return;

  $("#btnCloseImageViewer")?.addEventListener("click", () => modal.close());
  $("#btnIvZoomIn")?.addEventListener("click", () => zoomImageViewer(1.25));
  $("#btnIvZoomOut")?.addEventListener("click", () => zoomImageViewer(1 / 1.25));
  $("#btnIvZoomReset")?.addEventListener("click", resetImageViewerTransform);
  $("#btnIvFit")?.addEventListener("click", fitImageViewerToStage);

  modal.addEventListener("close", () => {
    img.removeAttribute("src");
    resetImageViewerTransform();
  });

  stage.addEventListener(
    "wheel",
    (e) => {
      e.preventDefault();
      const factor = e.deltaY < 0 ? 1.12 : 1 / 1.12;
      zoomImageViewerAt(factor, e.clientX, e.clientY);
    },
    { passive: false },
  );

  let drag = null;
  stage.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    drag = {
      startX: e.clientX,
      startY: e.clientY,
      panX: imageViewerState.panX,
      panY: imageViewerState.panY,
    };
    stage.setPointerCapture(e.pointerId);
    stage.classList.add("is-panning");
  });
  const endDrag = () => {
    drag = null;
    stage.classList.remove("is-panning");
  };
  stage.addEventListener("pointermove", (e) => {
    if (!drag) return;
    imageViewerState.panX = drag.panX + (e.clientX - drag.startX);
    imageViewerState.panY = drag.panY + (e.clientY - drag.startY);
    applyImageViewerTransform();
  });
  stage.addEventListener("pointerup", endDrag);
  stage.addEventListener("pointercancel", endDrag);

  stage.addEventListener("dblclick", (e) => {
    if (imageViewerState.scale > 1.4) resetImageViewerTransform();
    else zoomImageViewerAt(2, e.clientX, e.clientY);
  });

  let pinch = null;
  stage.addEventListener(
    "touchstart",
    (e) => {
      if (e.touches.length === 2) {
        pinch = {
          dist: touchDistance(e.touches),
          scale: imageViewerState.scale,
        };
      }
    },
    { passive: true },
  );
  stage.addEventListener(
    "touchmove",
    (e) => {
      if (e.touches.length !== 2 || !pinch) return;
      e.preventDefault();
      const dist = touchDistance(e.touches);
      const factor = dist / pinch.dist;
      imageViewerState.scale = Math.min(
        imageViewerState.maxScale,
        Math.max(imageViewerState.minScale, pinch.scale * factor),
      );
      applyImageViewerTransform();
      updateImageViewerZoomLabel();
    },
    { passive: false },
  );
  stage.addEventListener("touchend", () => {
    pinch = null;
  });

  modal.addEventListener("keydown", (e) => {
    if (e.key === "+" || e.key === "=") {
      e.preventDefault();
      zoomImageViewer(1.25);
    } else if (e.key === "-") {
      e.preventDefault();
      zoomImageViewer(1 / 1.25);
    } else if (e.key === "0") {
      e.preventDefault();
      resetImageViewerTransform();
    }
  });
}

function appendMessageDOM(msg, scroll = true) {
  const wrap = $("#messages");
  const el = document.createElement("div");
  el.className = `msg ${msg.role}`;

  const avatar = document.createElement("div");
  avatar.className = "msg-avatar";
  avatar.textContent = msg.role === "user" ? "Tú" : "IA";

  const body = document.createElement("div");
  body.className = "msg-body";

  if (msg.text) {
    const block = document.createElement("div");
    block.className = "msg-text";
    msg.text.split("\n").forEach((line) => {
      if (!line.trim()) return;
      const p = document.createElement("p");
      p.textContent = line;
      block.appendChild(p);
    });
    body.appendChild(block);
  }

  const modeLabel = assistantModeLabel(msg.assistantMode);
  if (msg.role === "assistant" && modeLabel) {
    const badge = document.createElement("span");
    badge.className = `msg-mode-badge msg-mode-badge--${msg.assistantMode === "llm" ? "llm" : "architect"}`;
    badge.textContent = modeLabel;
    body.appendChild(badge);
  }

  if (msg.steps?.length) {
    const box = document.createElement("div");
    box.className = "msg-steps";
    const title = document.createElement("p");
    title.className = "msg-steps-title";
    title.textContent = "Siguiente paso";
    box.appendChild(title);
    msg.steps.forEach((step, i) => {
      const row = document.createElement("div");
      row.className = "msg-step-row";
      row.innerHTML = `<span class="msg-step-num">${i + 1}</span><code>${step}</code>`;
      box.appendChild(row);
    });
    body.appendChild(box);
  }

  if (msg.attachment || msg.imageUrl) {
    const frame = document.createElement("div");
    frame.className = msg.role === "user" ? "msg-media msg-media--thumb" : "msg-media";

    let mediaCaption = "";
    if (msg.imageUrl) {
      const img = document.createElement("img");
      img.src = msg.imageUrl;
      img.alt = msg.role === "user" ? "Vista previa del plano" : "Plano analizado";
      img.loading = "lazy";
      img.onerror = () => {
        img.remove();
        if (msg.attachment) frame.appendChild(createMsgAttachmentChip(msg.attachment));
      };
      frame.appendChild(img);
    } else if (msg.attachment) {
      frame.appendChild(createMsgAttachmentChip(msg.attachment));
    }

    if (msg.role === "user" && msg.attachment) {
      mediaCaption = `${msg.attachment.name} (${msg.attachment.extLabel})`;
      const cap = document.createElement("span");
      cap.className = "msg-media-caption";
      cap.textContent = mediaCaption;
      frame.appendChild(cap);
    } else if (msg.role === "assistant" && msg.stats?.detections > 0) {
      const marked = msg.stats.errors > 0 ? " (hasta 28 errores numerados)" : "";
      mediaCaption = `Plano con incidencias marcadas${marked}`;
      const cap = document.createElement("span");
      cap.className = "msg-media-caption";
      cap.textContent = mediaCaption;
      frame.appendChild(cap);
    } else if (msg.role === "assistant" && msg.imageUrl) {
      mediaCaption = "Vista del plano analizado";
      const cap = document.createElement("span");
      cap.className = "msg-media-caption";
      cap.textContent = mediaCaption;
      frame.appendChild(cap);
    }
    const zoomImg = frame.querySelector("img");
    if (zoomImg?.src) {
      makeImageZoomable(zoomImg, mediaCaption || zoomImg.alt);
    }
    body.appendChild(frame);
  }

  if (msg.role === "assistant") {
    appendSourcesToBody(body, msg);
  }

  if (msg.stats || msg.detectionsSummary?.length || msg.issuesSummary?.length) {
    body.appendChild(buildResultsPanel(msg));
  }

  el.appendChild(avatar);
  el.appendChild(body);
  wrap.appendChild(el);
  if (scroll) scrollToBottom();
}

function showTyping() {
  const wrap = $("#messages");
  const el = document.createElement("div");
  el.className = "msg assistant";
  el.id = "typingIndicator";
  el.innerHTML = `
    <div class="msg-avatar">IA</div>
    <div class="msg-body"><div class="typing"><span></span><span></span><span></span></div></div>
  `;
  wrap.appendChild(el);
  scrollToBottom();
}

function hideTyping() {
  $("#typingIndicator")?.remove();
}

function scrollToBottom() {
  $("#chatArea").scrollTop = $("#chatArea").scrollHeight;
}

function formatFileSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function clearPreviewUrl() {
  if (previewObjectUrl) {
    URL.revokeObjectURL(previewObjectUrl);
    previewObjectUrl = null;
  }
}

function buildAttachmentMeta(file) {
  const ext = getFileExt(file.name);
  return {
    name: file.name || "plano",
    extLabel: (ext.replace(".", "") || "archivo").toUpperCase(),
    sizeLabel: formatFileSize(file.size),
    kind: isPdfFile(file) ? "pdf" : "image",
  };
}

function attachmentIconName(kind) {
  if (kind === "pdf") return "picture_as_pdf";
  return "draft";
}

function createMsgAttachmentChip(meta) {
  const chip = document.createElement("div");
  chip.className = "msg-attachment-chip";
  chip.innerHTML = `
    <span class="material-symbols-outlined msg-attachment-icon">${attachmentIconName(meta.kind)}</span>
    <div class="msg-attachment-meta">
      <span class="msg-attachment-name">${escapeHtml(meta.name)}</span>
      <span class="msg-attachment-type">${escapeHtml(meta.extLabel)} · ${escapeHtml(meta.sizeLabel)}</span>
    </div>
  `;
  return chip;
}

async function fetchPreviewDataUrl(file) {
  const key = previewCacheKey(file);
  if (key && filePreviewCache.has(key)) {
    return filePreviewCache.get(key);
  }

  const fd = new FormData();
  fd.append("file", file);
  const previewUrl = isGuestMode ? "/api/guest/preview" : "/api/plano/preview";
  const res = isGuestMode
    ? await guestFetch(previewUrl, { method: "POST", body: fd })
    : await PlanoAuth.apiFetch(previewUrl, { method: "POST", body: fd });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(
      typeof data.detail === "string" ? data.detail : "Vista previa no disponible"
    );
  }
  const mime = data.mime || "image/png";
  const result = {
    url: `data:${mime};base64,${data.image_base64}`,
    note: data.preview_note || null,
  };
  if (key) filePreviewCache.set(key, result);
  return result;
}

async function resolveAttachmentPreview(file) {
  const ext = getFileExt(file.name);
  const isImage =
    file.type?.startsWith("image/") ||
    [".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"].includes(ext);

  if (isImage) {
    return URL.createObjectURL(file);
  }
  if (needsServerPreview(file)) {
    try {
      const { url } = await fetchPreviewDataUrl(file);
      return url;
    } catch {
      return null;
    }
  }
  return null;
}

function resetAttachFallbackIcon() {
  const fallback = $("#attachFallback");
  if (!fallback) return;
  fallback.innerHTML =
    '<span class="material-symbols-outlined text-[18px]">image</span>';
}

function setAttachPreviewLoading(on, message) {
  attachPreviewLoading = on;
  const row = $("#attachmentsRow");
  if (row) row.classList.toggle("is-converting", on);
  if (on && message) showToast(message, 7000);
  updateSendButton();
}

async function loadServerPreview(file) {
  const img = $("#previewImg");
  const fallback = $("#attachFallback");
  if (!img) return;

  const reqId = ++previewRequestId;
  setAttachPreviewLoading(true, "Generando vista previa…");
  try {
    const { url } = await fetchPreviewDataUrl(file);
    if (attachedFile !== file || reqId !== previewRequestId) return;
    img.onload = () => {
      img.dataset.hidden = "false";
      if (fallback) fallback.hidden = true;
    };
    img.onerror = () => {
      img.dataset.hidden = "true";
      img.removeAttribute("src");
      if (fallback) fallback.hidden = false;
    };
    img.src = url;
  } catch (err) {
    if (attachedFile === file && reqId === previewRequestId) {
      showToast(err.message || "No se pudo previsualizar el archivo");
    }
  } finally {
    if (attachedFile === file && reqId === previewRequestId) {
      setAttachPreviewLoading(false);
    }
  }
}

function setAttachment(file) {
  previewRequestId += 1;
  attachedFile = file;
  const row = $("#attachmentsRow");
  const img = $("#previewImg");
  const fallback = $("#attachFallback");

  clearPreviewUrl();
  resetAttachFallbackIcon();

  if (!file) {
    row.hidden = true;
    img.removeAttribute("src");
    img.dataset.hidden = "true";
    if (fallback) fallback.hidden = false;
    updateSendButton();
    return;
  }

  row.hidden = false;
  const ext = getFileExt(file.name);
  const extLabel = ext.replace(".", "").toUpperCase() || "ARCHIVO";
  $("#attachName").textContent = file.name || "plano";
  $("#attachType").textContent = `${extLabel} · ${formatFileSize(file.size)}`;

  const isImage =
    file.type?.startsWith("image/") ||
    [".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"].includes(ext);

  if (needsServerPreview(file)) {
    if (fallback) {
      fallback.innerHTML = isPdfFile(file)
        ? '<span class="material-symbols-outlined text-[18px]">picture_as_pdf</span>'
        : '<span class="material-symbols-outlined text-[18px]">architecture</span>';
      fallback.hidden = false;
    }
    img.dataset.hidden = "true";
    img.removeAttribute("src");
    loadServerPreview(file);
  } else if (isImage) {
    previewObjectUrl = URL.createObjectURL(file);
    img.onload = () => {
      img.dataset.hidden = "false";
      if (fallback) fallback.hidden = true;
    };
    img.onerror = () => {
      img.dataset.hidden = "true";
      img.removeAttribute("src");
      if (fallback) fallback.hidden = false;
    };
    img.src = previewObjectUrl;
  } else {
    img.dataset.hidden = "true";
    img.removeAttribute("src");
    if (fallback) fallback.hidden = false;
    loadServerPreview(file);
  }

  updateSendButton();
}

function resizeMessageInput() {
  const ta = $("#messageInput");
  if (!ta) return;
  ta.style.height = "auto";
  const next = ta.value.trim() ? Math.min(ta.scrollHeight, 128) : 40;
  ta.style.height = `${next}px`;
}

function updateSendButton() {
  const input = $("#messageInput");
  const btn = $("#btnSend");
  if (!input || !btn) return;
  const hasText = input.value.trim().length > 0;
  btn.disabled = isLoading || attachPreviewLoading || (!attachedFile && !hasText);
}

function appendSourcesToBody(body, msg) {
  const sources = [...(msg.localSources || []), ...(msg.webSources || [])];
  if (!sources.length) return;

  const sec = document.createElement("div");
  sec.className = "msg-sources";
  const title = document.createElement("p");
  title.className = "msg-sources-title";
  title.textContent =
    msg.webSources?.length && msg.localSources?.length
      ? "Fuentes (manuales y web)"
      : msg.webSources?.length
        ? "Fuentes web"
        : "Tus manuales";
  sec.appendChild(title);

  sources.slice(0, 6).forEach((s) => {
    const row = document.createElement("div");
    row.className = "msg-source-row";
    if (s.url) {
      row.innerHTML = `<a href="${escapeHtml(s.url)}" target="_blank" rel="noopener">${escapeHtml(s.title || s.doc_title || "Enlace")}</a>`;
      const sn = document.createElement("span");
      sn.textContent = (s.snippet || "").slice(0, 180);
      row.appendChild(sn);
    } else {
      row.innerHTML = `<strong>${escapeHtml(s.doc_title || "Manual")}</strong> (pág. ${s.page})`;
      const sn = document.createElement("span");
      sn.textContent = s.snippet || "";
      row.appendChild(sn);
    }
    sec.appendChild(row);
  });
  body.appendChild(sec);
}

async function askConstructionQuestion(text) {
  if (!text) return;
  if (isGuestMode && guestTrial?.asks_remaining <= 0) {
    showTrialEndedModal();
    return;
  }
  try {
    await ensureChat();
    const userMsg = { role: "user", text };
    const c = getCurrentChat();
    c.messages.push(userMsg);
    $("#welcome").hidden = true;
    $("#messages").hidden = false;
    appendMessageDOM(userMsg);

    isLoading = true;
    setComposerDisabled(true);
    showTyping();

    const formData = new FormData();
    formData.append("message", text);
    if (!isGuestMode && currentChatId) formData.append("chat_id", currentChatId);

    const askUrl = isGuestMode ? "/api/guest/ask" : "/api/ask";
    const res = isGuestMode
      ? await guestFetch(askUrl, { method: "POST", body: formData })
      : await PlanoAuth.apiFetch(askUrl, { method: "POST", body: formData });
    const data = await res.json();
    if (!res.ok) {
      if (isTrialExhaustedResponse(data, res.status)) {
        await loadGuestTrialStatus();
        showTrialEndedModal();
        return;
      }
      throw new Error(parseApiDetail(data, "No pude responder la pregunta"));
    }

    if (data.guest_trial) {
      guestTrial = data.guest_trial;
      updateGuestTrialUI();
    }
    if (data.chat_id) currentChatId = data.chat_id;

    hideTyping();
    const assistantMsg = {
      role: "assistant",
      text: data.text || "Sin respuesta.",
      localSources: data.local_sources || [],
      webSources: (data.web_sources || []).map((w) => ({
        title: w.title,
        url: w.url,
        snippet: w.snippet,
      })),
      municipality: data.municipality,
      assistantMode: data.assistant_mode || null,
    };
    c.messages.push(assistantMsg);
    if (c.title === "Nuevo chat") c.title = text.slice(0, 80);
    c.updatedAt = Date.now();
    appendMessageDOM(assistantMsg);
    saveChats();
    renderChatList();
  } catch (err) {
    hideTyping();
    showToast(err.message || "Error al consultar");
    const errMsg = { role: "assistant", text: `No pude responder: ${err.message}` };
    getCurrentChat()?.messages.push(errMsg);
    appendMessageDOM(errMsg);
    saveChats();
  } finally {
    isLoading = false;
    setComposerDisabled(false);
    const input = $("#messageInput");
    if (input) {
      input.value = "";
      resizeMessageInput();
    }
    updateSendButton();
  }
}

function detectToolFromPrompt(prompt) {
  const p = (prompt || "").toLowerCase();
  if (/ventana|iluminaci[oó]n\s+natural|vanos?\s+exterior/.test(p)) return "measures";
  if (/puerta|door|accesibilidad|giro|acceso/.test(p)) return "doors";
  if (/habitaci[oó]n|recinto|superficie|cota|medida|dimensi[oó]n/.test(p)) return "measures";
  if (/error|estructural|normativa|incidencia|integral/.test(p)) return "errors";
  return "default";
}

function runChipAction(prompt) {
  if (isLoading) return;
  setToolMode(detectToolFromPrompt(prompt));
  const input = $("#messageInput");
  if (input) {
    input.value = prompt;
    resizeMessageInput();
    updateSendButton();
  }
  if (!attachedFile) {
    pendingPrompt = prompt;
    openAttachPicker();
    return;
  }
  sendMessage(prompt);
}

function buildAssistantMessage(data) {
  if (data.text) {
    const detCount = data.counts?.detections ?? data.stats?.detections ?? 0;
    const errors = data.counts?.errors ?? data.stats?.errors ?? 0;
    const warnings = data.counts?.warnings ?? data.stats?.warnings ?? 0;
    return {
      role: "assistant",
      text: data.text,
      steps: data.steps || null,
      imageUrl: data.image_base64
        ? `data:image/jpeg;base64,${data.image_base64}`
        : null,
      stats: detCount > 0 ? { detections: detCount, errors, warnings } : data.stats || null,
      issuesSummary: data.issues_summary || [],
      detectionsSummary: data.detections_summary || [],
      scaleHint: data.scale_hint || null,
      autoCalibration: data.auto_calibration || null,
      constructionCoverage: data.construction_coverage || null,
      knowledgeReferences: data.knowledge_references || null,
      verdict: data.verdict || null,
      analysisIntent: data.analysis_intent || null,
      customFindings: data.custom_findings || null,
      measuresReport: data.measures_report || null,
      analysisId: data.analysis_id || null,
      conversionNote: data.conversion_note || null,
      detectionsList: data.detections || data.detections_list || [],
      correctionsCount: data.corrections_count || 0,
      assistantMode: data.assistant_mode || null,
    };
  }

  const errors = data.counts?.errors ?? 0;
  const warnings = data.counts?.warnings ?? 0;
  const detCount = data.counts?.detections ?? 0;
  const intentTitle = data.analysis_intent?.title || "Revisión integral";
  const conversational = data.analysis_intent?.conversational;
  const listMeasures = data.analysis_intent?.list_measures;
  const measuresReport = data.measures_report;
  const verdict = data.verdict || {};

  let text;
  if (listMeasures && measuresReport?.text) {
    text = measuresReport.text;
    if (data.auto_calibration?.summary) {
      text = `${data.auto_calibration.summary}\n\n${text}`;
    }
    if (data.conversion_note) {
      text = `${data.conversion_note}\n\n${text}`;
    }
  } else if (conversational && verdict.headline) {
    text = verdict.headline;
    if (verdict.detail) text += `\n${verdict.detail}`;
    (verdict.suggestions || []).forEach((tip) => {
      text += `\n→ ${tip}`;
    });
  } else {
    text = `${intentTitle}\n${data.status || ""}`;
  }
  (data.custom_findings || []).forEach((cf) => {
    if (cf.severity === "ok") text += `\n✓ ${cf.message}`;
    else if (cf.message) text += `\n• ${cf.message}`;
  });
  if (data.auto_calibration?.summary) {
    text = `${data.auto_calibration.summary}\n${text}`;
  }
  if (!listMeasures && data.knowledge_references?.length) {
    text += "\n\nReferencias de tus manuales:";
    data.knowledge_references.slice(0, 3).forEach((r) => {
      text += `\n• ${r.doc_title} (pág. ${r.page}): ${(r.snippet || "").slice(0, 180)}`;
    });
  }
  if (data.conversion_note) {
    text = `${data.conversion_note}\n${text}`;
  }
  let steps = null;
  if (conversational && verdict.headline && detCount > 0) {
    /* veredicto ya en text */
  } else if (detCount === 0) {
    if (data.is_demo_model) {
      text =
        "No detecté puertas, ventanas ni muros en este plano.\n" +
        "El modelo demo solo aprendió dibujos sintéticos; en planos reales como el tuyo no sirve.\n" +
        "Entrena con CubiCasa5K para planos reales:";
      steps = [
        "python scripts/download_dataset.py --force",
        "python scripts/cubicasa_to_yolo.py --input data/raw/dataset --max-samples 200",
        "python scripts/train.py --epochs 50 --device cpu",
      ];
    } else {
      text =
        "No detecté elementos. Verifica la ruta a best.pt o desactiva calibración automática en Ajustes.";
    }
  } else if (!conversational) {
    if (errors === 0 && warnings === 0) {
      const hasOk = (data.custom_findings || []).some((c) => c.severity === "ok");
      text = `En «${intentTitle}» no hay incidencias normativas pendientes.${hasOk ? " Ver uniformidad arriba." : ""}`;
    } else {
      const groups = data.issues_summary?.length ?? 0;
      const juris = data.jurisdiction ? ` — ${data.jurisdiction}` : "";
      text =
        groups > 0
          ? `«${intentTitle}»${juris}: ${errors} error(es) y ${warnings} aviso(s) (${groups} tipo(s)).`
          : `«${intentTitle}»${juris}: ${errors} error(es) y ${warnings} aviso(s).`;
    }
  }

  return {
    role: "assistant",
    text,
    steps,
    imageUrl: `data:image/jpeg;base64,${data.image_base64}`,
    stats: detCount > 0 ? {
      detections: detCount,
      errors,
      warnings,
    } : null,
    issuesSummary: data.issues_summary || [],
    detectionsSummary: data.detections_summary || [],
    scaleHint: data.scale_hint || null,
    autoCalibration: data.auto_calibration || null,
    constructionCoverage: data.construction_coverage || null,
    knowledgeReferences: data.knowledge_references || null,
    verdict: data.verdict || null,
    analysisIntent: data.analysis_intent || null,
    customFindings: data.custom_findings || null,
    measuresReport: data.measures_report || null,
    analysisId: data.analysis_id || null,
    conversionNote: data.conversion_note || null,
    detectionsList: data.detections || data.detections_list || [],
    correctionsCount: data.corrections_count || 0,
    assistantMode: data.assistant_mode || null,
  };
}

async function applyDetectionCorrection(analysisId, detectionIndex, action, newClass, rowEl) {
  if (isGuestMode) {
    showToast("Crea cuenta para guardar correcciones y mejorar el modelo.");
    return;
  }
  let chat;
  try {
    chat = await ensureChat();
  } catch (err) {
    showToast(err.message || "Error de chat");
    return;
  }

  if (rowEl) rowEl.classList.add("is-busy");
  isLoading = true;
  setComposerDisabled(true);

  try {
    const q = currentChatId ? `?chat_id=${encodeURIComponent(currentChatId)}` : "";
    const res = await PlanoAuth.apiFetch(`/api/analyses/${analysisId}/corrections${q}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        detection_index: detectionIndex,
        action,
        new_class: newClass,
        note: "",
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(parseApiDetail(data, "No se pudo guardar la corrección"));

    if (data.chat_id) currentChatId = data.chat_id;
    const assistantMsg = buildAssistantMessage(data);
    chat.messages.push(assistantMsg);
    $("#welcome").hidden = true;
    $("#messages").hidden = false;
    appendMessageDOM(assistantMsg);
    chat.updatedAt = Date.now();
    saveChats();
    showToast("Corrección guardada para aprendizaje");
  } catch (err) {
    showToast(err.message || "Error al corregir");
  } finally {
    if (rowEl) rowEl.classList.remove("is-busy");
    isLoading = false;
    setComposerDisabled(false);
    updateSendButton();
  }
}

async function submitCorrectionMessage(msgText, analysisId) {
  if (isGuestMode) {
    showToast("Crea cuenta para guardar correcciones y mejorar el modelo.");
    return;
  }

  let chat;
  try {
    chat = await ensureChat();
  } catch (err) {
    showToast(err.message || "Error de chat");
    return;
  }

  const userMsg = { role: "user", text: msgText };
  chat.messages.push(userMsg);
  $("#welcome").hidden = true;
  $("#messages").hidden = false;
  appendMessageDOM(userMsg);

  isLoading = true;
  setComposerDisabled(true);
  showTyping();

  try {
    const res = await PlanoAuth.apiFetch(
      `/api/analyses/${analysisId}/correct-from-message`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: msgText,
          chat_id: currentChatId || "",
        }),
      },
    );
    const data = await res.json();
    if (!res.ok) throw new Error(parseApiDetail(data, "No entendí la corrección"));

    if (data.chat_id) currentChatId = data.chat_id;
    hideTyping();
    const assistantMsg = buildAssistantMessage(data);
    chat.messages.push(assistantMsg);
    appendMessageDOM(assistantMsg);
    chat.updatedAt = Date.now();
    saveChats();
  } catch (err) {
    hideTyping();
    showToast(err.message || "Error al aplicar corrección");
  } finally {
    isLoading = false;
    setComposerDisabled(false);
    const input = $("#messageInput");
    if (input) {
      input.value = "";
      resizeMessageInput();
    }
    updateSendButton();
  }
}

async function analyzeFollowup(msgText, analysisId) {
  if (isGuestMode) {
    showToast("En modo prueba no hay seguimiento sin volver a subir el plano.");
    return;
  }
  let chat;
  try {
    chat = await ensureChat();
  } catch (err) {
    showToast(err.message || "Error de chat");
    return;
  }

  const userMsg = { role: "user", text: msgText };
  chat.messages.push(userMsg);
  $("#welcome").hidden = true;
  $("#messages").hidden = false;
  appendMessageDOM(userMsg);

  isLoading = true;
  setComposerDisabled(true);
  showTyping();

  const formData = new FormData();
  formData.append("message", msgText);
  formData.append("analysis_id", String(analysisId));
  formData.append("auto_calibrate", settings.autoCalibrate ? "1" : "0");
  if (settings.autoCalibrate) {
    formData.append("ppm", "0");
    formData.append("conf", "0");
  } else {
    formData.append("ppm", String(settings.ppm));
    formData.append("conf", String(settings.conf));
  }
  formData.append("weights", settings.weights);
  if (currentChatId) formData.append("chat_id", currentChatId);

  try {
    const res = await PlanoAuth.apiFetch("/api/analyze/followup", {
      method: "POST",
      body: formData,
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || "No pude reanalizar el plano");

    if (data.chat_id) currentChatId = data.chat_id;
    if (data.analysis_id) chat.lastAnalysisId = data.analysis_id;
    hideTyping();
    rememberAutoCalibration(data);
    const assistantMsg = buildAssistantMessage(data);
    chat.messages.push(assistantMsg);
    appendMessageDOM(assistantMsg);
    chat.updatedAt = Date.now();
    saveChats();
  } catch (err) {
    hideTyping();
    showToast(err.message || "Error al reanalizar");
    const errMsg = { role: "assistant", text: `No pude reanalizar: ${err.message}` };
    chat.messages.push(errMsg);
    appendMessageDOM(errMsg);
  } finally {
    isLoading = false;
    setComposerDisabled(false);
    const input = $("#messageInput");
    if (input) {
      input.value = "";
      resizeMessageInput();
    }
    updateSendButton();
  }
}

async function sendMessage(text) {
  if (isLoading) return;

  const input = $("#messageInput");
  const msgText = (typeof text === "string" ? text : input?.value || "").trim();

  if (!attachedFile) {
    if (msgText) {
      if (isGuestMode && guestTrial?.asks_remaining <= 0) {
        showTrialEndedModal();
        updateSendButton();
        return;
      }
      const chat = getCurrentChat();
      const lastId = findLastAnalysisId(chat);
      if (lastId && looksLikeCorrection(msgText)) {
        if (input) {
          input.value = "";
          resizeMessageInput();
        }
        await submitCorrectionMessage(msgText, lastId);
        updateSendButton();
        return;
      }
      if (wantsPlanMeasures(msgText) && lastId) {
        if (input) {
          input.value = "";
          resizeMessageInput();
        }
        setToolMode("measures");
        await analyzeFollowup(msgText, lastId);
        updateSendButton();
        return;
      }
      if (wantsPlanMeasures(msgText)) {
        showToast("Adjunta el plano o analízalo primero en este chat.");
      }
      await askConstructionQuestion(msgText);
    }
    updateSendButton();
    return;
  }

  isLoading = true;
  setComposerDisabled(true);

  let chat;
  try {
    chat = await ensureChat();
  } catch (err) {
    showToast(err.message || "Error de chat");
    isLoading = false;
    setComposerDisabled(false);
    return;
  }

  const fileToSend = attachedFile;
  const attachmentMeta = buildAttachmentMeta(fileToSend);
  let imageUrl = null;
  const cacheKey = previewCacheKey(fileToSend);
  const cached = cacheKey ? filePreviewCache.get(cacheKey) : null;
  if (cached?.url) {
    imageUrl = cached.url;
  } else {
    try {
      imageUrl = await resolveAttachmentPreview(fileToSend);
    } catch (err) {
      showToast(err.message || "No se pudo preparar el plano");
      isLoading = false;
      setComposerDisabled(false);
      return;
    }
  }

  setAttachment(null);
  $("#fileInput").value = "";

  const userMsg = {
    role: "user",
    text: msgText || "Analiza este plano",
    imageUrl,
    attachment: attachmentMeta,
  };

  const c = getCurrentChat();
  c.messages.push(userMsg);
  if (c.title === "Nuevo chat") {
    c.title = (msgText || "Análisis de plano").slice(0, 36);
  }
  c.updatedAt = Date.now();

  $("#welcome").hidden = true;
  $("#messages").hidden = false;
  appendMessageDOM(userMsg);
  setToolMode(detectToolFromPrompt(msgText));
  saveChats();

  const formData = new FormData();
  formData.append("file", fileToSend);
  formData.append("auto_calibrate", settings.autoCalibrate ? "1" : "0");
  if (settings.autoCalibrate) {
    formData.append("ppm", "0");
    formData.append("conf", "0");
  } else {
    formData.append("ppm", String(settings.ppm));
    formData.append("conf", String(settings.conf));
  }
  formData.append("weights", settings.weights);
  formData.append("message", msgText || "");
  if (currentChatId) formData.append("chat_id", currentChatId);

  if (input) {
    input.value = "";
    resizeMessageInput();
  }
  updateSendButton();
  showTyping();

  if (isGuestMode && guestTrial?.analyses_remaining <= 0) {
    showTrialEndedModal();
    isLoading = false;
    setComposerDisabled(false);
    return;
  }

  try {
    const analyzeUrl = isGuestMode ? "/api/guest/analyze" : "/api/analyze";
    const res = isGuestMode
      ? await guestFetch(analyzeUrl, { method: "POST", body: formData })
      : await PlanoAuth.apiFetch(analyzeUrl, { method: "POST", body: formData });
    const data = await res.json();
    if (!res.ok) {
      if (isTrialExhaustedResponse(data, res.status)) {
        await loadGuestTrialStatus();
        showTrialEndedModal();
        hideTyping();
        isLoading = false;
        setComposerDisabled(false);
        return;
      }
      const err = new Error(parseApiDetail(data, "Error al analizar"));
      err.status = res.status;
      throw err;
    }

    if (data.guest_trial) {
      guestTrial = data.guest_trial;
      updateGuestTrialUI();
    }
    if (data.chat_id) currentChatId = data.chat_id;
    if (data.analysis_id) {
      const c = getCurrentChat();
      if (c) c.lastAnalysisId = data.analysis_id;
    }
    if (data.subscription) {
      localStorage.setItem("plano_ia_subscription", JSON.stringify(data.subscription));
      updateUsageUI(data.subscription);
    }

    hideTyping();
    rememberAutoCalibration(data);
    const assistantMsg = buildAssistantMessage(data);
    const c = getCurrentChat();
    if (c) {
      c.messages.push(assistantMsg);
      if (CHAT_PERSISTENCE_ENABLED && data.chat_id && !chats.find((x) => x.id === data.chat_id)) {
        chats.unshift({
          id: data.chat_id,
          title: (msgText || "Análisis").slice(0, 36),
          messages: c.messages,
          updatedAt: Date.now(),
        });
      }
      c.updatedAt = Date.now();
    }
    appendMessageDOM(assistantMsg);
    if (c) c.messageCount = (c.messageCount || 0) + 2;
    saveChats();
    if (CHAT_PERSISTENCE_ENABLED) {
      await loadAnalysisHistory();
      if (!isGuestMode) showToast("Análisis guardado en tu historial");
    }
  } catch (err) {
    hideTyping();
    let text = `No pude analizar el plano: ${err.message}`;
    if (err.status === 402 || /límite|suscripción/i.test(err.message)) {
      text = `${err.message}\n\nAbre Planes para mejorar tu cuota mensual.`;
      setTimeout(() => openPlans(), 400);
    }
    if (/modelo no encontrado/i.test(err.message)) {
      text = [
        "Todavía no hay modelo entrenado (`best.pt`). Pasos:",
        "",
        "1. Descargar datos: `python scripts/download_dataset.py`",
        "2. Convertir: `python scripts/cubicasa_to_yolo.py --input data/raw/cubicasa5k --max-samples 200`",
        "3. Entrenar: `python scripts/train.py --epochs 50 --device cpu`",
        "4. En Ajustes, confirma la ruta: `runs/detect/plano_elementos/weights/best.pt`",
        "",
        "Cuando termine el entrenamiento, vuelve a enviar el plano.",
      ].join("\n");
    }
    const errMsg = {
      role: "assistant",
      text,
    };
    getCurrentChat().messages.push(errMsg);
    appendMessageDOM(errMsg);
    saveChats();
  } finally {
    isLoading = false;
    pendingPrompt = null;
    setAttachment(null);
    $("#fileInput").value = "";
    setComposerDisabled(false);
    updateSendButton();
  }
}

function setComposerDisabled(disabled) {
  document.querySelectorAll(".chip, #btnAttach, #messageInput, #btnSend").forEach((el) => {
    el.disabled = disabled;
  });
  if (!disabled) updateSendButton();
}

/* Eventos */
$("#btnNewChat")?.addEventListener("click", () => newChat(true));

function closeAttachPicker() {
  const menu = $("#attachPickerMenu");
  const btn = $("#btnAttach");
  if (!menu) return;
  menu.hidden = true;
  menu.classList.remove("is-open");
  if (btn) {
    btn.setAttribute("aria-expanded", "false");
  }
}

function openAttachPicker() {
  const menu = $("#attachPickerMenu");
  const btn = $("#btnAttach");
  if (!menu) return;
  menu.hidden = false;
  menu.classList.add("is-open");
  if (btn) {
    btn.setAttribute("aria-expanded", "true");
  }
}

function openPlanoFileBrowser(accept = FILE_INPUT_ACCEPT) {
  const fileInput = $("#fileInput");
  if (!fileInput) return;
  fileInput.accept = accept || FILE_INPUT_ACCEPT;
  fileInput.value = "";
  fileInput.click();
}

function setupAttachPicker() {
  const wrap = $("#attachPickerWrap");
  const btn = $("#btnAttach");
  const menu = $("#attachPickerMenu");
  const fileInput = $("#fileInput");
  if (!btn || !menu || !fileInput) return;

  // El clip abre el menú para elegir formato; luego el explorador.
  btn.onclick = (e) => {
    e.preventDefault();
    e.stopPropagation();
    if (menu.classList.contains("is-open")) closeAttachPicker();
    else openAttachPicker();
  };

  menu.querySelectorAll("[data-attach-accept]").forEach((item) => {
    item.onclick = (e) => {
      e.preventDefault();
      e.stopPropagation();
      const mode = item.dataset.attachAccept;
      closeAttachPicker();
      openPlanoFileBrowser(mode === "all" ? FILE_INPUT_ACCEPT : mode);
    };
  });

  menu.addEventListener("click", (e) => e.stopPropagation());
  wrap?.addEventListener("click", (e) => e.stopPropagation());
  document.addEventListener("click", () => closeAttachPicker());
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeAttachPicker();
  });
}

setupAttachPicker();

$("#fileInput").onchange = (e) => {
  const f = pickPlanoFile(e.target.files);
  if (!f) {
    showToast("Formato no soportado: PNG, JPG o PDF");
    return;
  }
  handlePlanoFile(f, !!pendingPrompt);
  closeAttachPicker();
};

$("#btnRemoveAttach").onclick = () => {
  setAttachment(null);
  pendingPrompt = null;
  $("#fileInput").value = "";
  updateSendButton();
};

$("#composerForm")?.addEventListener("submit", (e) => {
  e.preventDefault();
  sendMessage();
});

$("#messageInput")?.addEventListener("input", () => {
  resizeMessageInput();
  updateSendButton();
});

$("#messageInput")?.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    $("#composerForm")?.requestSubmit();
  }
});

document.querySelectorAll(".chip").forEach((btn) => {
  btn.onclick = () => runChipAction(btn.dataset.prompt || "Analiza este plano");
});

document.querySelectorAll(".suggestion-card").forEach((card) => {
  card.onclick = () => runChipAction(card.dataset.prompt || "Analiza este plano");
});

$("#searchChats")?.addEventListener("input", renderChatList);

async function loadNormsPanel() {
  const list = $("#normsThresholdsList");
  const title = $("#normsBundleTitle");
  if (!list) return;
  try {
    const res = await fetch("/api/norms");
    const data = await res.json();
    if (title) title.textContent = data.bundle_title || "Chiapas, México";
    list.innerHTML = "";
    const domains = data.construction_domains || [];
    if (domains.length) {
      const head = document.createElement("li");
      head.className = "norms-domain-head";
      head.textContent = "Ámbitos de la construcción (Chiapas):";
      list.appendChild(head);
      domains.forEach((d) => {
        const li = document.createElement("li");
        const tag = d.auto_in_planta ? "automático en planta" : "revisión manual";
        li.textContent = `${d.title} — ${tag}`;
        list.appendChild(li);
      });
      const sep = document.createElement("li");
      sep.className = "norms-domain-head";
      sep.textContent = "Umbrales medibles:";
      list.appendChild(sep);
    }
    (data.thresholds_applied || []).forEach((t) => {
      const li = document.createElement("li");
      li.textContent = `${t.code}: ${t.value} ${t.unit} (${t.source})`;
      list.appendChild(li);
    });
  } catch {
    list.innerHTML = "<li>No se pudo cargar el catálogo normativo.</li>";
  }
}

const openSettings = () => {
  setNavActive("settings");
  $("#weightsPath").value = settings.weights;
  $("#ppmInput").value = settings.ppm;
  $("#confInput").value = settings.conf;
  const autoEl = $("#autoCalibrate");
  if (autoEl) autoEl.checked = settings.autoCalibrate;
  syncCalibrationInputs();
  applyTheme(getTheme());
  loadNormsPanel();
  $("#settingsModal").showModal();
};
$("#btnSettings").onclick = (e) => { e.preventDefault(); openSettings(); };
$("#btnWorkspace")?.addEventListener("click", (e) => {
  e.preventDefault();
  goToWorkspace();
});
$("#btnHomeProjects")?.addEventListener("click", (e) => {
  e.preventDefault();
  if (window.HomeProjectsUI?.open) {
    window.HomeProjectsUI.open();
  } else {
    window.location.href = "/legacy-app?home-projects=1";
  }
});
$("#btnAdmin")?.addEventListener("click", (e) => {
  e.preventDefault();
  window.location.href = "/app/admin";
});

let supportHelpSelectedId = null;

const SUPPORT_STATUS_LABELS = {
  open: "Abierto",
  pending: "En espera",
  resolved: "Resuelto",
  closed: "Cerrado",
};

async function refreshSupportHelpList() {
  const list = document.getElementById("supportHelpList");
  if (!list || !PlanoAuth.getToken()) return;
  list.innerHTML = "<p class='support-help-empty'>Cargando tus tickets…</p>";
  try {
    const res = await PlanoAuth.apiFetch("/api/support/tickets?limit=20");
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(PlanoAuth.formatApiError(data, "No se pudieron cargar tickets"));
    const items = data.items || [];
    if (!items.length) {
      list.innerHTML = "<p class='support-help-empty'>Aún no tienes tickets.</p>";
      return;
    }
    list.innerHTML = items
      .map(
        (t) => `<button type="button" class="support-help-item${supportHelpSelectedId === t.id ? " is-selected" : ""}" data-support-ticket="${t.id}">
          <strong>${escapeHtml(t.subject)}</strong>
          <span>${SUPPORT_STATUS_LABELS[t.status] || t.status}</span>
        </button>`
      )
      .join("");
    list.querySelectorAll("[data-support-ticket]").forEach((btn) => {
      btn.addEventListener("click", () => {
        supportHelpSelectedId = Number(btn.getAttribute("data-support-ticket"));
        openSupportHelpTicket(supportHelpSelectedId);
        refreshSupportHelpList();
      });
    });
  } catch (err) {
    list.innerHTML = `<p class="support-help-empty">${escapeHtml(err.message || "Error")}</p>`;
  }
}

async function openSupportHelpTicket(ticketId) {
  const thread = document.getElementById("supportHelpThread");
  if (!thread) return;
  thread.innerHTML = "<p class='support-help-empty'>Cargando conversación…</p>";
  try {
    const res = await PlanoAuth.apiFetch(`/api/support/tickets/${ticketId}`);
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(PlanoAuth.formatApiError(data, "No se pudo abrir el ticket"));
    const msgs = data.messages || [];
    const closed = data.status === "closed";
    thread.innerHTML = `
      <header class="support-help-thread-head">
        <strong>${escapeHtml(data.subject)}</strong>
        <span>${SUPPORT_STATUS_LABELS[data.status] || data.status}</span>
      </header>
      <div class="support-help-msgs">
        ${
          msgs
            .map(
              (m) => `<article class="support-help-msg${m.is_staff ? " is-staff" : ""}">
                <header>
                  <strong>${escapeHtml(m.author_name || (m.is_staff ? "Soporte" : "Tú"))}</strong>
                </header>
                <p>${escapeHtml(m.body)}</p>
              </article>`
            )
            .join("") || "<p class='support-help-empty'>Sin mensajes</p>"
        }
      </div>
      ${
        closed
          ? "<p class='support-help-empty'>Este ticket está cerrado.</p>"
          : `<form class="support-help-reply" id="supportHelpReplyForm">
              <textarea id="supportHelpReplyBody" rows="3" required placeholder="Escribe un seguimiento…"></textarea>
              <button type="submit" class="btn-primary">Responder</button>
            </form>`
      }`;
    document.getElementById("supportHelpReplyForm")?.addEventListener("submit", async (e) => {
      e.preventDefault();
      const body = document.getElementById("supportHelpReplyBody")?.value || "";
      try {
        const r = await PlanoAuth.apiFetch(`/api/support/tickets/${ticketId}/messages`, {
          method: "POST",
          body: JSON.stringify({ body }),
        });
        const d = await r.json().catch(() => ({}));
        if (!r.ok) throw new Error(PlanoAuth.formatApiError(d, "No se pudo enviar"));
        showToast("Mensaje enviado");
        await openSupportHelpTicket(ticketId);
        await refreshSupportHelpList();
      } catch (err) {
        showToast(err.message || "Error al responder");
      }
    });
  } catch (err) {
    thread.innerHTML = `<p class="support-help-empty">${escapeHtml(err.message || "Error")}</p>`;
  }
}

$("#btnSupportHelp")?.addEventListener("click", (e) => {
  e.preventDefault();
  const modal = document.getElementById("supportHelpModal");
  if (modal?.showModal) modal.showModal();
  else modal?.setAttribute("open", "");
  refreshSupportHelpList();
  if (supportHelpSelectedId) openSupportHelpTicket(supportHelpSelectedId);
});
$("#btnCloseSupportHelp")?.addEventListener("click", () => {
  const modal = document.getElementById("supportHelpModal");
  if (modal?.close) modal.close();
  else modal?.removeAttribute("open");
});
$("#supportHelpForm")?.addEventListener("submit", async (e) => {
  e.preventDefault();
  const subject = document.getElementById("supportHelpSubject")?.value || "";
  const body = document.getElementById("supportHelpBody")?.value || "";
  try {
    const res = await PlanoAuth.apiFetch("/api/support/tickets", {
      method: "POST",
      body: JSON.stringify({ subject, body }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(PlanoAuth.formatApiError(data, "No se pudo crear el ticket"));
    document.getElementById("supportHelpSubject").value = "";
    document.getElementById("supportHelpBody").value = "";
    supportHelpSelectedId = data.id || null;
    showToast("Ticket enviado. Soporte te responderá pronto.");
    await refreshSupportHelpList();
    if (supportHelpSelectedId) await openSupportHelpTicket(supportHelpSelectedId);
  } catch (err) {
    showToast(err.message || "Error al enviar");
  }
});

$("#btnCloseSettings").onclick = () => $("#settingsModal").close();
$("#settingsForm").onsubmit = (e) => {
  e.preventDefault();
  saveSettings();
  $("#settingsModal").close();
};
$("#autoCalibrate")?.addEventListener("change", syncCalibrationInputs);

function isMobileLayout() {
  return window.matchMedia("(max-width: 767px)").matches;
}

function isSidebarCollapsed() {
  return document.body.classList.contains("sidebar-collapsed");
}

function updateSidebarToggleUI() {
  const collapsed = isSidebarCollapsed();
  const icon = document.getElementById("sidebarToggleIcon");
  const btn = $("#btnMenu");
  const floatBtn = $("#btnMenuFloat");
  if (icon) icon.textContent = collapsed ? "menu" : "chevron_left";
  if (btn) {
    btn.setAttribute("aria-label", collapsed ? "Mostrar panel" : "Minimizar panel");
    btn.title = collapsed ? "Mostrar panel lateral" : "Minimizar panel lateral";
  }
  if (floatBtn) {
    const showFloat = collapsed;
    floatBtn.classList.toggle("hidden", !showFloat);
    floatBtn.classList.toggle("is-visible", showFloat);
  }
}

function updateSidebarBackdrop() {
  const backdrop = $("#sidebarBackdrop");
  if (!backdrop) return;
  const show = isMobileLayout() && !isSidebarCollapsed();
  backdrop.classList.toggle("hidden", !show);
  backdrop.classList.toggle("is-visible", show);
  backdrop.setAttribute("aria-hidden", show ? "false" : "true");
}

function setSidebarCollapsed(collapsed, save = true) {
  document.body.classList.toggle("sidebar-collapsed", collapsed);
  updateSidebarToggleUI();
  updateSidebarBackdrop();
  if (save) localStorage.setItem(SIDEBAR_KEY, collapsed ? "1" : "0");
}

function toggleSidebar() {
  setSidebarCollapsed(!isSidebarCollapsed());
}

function initSidebar() {
  const saved = localStorage.getItem(SIDEBAR_KEY);
  const collapsed = saved === "1";
  setSidebarCollapsed(collapsed, false);
}

$("#btnMenu")?.addEventListener("click", () => toggleSidebar());
$("#btnMenuFloat")?.addEventListener("click", () => toggleSidebar());

$("#sidebarBackdrop")?.addEventListener("click", () => setSidebarCollapsed(true));

window.addEventListener("resize", () => {
  updateSidebarBackdrop();
});

const btnCancel = document.getElementById("btnCancelSettings");
if (btnCancel) btnCancel.onclick = () => $("#settingsModal").close();

applyTheme(getTheme());
initSidebar();

document.getElementById("themeDark")?.addEventListener("click", () => applyTheme("dark"));
document.getElementById("themeLight")?.addEventListener("click", () => applyTheme("light"));

function isPlanUnlimited(sub) {
  if (!sub) return false;
  if (sub.is_unlimited) return true;
  return (sub.plan?.analyses_limit_monthly ?? 0) >= 9999;
}

function formatPlanLimitText(limit) {
  if (limit >= 9999) return "Análisis ilimitados";
  return `${limit} análisis/mes`;
}

function formatPlanStorageText(plan) {
  const gb = Number(plan?.storage_gb ?? plan?.features?.storage_gb ?? 0);
  if (!Number.isFinite(gb) || gb <= 0) return null;
  return `${gb} GB de documentación`;
}

function planFeatureLines(plan, { compact = false } = {}) {
  const f = plan.features || {};
  const custom = Array.isArray(f.benefits)
    ? f.benefits.map((line) => String(line).trim()).filter(Boolean)
    : [];
  if (custom.length) {
    return compact ? custom.slice(0, 5) : custom;
  }

  const lines = [formatPlanLimitText(plan.analyses_limit_monthly)];
  const storage = formatPlanStorageText(plan);
  if (storage) lines.push(storage);
  lines.push(plan.allow_real_model ? "Modelo real" : "Modelo demo");
  lines.push(`Hasta ${plan.max_file_mb} MB por archivo`);
  if (!compact) {
    if (f.export) lines.push("Exportar reportes");
    if (f.mobile_app) lines.push("App móvil ARCHITECT");
    if (f.sla) lines.push("SLA dedicado");
    if (f.support) lines.push(`Soporte ${f.support}`);
  } else if (f.support) {
    lines.push(`Soporte ${f.support}`);
  } else if (f.mobile_app) {
    lines.push("App móvil");
  }
  return lines;
}

function updateUsageUI(sub) {
  if (!sub) return;
  const box = document.getElementById("usageBar");
  const plan = sub.plan || {};
  const usage = sub.usage || {};
  const limit = plan.analyses_limit_monthly || 0;
  const used = usage.analyses_used || 0;
  const remaining = usage.analyses_remaining;
  const unlimited = isPlanUnlimited(sub);
  const planLabel = document.getElementById("planLabel");
  const usageLabel = document.getElementById("usageLabel");
  if (planLabel) planLabel.textContent = plan.name || plan.slug || "Plan";
  if (usageLabel) {
    usageLabel.textContent = unlimited ? `${used} análisis` : `${used} / ${limit}`;
  }
  const pct = unlimited ? 8 : Math.min(100, Math.round((used / Math.max(limit, 1)) * 100));
  const fill = document.getElementById("usageFill");
  if (fill) fill.style.width = `${pct}%`;
  const limitReached = !unlimited && !!usage.limit_reached;
  if (box) {
    box.classList.toggle("usage-box--limit", limitReached);
    box.classList.toggle("usage-box--unlimited", unlimited);
  }
  const plansText = document.getElementById("plansUsageText");
  if (plansText) {
    plansText.innerHTML = unlimited
      ? `<strong>${escapeHtml(plan.name || "Plan")}</strong><span>Uso ilimitado · ${used} análisis este mes</span>`
      : `<strong>${escapeHtml(plan.name || "Plan")}</strong><span>${used} / ${limit} análisis` +
        (remaining != null ? ` · ${remaining} restantes` : "") +
        `</span>`;
  }
  const badge = document.getElementById("planUsageBadge");
  const badgeText = document.getElementById("planUsageBadgeText");
  if (badge && badgeText) {
    const showBadge = !!PlanoAuth.getToken() && !!PlanoAuth.getUser() && !isGuestMode;
    badge.classList.toggle("hidden", !showBadge);
    badgeText.textContent = unlimited
      ? `${plan.name || "Plan"} · ${used} análisis`
      : `${plan.name || "Plan"} · ${used}/${limit}`;
    badge.classList.toggle("plan-usage-badge--limit", limitReached);
  }
}

function applyAvatarElement(el, user, initials) {
  if (!el) return;
  const url = user?.avatar_url;
  if (url) {
    el.classList.add("has-photo");
    el.style.setProperty("background-image", `url("${url}")`, "important");
    el.textContent = "";
    el.setAttribute("aria-label", "Foto de perfil");
  } else {
    el.classList.remove("has-photo");
    el.style.removeProperty("background-image");
    el.textContent = initials;
    el.removeAttribute("aria-label");
  }
}

function updateUserUI() {
  const user = PlanoAuth.getUser();
  const sub = PlanoAuth.getSubscription();
  if (!user) return;
  const initials = (user.full_name || user.email || "U")
    .split(" ")
    .map((w) => w[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
  applyAvatarElement(document.getElementById("userAvatar"), user, initials);
  const nameEl = document.getElementById("userName");
  if (nameEl) nameEl.textContent = user.full_name || user.email;
  const roleEl = document.getElementById("userRole");
  if (roleEl) {
    roleEl.textContent =
      user.role === "admin"
        ? "Administrador"
        : user.role === "support"
          ? "Soporte"
          : sub?.plan?.name || "Usuario";
  }
  const adminBtn = document.getElementById("btnAdmin");
  if (adminBtn) {
    const showAdmin = user.role === "admin" || user.role === "support";
    adminBtn.classList.toggle("hidden", !showAdmin);
    adminBtn.hidden = !showAdmin;
    const label = document.getElementById("btnAdminLabel");
    if (label) label.textContent = user.role === "support" ? "Bandeja soporte" : "Administración";
  }
  const helpBtn = document.getElementById("btnSupportHelp");
  if (helpBtn) {
    const showHelp = user.role !== "support";
    helpBtn.classList.toggle("hidden", !showHelp);
    helpBtn.hidden = !showHelp;
  }
  if (sub) updateUsageUI(sub);
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
  if (data.user) {
    localStorage.setItem("plano_ia_user", JSON.stringify(data.user));
  } else {
    await PlanoAuth.refreshMe();
  }
  updateUserUI();
  return data;
}

async function removeProfileAvatar() {
  const res = await PlanoAuth.apiFetch("/api/auth/me/avatar", { method: "DELETE" });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(PlanoAuth.formatApiError(data, "No se pudo quitar la foto"));
  if (data.user) {
    localStorage.setItem("plano_ia_user", JSON.stringify(data.user));
  } else {
    await PlanoAuth.refreshMe();
  }
  updateUserUI();
  return data;
}

async function loadPlansModal() {
  const grid = document.getElementById("plansGrid");
  if (!grid) return;
  grid.innerHTML = "";
  const res = await fetch("/api/billing/plans");
  const plans = await res.json();
  const current = PlanoAuth.getSubscription()?.plan?.slug;
  plans.forEach((p) => {
    const card = document.createElement("article");
    const isCurrent = p.slug === current;
    const isRecommended = !!(p.features?.recommended || p.slug === "pro");
    card.className =
      "plan-card" +
      (isCurrent ? " is-current" : "") +
      (isRecommended && !isCurrent ? " is-recommended" : "");
    const price = p.price_monthly_cents
      ? `$${(p.price_monthly_cents / 100).toFixed(0)}`
      : "Gratis";
    const priceSuffix = p.price_monthly_cents ? "<small>/mes</small>" : "";
    const features = planFeatureLines(p, { compact: true })
      .map((line) => `<li>${escapeHtml(line)}</li>`)
      .join("");
    const ideal = p.features?.ideal_for
      ? `<p class="plan-card-ideal">Ideal para: ${escapeHtml(p.features.ideal_for)}</p>`
      : "";
    const badges = [
      isCurrent ? '<span class="plan-card-badge">Actual</span>' : "",
      isRecommended && !isCurrent
        ? '<span class="plan-card-badge plan-card-badge--recommended">Recomendado</span>'
        : "",
    ]
      .filter(Boolean)
      .join("");
    const cta = isCurrent
      ? "Plan actual"
      : p.price_monthly_cents
        ? "Elegir plan"
        : p.slug === "free"
          ? "Bajar a gratis"
          : "Seleccionar";
    card.innerHTML = `
      <div class="plan-card-top">
        <div class="plan-card-title-wrap">
          <h3>${escapeHtml(p.name)}</h3>
          ${badges}
        </div>
        <p class="plan-card-price">${price}${priceSuffix}</p>
      </div>
      <p class="plan-card-desc">${escapeHtml(p.description || "")}</p>
      ${ideal}
      <ul class="plan-card-features">${features}</ul>
      <button type="button" class="plan-select-btn${isCurrent ? " is-current" : ""}" data-slug="${p.slug}" ${isCurrent ? "disabled" : ""}>
        ${cta}
      </button>`;
    grid.appendChild(card);
  });
  grid.querySelectorAll(".plan-select-btn").forEach((btn) => {
    btn.onclick = async () => {
      const slug = btn.dataset.slug;
      btn.disabled = true;
      try {
        if (!window.ArchitectBilling) throw new Error("Billing no disponible");
        const token = PlanoAuth.getToken();
        const result = await window.ArchitectBilling.requestPlanChange(slug, {
          token,
          returnUrl: "/legacy-app",
          apiFetch: (url, opts) => PlanoAuth.apiFetch(url, opts),
        });
        if (result?.status === "redirecting") return;
        const data = result.subscription || result;
        if (data?.plan) {
          localStorage.setItem("plano_ia_subscription", JSON.stringify(data));
          updateUsageUI(data);
          $("#plansModal").close();
          await loadPlansModal();
          showToast(data.plan?.name ? `Plan ${data.plan.name} activado` : "Plan actualizado");
        }
      } catch (err) {
        PlanoDialog.alert(err.message || "No se pudo cambiar el plan", {
          title: "Error al cambiar plan",
          variant: "danger",
        });
      } finally {
        btn.disabled = false;
      }
    };
  });

  const note = document.getElementById("plansDemoNote");
  const portalBtn = document.getElementById("btnStripePortal");
  try {
    const config = await window.ArchitectBilling?.fetchBillingConfig?.();
    const sub = PlanoAuth.getSubscription();
    if (note) {
      note.textContent =
        "Proyecto escolar: pasarela simulada (sin cobro real). Bajar a Gratis es inmediato.";
    }
    if (portalBtn) {
      const showPortal = config?.mode === "stripe" && sub?.has_active_payment;
      portalBtn.classList.toggle("hidden", !showPortal);
      portalBtn.onclick = async () => {
        try {
          await window.ArchitectBilling.openBillingPortal({
            token: PlanoAuth.getToken(),
            returnUrl: "/legacy-app",
            apiFetch: (url, opts) => PlanoAuth.apiFetch(url, opts),
          });
        } catch (err) {
          PlanoDialog.alert(err.message || "No se pudo abrir Stripe", {
            title: "Portal de facturación",
            variant: "danger",
          });
        }
      };
    }
  } catch {
    /* ignore */
  }
}

const openPlans = async () => {
  if (isGuestMode) {
    showTrialEndedModal();
    return;
  }
  setNavActive("plans");
  await loadPlansModal();
  $("#plansModal").showModal();
};
$("#btnPlans")?.addEventListener("click", (e) => { e.preventDefault(); openPlans(); });
$("#btnUsagePlans")?.addEventListener("click", (e) => { e.preventDefault(); openPlans(); });
$("#btnPlanUsageBadge")?.addEventListener("click", (e) => { e.preventDefault(); openPlans(); });
$("#planBadge")?.addEventListener("click", (e) => { e.preventDefault(); openPlans(); });
const btnClosePlans = $("#btnClosePlans");
if (btnClosePlans) btnClosePlans.onclick = () => $("#plansModal").close();
const btnLogout = $("#btnLogout");
if (btnLogout) btnLogout.onclick = () => PlanoAuth.logout();

async function checkBackendHealth() {
  try {
    const res = await fetch("/api/health");
    const h = await res.json();
    if (!h.ok) {
      const banner = $("#setupBanner");
      if (banner) {
        banner.hidden = false;
        banner.innerHTML =
          "<strong>Base de datos no disponible.</strong> " +
          "<span>Enciende MySQL, configura <code>.env</code> y ejecuta " +
          "<code>python scripts/init_db.py</code></span>";
      }
      return false;
    }
    return true;
  } catch {
    return false;
  }
}

async function loadAnalysisHistory() {
  if (!CHAT_PERSISTENCE_ENABLED || isGuestMode) return;
  const wrap = $("#analysisHistoryWrap");
  const list = $("#analysisList");
  if (!wrap || !list) return;
  try {
    const res = await PlanoAuth.apiFetch("/api/analyses?limit=8");
    const rows = await res.json();
    if (!rows.length) {
      wrap.classList.add("hidden");
      return;
    }
    wrap.classList.remove("hidden");
    list.innerHTML = "";
    rows.forEach((a) => {
      const li = document.createElement("li");
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "analysis-item-btn";
      const errs = a.counts?.errors ?? 0;
      const dets = a.counts?.detections ?? 0;
      btn.innerHTML = `<span class="block truncate font-medium">${escapeHtml(a.filename)}</span><span class="opacity-50">${dets} det. · ${errs} err.</span>`;
      btn.onclick = async () => {
        if (!a.chat_id) {
          showToast("Este análisis ya no tiene chat (fue eliminado)");
          return;
        }
        try {
          const res = await PlanoAuth.apiFetch(
            `/api/chats/${encodeURIComponent(a.chat_id)}`,
          );
          if (!res.ok) {
            showToast("Ese chat ya no existe; actualizando historial…");
            await loadChats();
            await loadAnalysisHistory();
            return;
          }
          const data = await res.json();
          let chat = chats.find((c) => c.id === a.chat_id);
          if (!chat) {
            chat = {
              id: a.chat_id,
              title: data.chat?.title || a.filename,
              messages: [],
              messageCount: data.chat?.message_count || 0,
              updatedAt: Date.now(),
            };
            chats.unshift(chat);
            saveChats();
          }
          await showChat(chat);
          if (isMobileLayout()) setSidebarCollapsed(true);
        } catch (err) {
          showToast(err.message || "No se pudo abrir el chat");
        }
      };
      li.appendChild(btn);
      list.appendChild(li);
    });
  } catch {
    wrap?.classList.add("hidden");
  }
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

const RECEIPT_ALERT_KEY = "pending_receipt_alert";

function showReceiptEmailAlert(receipt) {
  if (!receipt?.id) return;
  const el = $("#receiptEmailAlert");
  if (!el) return;
  $("#receiptEmailAlertTitle").textContent = "No se pudo enviar el comprobante por correo";
  $("#receiptEmailAlertMsg").textContent = `Folio ${receipt.receipt_number}. Descárgalo aquí o revísalo en Mi cuenta.`;
  el.classList.remove("hidden");
  el.dataset.receiptId = String(receipt.id);
  el.dataset.receiptNumber = receipt.receipt_number || "";
  const dl = $("#receiptEmailAlertDownload");
  if (dl) {
    dl.onclick = async () => {
      try {
        await downloadBillingReceipt(receipt.id, receipt.receipt_number);
      } catch (err) {
        showToast(err.message || "Error al descargar");
      }
    };
  }
  const accountBtn = $("#receiptEmailAlertAccount");
  if (accountBtn) accountBtn.onclick = () => openAccountModal();
  const dismissBtn = $("#receiptEmailAlertDismiss");
  if (dismissBtn) {
    dismissBtn.onclick = () => {
      el.classList.add("hidden");
      sessionStorage.removeItem(RECEIPT_ALERT_KEY);
    };
  }
}

function consumePendingReceiptAlert() {
  try {
    const raw = sessionStorage.getItem(RECEIPT_ALERT_KEY);
    if (!raw) return;
    const receipt = JSON.parse(raw);
    if (receipt?.email_status === "failed") showReceiptEmailAlert(receipt);
    sessionStorage.removeItem(RECEIPT_ALERT_KEY);
  } catch {
    sessionStorage.removeItem(RECEIPT_ALERT_KEY);
  }
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

function formatReceiptDate(iso) {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString("es-MX", { dateStyle: "medium", timeStyle: "short" });
  } catch {
    return iso;
  }
}

const ACCOUNT_RECEIPTS_PAGE_SIZE = 4;
let accountReceiptsExpanded = false;
let accountReceiptsCache = [];

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
        showToast("ZIP descargado");
      } catch (err) {
        showToast(err.message || "No se pudo exportar");
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
        showToast(err.message || "Error al descargar");
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
        showToast("Comprobante enviado a tu correo");
        await openAccountModal();
      } catch (err) {
        showToast(err.message || "No se pudo reenviar");
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

async function openAccountModal() {
  const user = PlanoAuth.getUser();
  const body = $("#accountBody");
  if (!body || !user) return;

  let sub = PlanoAuth.getSubscription();
  try {
    const res = await PlanoAuth.apiFetch("/api/billing/subscription");
    if (res.ok) {
      const fresh = await res.json();
      localStorage.setItem("plano_ia_subscription", JSON.stringify(fresh));
      sub = fresh;
    }
  } catch {
    /* usa cache local */
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
          <span class="account-meta-value">${user.role === "admin" ? "Administrador" : "Usuario"}</span>
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
    <div class="account-usage-chart-slot">
      <p class="account-loading">Cargando uso mensual…</p>
    </div>
    <div class="account-receipts">
      <p class="account-loading">Cargando comprobantes…</p>
    </div>
  `;
  $("#accountModal").showModal();

  const avatarInput = body.querySelector("#accountAvatarInput");
  const pickBtn = body.querySelector("#btnPickAvatar");
  const removeBtn = body.querySelector("#btnRemoveAvatar");
  pickBtn?.addEventListener("click", () => avatarInput?.click());
  avatarInput?.addEventListener("change", async () => {
    const file = avatarInput.files?.[0];
    avatarInput.value = "";
    if (!file) return;
    try {
      showToast("Subiendo foto…");
      await uploadProfileAvatar(file);
      showToast("Foto de perfil actualizada");
      await openAccountModal();
    } catch (err) {
      showToast(err.message || "No se pudo subir la foto");
    }
  });
  removeBtn?.addEventListener("click", async () => {
    try {
      await removeProfileAvatar();
      showToast("Foto eliminada");
      await openAccountModal();
    } catch (err) {
      showToast(err.message || "No se pudo quitar la foto");
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

function openInfoModal(title, html) {
  $("#infoModalTitle").textContent = title;
  $("#infoModalBody").innerHTML = html;
  $("#infoModal").showModal();
}

function setupFooterLinks() {
  /* Footer eliminado de la UI */
}

function setupDragDrop() {
  const overlay = $("#dropOverlay");
  const dock = $("#composerDock");
  const chatArea = $("#chatArea");
  if (!overlay) return;

  let dragDepth = 0;
  const hasFiles = (e) =>
    [...(e.dataTransfer?.types || [])].some(
      (t) => t === "Files" || t === "application/x-moz-file"
    );

  const show = () => {
    overlay.classList.remove("hidden");
    overlay.classList.add("is-active");
    overlay.setAttribute("aria-hidden", "false");
  };
  const hide = () => {
    dragDepth = 0;
    overlay.classList.remove("is-active");
    overlay.classList.add("hidden");
    overlay.setAttribute("aria-hidden", "true");
  };

  const onDragOver = (e) => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = "copy";
    show();
  };

  const onDragEnter = (e) => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    dragDepth++;
    show();
  };

  const onDrop = (e) => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    e.stopPropagation();
    hide();
    const f = pickPlanoFile(e.dataTransfer?.files);
    if (!f) {
      showToast("Formato no soportado: PNG, JPG o PDF");
      return;
    }
    handlePlanoFile(f, !!pendingPrompt);
  };

  document.addEventListener("dragenter", onDragEnter);
  document.addEventListener("dragover", onDragOver);
  document.addEventListener("dragleave", (e) => {
    if (e.relatedTarget && document.contains(e.relatedTarget)) return;
    dragDepth = Math.max(0, dragDepth - 1);
    if (dragDepth === 0) hide();
  });
  document.addEventListener("drop", onDrop);

  overlay.addEventListener("drop", onDrop);
  dock?.addEventListener("dragover", onDragOver);
  dock?.addEventListener("drop", onDrop);
  chatArea?.addEventListener("dragover", onDragOver);
  chatArea?.addEventListener("drop", onDrop);
}

function setupPasteImages() {
  document.addEventListener("paste", (e) => {
    const items = e.clipboardData?.items;
    if (!items) return;
    for (const item of items) {
      if (item.kind === "file") {
        const file = item.getAsFile();
        if (file && (file.type.startsWith("image/") || isPlanoFile(file))) {
          e.preventDefault();
          handlePlanoFile(file, false);
          return;
        }
      }
    }
  });
}

async function measureLatency() {
  const t0 = performance.now();
  try {
    await fetch("/api/health");
    const ms = Math.round(performance.now() - t0);
    const el = document.getElementById("timestamp");
    if (el) el.textContent = `LATENCY: ${ms}ms`;
  } catch {
    const el = document.getElementById("timestamp");
    if (el) el.textContent = "LATENCY: —";
  }
}

async function refreshAfterPageRestore() {
  const loader = window.PlanoLoader;
  loader?.show("Actualizando…");
  try {
    if (PlanoAuth.getToken()) {
      await PlanoAuth.refreshMe();
      updateUserUI();
      if (CHAT_PERSISTENCE_ENABLED) {
        await loadChats();
        await loadAnalysisHistory();
      }
    } else {
      await loadGuestTrialStatus();
      updateGuestUI();
    }
  } catch (e) {
    console.warn("refreshAfterPageRestore:", e);
  } finally {
    loader?.hide();
  }
}

async function boot() {
  const loader = window.PlanoLoader;
  loader?.show(PlanoAuth.getToken() ? "Preparando tu espacio…" : "Cargando ARCHITECT…");
  const bootGuard = window.setTimeout(() => loader?.hide(), 12000);

  try {
    setupImageViewer();
    setupFooterLinks();
    setupDragDrop();
    setupPasteImages();
    $("#btnAccount")?.addEventListener("click", () => {
      if (isGuestMode) window.location.href = "/login";
      else openAccountModal();
    });
    const btnCloseAccount = $("#btnCloseAccount");
    if (btnCloseAccount) btnCloseAccount.onclick = () => $("#accountModal").close();
    const btnAccountLogout = $("#btnAccountLogout");
    if (btnAccountLogout) btnAccountLogout.onclick = () => PlanoAuth.logout();
    const btnAccountPlans = $("#btnAccountPlans");
    if (btnAccountPlans) {
      btnAccountPlans.onclick = () => {
        $("#accountModal").close();
        openPlans();
      };
    }
    $("#btnCloseTrial")?.addEventListener("click", () => $("#trialModal")?.close());

    const openHomeProjects =
      new URLSearchParams(window.location.search).get("home-projects") === "1" ||
      sessionStorage.getItem("open_home_projects") === "1";

    if (openHomeProjects) {
      sessionStorage.removeItem("open_home_projects");
      const url = new URL(window.location.href);
      if (url.searchParams.get("home-projects") !== "1") {
        url.searchParams.set("home-projects", "1");
        window.history.replaceState({}, "", url.pathname + url.search);
      }
    }

    if (PlanoAuth.getToken()) {
      loader?.show("Sincronizando tu cuenta…");
      await initAuthenticatedApp(openHomeProjects);
    } else {
      loader?.show("Iniciando modo prueba…");
      await initGuestApp(openHomeProjects);
    }

    if (openHomeProjects && PlanoAuth.getToken()) {
      window.HomeProjectsUI?.open();
    }

    if (new URLSearchParams(window.location.search).get("plan_activated") === "1") {
      const sub = PlanoAuth.getSubscription();
      const receiptId = new URLSearchParams(window.location.search).get("receipt_id");
      let msg = sub?.plan?.name ? `Plan ${sub.plan.name} activado` : "Plan activado correctamente";
      if (receiptId) msg += ". Revisa Mi cuenta para tu comprobante.";
      showToast(msg);
      const url = new URL(window.location.href);
      url.searchParams.delete("plan_activated");
      url.searchParams.delete("receipt_id");
      window.history.replaceState({}, "", url.pathname + url.search);
    }
    consumePendingReceiptAlert();
    const bootParams = new URLSearchParams(window.location.search);
    if (bootParams.get("account") === "1" && PlanoAuth.getToken()) {
      const receiptId = bootParams.get("receipt_id");
      await openAccountModal();
      if (receiptId) {
        try {
          await downloadBillingReceipt(receiptId);
          showToast("Comprobante descargado");
        } catch {
          showToast("Abre Mi cuenta para descargar tu comprobante");
        }
      }
      const url = new URL(window.location.href);
      url.searchParams.delete("account");
      url.searchParams.delete("receipt_id");
      window.history.replaceState({}, "", url.pathname + url.search);
    }
    if (new URLSearchParams(window.location.search).get("checkout_canceled") === "1") {
      showToast("Pago cancelado. Puedes intentarlo de nuevo cuando quieras.");
      const url = new URL(window.location.href);
      url.searchParams.delete("checkout_canceled");
      window.history.replaceState({}, "", url.pathname + url.search);
    }
  } finally {
    window.clearTimeout(bootGuard);
    loader?.hide();
  }
}

boot();

window.addEventListener("plano:pageshow-restore", () => {
  if (document.querySelector(".app-shell")) refreshAfterPageRestore();
});

document.querySelectorAll(".glass-card.suggestion-card").forEach((card, i) => {
  card.classList.add("animate-in");
  setTimeout(() => card.classList.add("visible"), 400 + i * 150);
});

