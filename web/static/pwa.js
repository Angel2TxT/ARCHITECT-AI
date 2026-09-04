(function () {
  "use strict";

  const SW_URL = "/sw.js";
  let deferredPrompt = null;

  function isStandalone() {
    return (
      window.matchMedia("(display-mode: standalone)").matches ||
      window.navigator.standalone === true
    );
  }

  function registerServiceWorker() {
    if (!("serviceWorker" in navigator)) return;
    window.addEventListener("load", () => {
      navigator.serviceWorker.register(SW_URL, { scope: "/" }).catch((err) => {
        console.warn("[PWA] No se pudo registrar el service worker:", err);
      });
    });
  }

  function syncInstallButtons() {
    const buttons = document.querySelectorAll("[data-pwa-install]");
    const show = !isStandalone() && !!deferredPrompt;
    buttons.forEach((btn) => {
      btn.hidden = !show;
      btn.setAttribute("aria-hidden", show ? "false" : "true");
    });
  }

  async function promptInstall(event) {
    event?.preventDefault?.();
    if (!deferredPrompt) {
      // Ya instalada o el navegador no ofrece el prompt (Safari/Firefox).
      const tip =
        "En Chrome o Edge: menú ⋮ → «Instalar ARCHITECT» o el icono ⊕ en la barra de direcciones.";
      if (typeof window.showToast === "function") window.showToast(tip);
      else window.alert(tip);
      return;
    }
    deferredPrompt.prompt();
    const choice = await deferredPrompt.userChoice.catch(() => null);
    deferredPrompt = null;
    syncInstallButtons();
    if (choice?.outcome === "accepted" && typeof window.showToast === "function") {
      window.showToast("ARCHITECT se está instalando…");
    }
  }

  function bindInstallButtons() {
    document.querySelectorAll("[data-pwa-install]").forEach((btn) => {
      if (btn.dataset.pwaBound === "1") return;
      btn.dataset.pwaBound = "1";
      btn.addEventListener("click", promptInstall);
    });
    syncInstallButtons();
  }

  window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault();
    deferredPrompt = e;
    syncInstallButtons();
  });

  window.addEventListener("appinstalled", () => {
    deferredPrompt = null;
    syncInstallButtons();
  });

  registerServiceWorker();

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bindInstallButtons);
  } else {
    bindInstallButtons();
  }

  // Por si el botón se inyecta después (landing dinámico).
  window.ArchitectPWA = {
    refresh: bindInstallButtons,
    promptInstall,
    isStandalone,
  };
})();
