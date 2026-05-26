/**
 * Muestra el loader lo antes posible en cada carga/recarga (F5) y al restaurar desde bfcache.
 */
(function () {
  var DEFAULT_TEXT = "Cargando…";

  function armLoader(text) {
    var body = document.body;
    if (!body) return;
    body.classList.add("app-loading");
    var el = document.getElementById("appLoader");
    if (!el) return;
    if (text) {
      var t = document.getElementById("appLoaderText");
      if (t) t.textContent = text;
    }
    el.classList.add("app-loader--visible");
    el.setAttribute("aria-busy", "true");
  }

  function runWhenBodyReady(fn) {
    if (document.body) fn();
    else document.addEventListener("DOMContentLoaded", fn, { once: true });
  }

  runWhenBodyReady(function () {
    armLoader(DEFAULT_TEXT);
  });

  window.addEventListener("pageshow", function (ev) {
    if (!document.getElementById("appLoader")) return;
    armLoader(DEFAULT_TEXT);
    if (ev.persisted) {
      window.dispatchEvent(new CustomEvent("plano:pageshow-restore"));
    }
  });
})();
