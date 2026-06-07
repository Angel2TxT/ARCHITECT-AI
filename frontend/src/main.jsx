import React, { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import {
  ArrowRight,
  Building2,
  CheckCircle2,
  Eye,
  EyeOff,
  Layers3,
  LogIn,
  Menu,
  ShieldCheck,
  Sparkles,
  Workflow
} from "lucide-react";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import "./styles.css";

const TOKEN_KEY = "plano_ia_token";
const USER_KEY = "plano_ia_user";
const SUB_KEY = "plano_ia_subscription";
const SELECTED_PLAN_KEY = "plano_ia_selected_plan";
const THEME_KEY = "plano_ia_theme";

gsap.registerPlugin(ScrollTrigger);

function getStoredTheme() {
  return localStorage.getItem(THEME_KEY) === "light" ? "light" : "dark";
}

function applyDocumentTheme(theme) {
  const next = theme === "light" ? "light" : "dark";
  const root = document.documentElement;
  root.classList.remove("light", "dark");
  root.classList.add(next);
  root.dataset.theme = next;
  root.style.colorScheme = next;
  localStorage.setItem(THEME_KEY, next);
}

applyDocumentTheme(getStoredTheme());

function setSession(data) {
  localStorage.setItem(TOKEN_KEY, data.access_token);
  localStorage.setItem(USER_KEY, JSON.stringify(data.user));
  localStorage.setItem(SUB_KEY, JSON.stringify(data.subscription));
}

function clearSession() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
  localStorage.removeItem(SUB_KEY);
}

function getToken() {
  return localStorage.getItem(TOKEN_KEY);
}

function formatApiError(data, fallback) {
  if (!data) return fallback;
  if (typeof data.detail === "string") return data.detail;
  if (Array.isArray(data.detail)) {
    return data.detail.map((item) => item.msg || item.message || JSON.stringify(item)).join(". ");
  }
  return fallback;
}

function navigate(path) {
  window.history.pushState({}, "", path);
  window.dispatchEvent(new PopStateEvent("popstate"));
}

function selectPlan(planSlug) {
  localStorage.setItem(SELECTED_PLAN_KEY, planSlug);
  navigate("/login#register");
}

async function applySelectedPlan(accessToken) {
  const planSlug = localStorage.getItem(SELECTED_PLAN_KEY);
  if (!planSlug || planSlug === "free") return;

  try {
    const res = await fetch("/api/billing/change-plan", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`
      },
      body: JSON.stringify({ plan_slug: planSlug })
    });

    if (res.ok) {
      const subscription = await res.json();
      localStorage.setItem(SUB_KEY, JSON.stringify(subscription));
      localStorage.removeItem(SELECTED_PLAN_KEY);
    }
  } catch {
    // El registro no depende del cambio de plan; el usuario puede cambiarlo dentro de la app.
  }
}

function useRoute() {
  const [path, setPath] = useState(window.location.pathname);

  useEffect(() => {
    const onPop = () => setPath(window.location.pathname);
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, []);

  return path;
}

function ThemeToggle() {
  const [theme, setTheme] = useState(getStoredTheme);

  function toggleTheme() {
    const next = theme === "dark" ? "light" : "dark";
    applyDocumentTheme(next);
    setTheme(next);
  }

  return (
    <button className="theme-toggle" type="button" onClick={toggleTheme} aria-label="Cambiar modo claro u oscuro">
      {theme === "dark" ? "Claro" : "Oscuro"}
    </button>
  );
}

function useRevealAnimations() {
  useEffect(() => {
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduceMotion) {
      document.querySelectorAll(".reveal").forEach((el) => el.classList.add("is-visible"));
      return undefined;
    }

    const ctx = gsap.context(() => {
      gsap.from(".site-nav", { y: -24, opacity: 0, duration: 0.75, ease: "power3.out" });
      gsap.from(".hero-copy > *", {
        y: 34,
        opacity: 0,
        duration: 0.9,
        stagger: 0.1,
        ease: "power3.out"
      });
      gsap.utils.toArray(".reveal").forEach((el) => {
        gsap.fromTo(
          el,
          { y: 42, opacity: 0, scale: 0.985 },
          {
            y: 0,
            opacity: 1,
            scale: 1,
            duration: 0.85,
            ease: "power3.out",
            scrollTrigger: {
              trigger: el,
              start: "top 86%",
              toggleActions: "play none none reverse"
            }
          }
        );
      });
      gsap.to(".hero-ring-one", {
        y: -80,
        rotate: 24,
        scrollTrigger: { trigger: ".hero", start: "top top", end: "bottom top", scrub: 1 }
      });
      gsap.to(".hero-ring-two", {
        y: 88,
        rotate: -18,
        scrollTrigger: { trigger: ".hero", start: "top top", end: "bottom top", scrub: 1 }
      });
    });

    return () => ctx.revert();
  }, []);
}

function StructureScene({ variant = "section" } = {}) {
  const canvasRef = useRef(null);
  const stageRef = useRef(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const stage = stageRef.current;
    if (!canvas || !stage) return undefined;

    const scene = new THREE.Scene();
    scene.fog = new THREE.Fog(0xf8fafc, 18, 46);

    const camera = new THREE.PerspectiveCamera(34, 1, 0.1, 90);
    camera.position.set(8.2, 5.1, 8.8);
    camera.lookAt(0, 1.65, 0);

    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setClearColor(0x000000, 0);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.outputColorSpace = THREE.SRGBColorSpace;

    scene.add(new THREE.HemisphereLight(0xffffff, 0xdde8f2, 1.45));
    const key = new THREE.DirectionalLight(0xffffff, 2.2);
    key.position.set(6, 10, 8);
    key.castShadow = true;
    scene.add(key);
    const blueLight = new THREE.PointLight(0x1ea7ff, 5, 22);
    blueLight.position.set(-2.6, 2.7, 2.1);
    scene.add(blueLight);
    const warmLight = new THREE.PointLight(0xffa33a, 4.5, 18);
    warmLight.position.set(3.4, 3.4, -2);
    scene.add(warmLight);

    const root = new THREE.Group();
    const building = new THREE.Group();
    root.add(building);
    scene.add(root);

    const concrete = new THREE.MeshStandardMaterial({ color: 0xe7e9ea, roughness: 0.58 });
    const slabMat = new THREE.MeshStandardMaterial({ color: 0xf7f8f8, roughness: 0.42 });
    const steel = new THREE.MeshStandardMaterial({ color: 0x59636d, roughness: 0.18, metalness: 0.72 });
    const darkSteel = new THREE.MeshStandardMaterial({ color: 0x25313b, roughness: 0.16, metalness: 0.82 });
    const glass = new THREE.MeshPhysicalMaterial({
      color: 0xc8ecff,
      transparent: true,
      opacity: 0.23,
      roughness: 0.02,
      transmission: 0.45,
      thickness: 0.3,
      depthWrite: false
    });
    const blue = new THREE.MeshBasicMaterial({ color: 0x19a8ff, transparent: true, opacity: 0.82 });
    const amber = new THREE.MeshBasicMaterial({ color: 0xffa63d, transparent: true, opacity: 0.9 });
    const red = new THREE.MeshStandardMaterial({ color: 0xc52222, emissive: 0x8f1010, emissiveIntensity: 1.1 });
    const edgeMaterial = new THREE.LineBasicMaterial({ color: 0x111820, transparent: true, opacity: 0.16 });

    function addMesh(geometry, material, position, group = building) {
      const item = new THREE.Mesh(geometry, material);
      item.position.set(...position);
      item.castShadow = true;
      item.receiveShadow = true;
      group.add(item);
      const edges = new THREE.LineSegments(new THREE.EdgesGeometry(geometry), edgeMaterial.clone());
      item.add(edges);
      return item;
    }

    function line(points, material) {
      const item = new THREE.Line(new THREE.BufferGeometry().setFromPoints(points), material);
      building.add(item);
      return item;
    }

    function marker(x, y, z, material) {
      const group = new THREE.Group();
      const sphere = new THREE.Mesh(new THREE.SphereGeometry(0.13, 32, 16), material);
      sphere.position.y = 0.16;
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.32, 0.01, 8, 64), material);
      ring.rotation.x = Math.PI / 2;
      group.add(sphere, ring);
      group.position.set(x, y, z);
      building.add(group);
      return group;
    }

    function buildProceduralModel() {
      addMesh(new THREE.BoxGeometry(8.8, 0.18, 5.8), concrete, [0, -0.1, 0]);
    [0, 1.55, 3.08].forEach((y) => {
      addMesh(new THREE.BoxGeometry(8.5, 0.16, 5.35), slabMat, [0, y, 0]);
    });

    [-3.85, 0, 3.85].forEach((x) => {
      [-2.35, 2.35].forEach((z) => {
        addMesh(new THREE.CylinderGeometry(0.075, 0.09, 3.35, 32), steel, [x, 1.67, z]);
      });
    });

    [1.71, 3.24].forEach((y) => {
      addMesh(new THREE.BoxGeometry(8.1, 0.12, 0.14), darkSteel, [0, y, -2.35]);
      addMesh(new THREE.BoxGeometry(8.1, 0.12, 0.14), darkSteel, [0, y, 2.35]);
      [-3.85, 0, 3.85].forEach((x) => {
        addMesh(new THREE.BoxGeometry(0.14, 0.12, 5), darkSteel, [x, y, 0]);
      });
    });

    function panel(x, y, z, w, h, rotation = 0) {
      const item = addMesh(new THREE.BoxGeometry(w, h, 0.035), glass, [x, y, z]);
      item.rotation.y = rotation;
      item.castShadow = false;
    }

    [-2.9, -1.45, 0, 1.45, 2.9].forEach((x) => {
      panel(x, 0.78, -2.48, 1.25, 1.2);
      panel(x, 2.32, -2.48, 1.25, 1.2);
    });
    [-1.9, 0, 1.9].forEach((x) => {
      panel(x, 0.78, 2.48, 1.55, 1.2);
      panel(x, 2.32, 2.48, 1.55, 1.2);
    });
    [0.72, 2.05].forEach((y) => {
      panel(4.05, y, -0.8, 1.35, 1.18, Math.PI / 2);
      panel(4.05, y, 0.8, 1.35, 1.18, Math.PI / 2);
    });

    addMesh(new THREE.BoxGeometry(0.78, 2.75, 1), concrete, [1.55, 1.42, 0.55]);

    const scanPath = line(
      [
        new THREE.Vector3(-3.85, 1.72, -2.35),
        new THREE.Vector3(0, 1.72, -2.35),
        new THREE.Vector3(0, 1.72, 2.35),
        new THREE.Vector3(3.85, 1.72, 2.35)
      ],
      blue
    );
    line([new THREE.Vector3(-3.85, 3.24, -2.35), new THREE.Vector3(3.85, 3.24, -2.35)], blue);
    line([new THREE.Vector3(3.85, 0.12, -2.35), new THREE.Vector3(3.85, 3.35, -2.35)], amber);
    line([new THREE.Vector3(3.85, 1.68, -2.35), new THREE.Vector3(3.85, 1.68, 2.35)], amber);

    const markerA = marker(3.85, 1.7, -2.35, red);
    const markerB = marker(0, 1.7, 2.35, blue);

    const scanPlane = new THREE.Mesh(
      new THREE.PlaneGeometry(8.6, 5.3),
      new THREE.MeshBasicMaterial({
        color: 0x39b8ff,
        transparent: true,
        opacity: 0.08,
        side: THREE.DoubleSide,
        depthWrite: false
      })
    );
    scanPlane.rotation.x = -Math.PI / 2;
    scanPlane.position.y = 1.62;
    building.add(scanPlane);
      return { markerA, markerB, scanPath, scanPlane };
    }

    let animatedParts = buildProceduralModel();

    const loader = new GLTFLoader();
    loader.load(
      "/models/architect-building.glb",
      (gltf) => {
        building.clear();
        const model = gltf.scene;
        model.position.set(0, -0.08, 0);
        model.rotation.y = -0.12;
        model.scale.setScalar(1.04);
        model.traverse((obj) => {
          if (obj.isMesh) {
            obj.castShadow = true;
            obj.receiveShadow = true;
            if (obj.material) {
              obj.material.needsUpdate = true;
            }
          }
        });
        building.add(model);

        const markerMaterial = red;
        const blueMarkerMaterial = blue;
        const markerA = marker(3.85, 1.7, -2.35, markerMaterial);
        const markerB = marker(0, 1.7, 2.35, blueMarkerMaterial);
        const scanPath = line(
          [
            new THREE.Vector3(-3.85, 1.72, -2.35),
            new THREE.Vector3(0, 1.72, -2.35),
            new THREE.Vector3(0, 1.72, 2.35),
            new THREE.Vector3(3.85, 1.72, 2.35)
          ],
          blue
        );
        const scanPlane = new THREE.Mesh(
          new THREE.PlaneGeometry(8.6, 5.3),
          new THREE.MeshBasicMaterial({
            color: 0x39b8ff,
            transparent: true,
            opacity: 0.08,
            side: THREE.DoubleSide,
            depthWrite: false
          })
        );
        scanPlane.rotation.x = -Math.PI / 2;
        scanPlane.position.y = 1.62;
        building.add(scanPlane);
        animatedParts = { markerA, markerB, scanPath, scanPlane };
      },
      undefined,
      () => {}
    );

    function resize() {
      const rect = stage.getBoundingClientRect();
      const width = Math.max(1, Math.floor(rect.width));
      const height = Math.max(1, Math.floor(rect.height));
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
    }
    resize();
    window.addEventListener("resize", resize);

    gsap.to(root.rotation, { y: 0.18, duration: 8, repeat: -1, yoyo: true, ease: "sine.inOut" });
    gsap.to(root.position, { y: 0.14, duration: 3.8, repeat: -1, yoyo: true, ease: "sine.inOut" });
    gsap.to(camera.position, { x: 6.2, y: 7.4, z: 10.8, duration: 10, repeat: -1, yoyo: true, ease: "sine.inOut" });

    let raf = 0;
    const animate = () => {
      raf = requestAnimationFrame(animate);
      const now = performance.now();
      camera.lookAt(0, 1.55, 0);
      animatedParts.markerA.rotation.y += 0.02;
      animatedParts.markerB.rotation.y -= 0.018;
      animatedParts.markerA.scale.setScalar(1.16 + Math.sin(now * 0.004) * 0.16);
      animatedParts.markerB.scale.setScalar(1.1 + Math.sin(now * 0.0032) * 0.12);
      animatedParts.scanPlane.position.y = 1.68 + Math.sin(now * 0.0024) * 0.08;
      animatedParts.scanPath.material.opacity = 0.65 + Math.sin(now * 0.003) * 0.25;
      renderer.render(scene, camera);
    };
    animate();

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", resize);
      renderer.dispose();
      scene.traverse((obj) => {
        if (obj.geometry) obj.geometry.dispose();
        if (obj.material) {
          if (Array.isArray(obj.material)) obj.material.forEach((mat) => mat.dispose());
          else obj.material.dispose();
        }
      });
    };
  }, []);

  return (
    <div className={`model-stage model-stage--${variant}`} ref={stageRef}>
      <canvas ref={canvasRef} aria-label="Modelo 3D de coordinacion tecnica ARCHITECT" />
      <div className="model-hud">
        <div className="hud-chip hud-chip-alert">
          <span />
          Posible interferencia viga-ducto
        </div>
        <div className="hud-chip">
          <span />
          Cotas, ejes y niveles por validar
        </div>
      </div>
      <div className="model-status">
        <strong>Analisis visual</strong>
        <small>Arquitectura, estructura e instalaciones</small>
      </div>
    </div>
  );
}

function HeroBolt() {
  return (
    <div className="hero-bolt-scene" aria-hidden="true">
      <div className="hero-lightning hero-lightning--violet" />
      <div className="hero-lightning hero-lightning--gold" />
      <div className="hero-bolt">
        <span className="bolt-face bolt-face-main" />
        <span className="bolt-face bolt-face-left" />
        <span className="bolt-face bolt-face-right" />
        <span className="bolt-edge bolt-edge-one" />
        <span className="bolt-edge bolt-edge-two" />
        <span className="bolt-edge bolt-edge-three" />
      </div>
    </div>
  );
}

const subscriptionPlans = [
  {
    slug: "starter",
    name: "Starter",
    tone: "violet",
    price: "$99",
    period: "/mes",
    description: "Para estudiantes, freelancers o revisiones puntuales de planos.",
    label: "Incluye",
    features: [
      "30 revisiones de planos al mes",
      "Deteccion de cotas y simbologia",
      "Modelo real habilitado",
      "Reporte PDF con observaciones"
    ]
  },
  {
    slug: "pro",
    name: "Pro",
    tone: "blue",
    price: "$299",
    period: "/mes",
    description: "Para despachos que revisan entregables de arquitectura e ingenieria cada semana.",
    label: "Mas elegido",
    popular: true,
    features: [
      "150 revisiones de planos al mes",
      "Revision arquitectonica, estructural e instalaciones",
      "Prioridad en procesamiento de IA",
      "API y reportes exportables"
    ]
  },
  {
    slug: "enterprise",
    name: "Enterprise",
    tone: "slate",
    price: "$999",
    period: "/mes",
    description: "Para constructoras, universidades o equipos con criterios tecnicos propios.",
    label: "Equipo",
    features: [
      "Hasta 9999 revisiones mensuales",
      "Criterios y listas de chequeo privadas",
      "Usuarios por equipo y roles",
      "Soporte dedicado y SLA"
    ]
  }
];

function Welcome() {
  useRevealAnimations();

  useEffect(() => {
    const onScroll = () => document.body.classList.toggle("nav-scrolled", window.scrollY > 14);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <main className="welcome-page">
      <nav className="site-nav">
        <a href="/" className="brand" onClick={(event) => { event.preventDefault(); navigate("/"); }}>
          <span className="brand-mark">A</span>
          <span>
            ARCHITECT
            <small>STUDIO</small>
          </span>
        </a>
        <div className="nav-links">
          <a href="#product">Inicio</a>
          <a href="#capabilities">Servicios</a>
          <a href="#review">Revision</a>
          <a href="#pricing">Planes</a>
          <a href="#coordination">Proceso</a>
        </div>
        <div className="nav-actions">
          <ThemeToggle />
          <button className="pill-button" onClick={() => navigate("/login#register")}>Empezar revision <ArrowRight size={15} /></button>
        </div>
        <Menu className="mobile-menu" size={22} />
      </nav>

      <section className="hero technical-grid" id="product">
        <span className="hero-ring hero-ring-one" />
        <span className="hero-ring hero-ring-two" />
        <div className="hero-energy" aria-hidden="true" />
        <div className="hero-asteroids" aria-hidden="true">
          <span />
          <span />
          <span />
          <span />
          <span />
        </div>
        <div className="hero-visual" aria-hidden="true">
          <HeroBolt />
        </div>
        <div className="hero-copy">
          <span className="eyebrow">Revision tecnica. Menos retrabajo.</span>
          <h1>
            Detecta errores en planos que <span>frenan la obra.</span>
          </h1>
          <p>
            ARCHITECT revisa planos arquitectonicos, estructurales e instalaciones para localizar interferencias, omisiones y criterios tecnicos antes de construir.
          </p>
          <div className="hero-actions">
            <button className="primary-action" onClick={() => navigate("/login#register")}>
              Iniciar revision <ArrowRight size={18} />
            </button>
            <button className="secondary-action" onClick={() => navigate("/login")}>
              Entrar al sistema
            </button>
          </div>
        </div>
        <div className="hero-proof-card">
          <strong>200+</strong>
          <span>criterios tecnicos listos para auditoria documental</span>
        </div>
        <div className="hero-stats">
          <div><strong>3</strong><span>disciplinas</span></div>
          <div><strong>4</strong><span>frentes</span></div>
          <div><strong>1</strong><span>reporte</span></div>
        </div>
        <div className="scroll-cue">Desplazar</div>
      </section>

      <section className="model-section" id="capabilities">
        <div className="section-intro reveal">
          <span className="line-label">Coordinacion visual</span>
          <h2>Lectura espacial para revisar interferencias y elementos criticos.</h2>
          <p>
            La vista 3D representa como la plataforma puede apoyar la interpretacion de elementos estructurales, cruces entre disciplinas, ejes, vanos y puntos que deben pasar por revision profesional.
          </p>
        </div>
        <StructureScene />
      </section>

      <section className="metrics-section">
        {[
          ["3", "Disciplinas coordinadas", "Arquitectura, estructura e instalaciones dentro del mismo flujo."],
          ["4", "Frentes de revision", "Geometria, cotas, interferencias y documentacion tecnica."],
          ["1", "Reporte centralizado", "Hallazgos organizados para revision, correccion y seguimiento."]
        ].map(([value, label, copy]) => (
          <div className="metric reveal" key={label}>
            <strong>{value}</strong>
            <span>{label}</span>
            <p>{copy}</p>
          </div>
        ))}
      </section>

      <section className="capability-section" id="review">
        <div className="section-intro centered reveal">
          <h2>Capacidades de revision tecnica</h2>
          <p>Herramientas pensadas para reducir retrabajo, ordenar observaciones y mejorar la coordinacion entre disciplinas antes de obra.</p>
        </div>
        <div className="capability-grid">
          <article className="capability-card wide reveal">
            <Building2 size={30} />
            <h3>Deteccion de inconsistencias</h3>
            <p>Identifica cotas faltantes, simbologia inconsistente, elementos duplicados, cruces no resueltos y zonas que requieren validacion tecnica.</p>
          </article>
          <article className="capability-card reveal">
            <Layers3 size={30} />
            <h3>Revision estructural preliminar</h3>
            <p>Apoya la lectura de ejes, niveles, columnas, vigas, claros y continuidad de elementos. No sustituye el calculo ni la firma del especialista.</p>
            <ul>
              <li><CheckCircle2 size={16} /> Ejes y niveles</li>
              <li><CheckCircle2 size={16} /> Elementos portantes</li>
            </ul>
          </article>
          <article className="capability-card dark-card reveal" id="coordination">
            <Workflow size={30} />
            <h3>Coordinacion de especialidades</h3>
            <p>Compara informacion entre arquitectura, estructura e instalaciones para localizar interferencias, cambios no reflejados y criterios pendientes.</p>
          </article>
          <article className="capability-card wide reveal">
            <ShieldCheck size={30} />
            <h3>Criterios tecnicos configurables</h3>
            <p>Permite estructurar listas de verificacion por proyecto, municipio o despacho: accesibilidad, seguridad, simbologia, escalas, notas generales y criterios de entrega.</p>
          </article>
        </div>
      </section>

      <section className="pricing-section technical-grid" id="pricing">
        <div className="pricing-intro reveal">
          <span className="line-label">Suscripciones IA</span>
          <h2>Planes flexibles para cada etapa de revision.</h2>
          <p>Escoge un plan segun el volumen de planos, disciplinas y nivel de control tecnico que necesita tu equipo.</p>
        </div>
        <div className="pricing-stage reveal">
          {subscriptionPlans.map((plan) => (
            <article className={`pricing-card pricing-card--${plan.tone}${plan.popular ? " pricing-card--featured" : ""}`} key={plan.name}>
              <div className="pricing-card-head">
                <h3>{plan.name}</h3>
                {plan.popular && <span><Sparkles size={13} /> Popular</span>}
              </div>
              <p>{plan.description}</p>
              <div className="pricing-divider" />
              <div className="pricing-price">
                <strong>{plan.price}</strong>
                {plan.period && <small>{plan.period}</small>}
              </div>
              <span className="pricing-label">{plan.label}</span>
              <ul>
                {plan.features.map((feature) => (
                  <li key={feature}><CheckCircle2 size={18} /> {feature}</li>
                ))}
              </ul>
              <button className={plan.popular ? "primary-action" : "secondary-action"} onClick={() => selectPlan(plan.slug)}>
                Elegir plan <ArrowRight size={16} />
              </button>
            </article>
          ))}
        </div>
      </section>

      <section className="cta-section technical-grid">
        <div className="reveal">
          <h2>Revisa tus planos antes de emitirlos a obra.</h2>
          <p>Centraliza observaciones, documenta inconsistencias y entrega al equipo una base clara para corregir el proyecto con mayor control tecnico.</p>
          <button className="primary-action" onClick={() => navigate("/login#register")}>
            Crear cuenta <ArrowRight size={18} />
          </button>
        </div>
      </section>

      <footer className="site-footer">
        <div>
          <strong>ARCHITECT</strong>
          <p>Asistente de revision tecnica para planos de arquitectura, ingenieria civil e instalaciones. Apoya decisiones, no reemplaza la validacion profesional.</p>
        </div>
        <div className="footer-links">
          <button onClick={() => navigate("/login")}>Ingresar</button>
          <button onClick={() => navigate("/app")}>App</button>
          <a href="/docs">API</a>
        </div>
      </footer>
    </main>
  );
}

function Login() {
  const [mode, setMode] = useState(window.location.hash === "#register" ? "register" : "login");
  const [showPassword, setShowPassword] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const formRef = useRef(null);

  useEffect(() => {
    if (getToken()) navigate("/app");
  }, []);

  useEffect(() => {
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduceMotion) return undefined;

    const ctx = gsap.context(() => {
      gsap.from(".auth-panel", {
        y: 28,
        opacity: 0,
        scale: 0.98,
        duration: 0.72,
        ease: "power3.out"
      });
      gsap.from(".back-link", {
        x: -12,
        opacity: 0,
        duration: 0.55,
        delay: 0.12,
        ease: "power2.out"
      });
      gsap.to(".auth-orbit-one", {
        y: -34,
        rotate: 12,
        duration: 7,
        repeat: -1,
        yoyo: true,
        ease: "sine.inOut"
      });
      gsap.to(".auth-orbit-two", {
        y: 38,
        rotate: -10,
        duration: 8,
        repeat: -1,
        yoyo: true,
        ease: "sine.inOut"
      });
    });

    return () => ctx.revert();
  }, []);

  useEffect(() => {
    const form = formRef.current;
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (!form || reduceMotion) return;

    gsap.fromTo(
      form.querySelectorAll(".auth-animated-field"),
      { x: mode === "register" ? 18 : -18, opacity: 0 },
      { x: 0, opacity: 1, duration: 0.42, stagger: 0.055, ease: "power2.out" }
    );
  }, [mode]);

  function switchMode(nextMode) {
    setError("");
    setShowPassword(false);
    setMode(nextMode);
    window.history.replaceState({}, "", nextMode === "register" ? "/login#register" : "/login");
  }

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    setError("");
    const form = new FormData(event.currentTarget);
    const payload = {
      email: String(form.get("email") || "").trim(),
      password: String(form.get("password") || "")
    };
    if (mode === "register") {
      payload.full_name = String(form.get("full_name") || "").trim();
    }

    try {
      const res = await fetch(`/api/auth/${mode === "register" ? "register" : "login"}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(formatApiError(data, mode === "register" ? "Error al registrarse" : "Error al iniciar sesion"));
        setBusy(false);
        return;
      }
      setSession(data);
      if (mode === "register") {
        await applySelectedPlan(data.access_token);
      }
      navigate("/app");
    } catch {
      setError("No se pudo conectar con el servidor.");
      setBusy(false);
    }
  }

  return (
    <main className={`auth-view auth-view--${mode}`}>
      <div className="auth-bg-motion" aria-hidden="true">
        <span className="auth-orbit auth-orbit-one" />
        <span className="auth-orbit auth-orbit-two" />
        <span className="auth-grid-line auth-grid-line-one" />
        <span className="auth-grid-line auth-grid-line-two" />
      </div>
      <button className="back-link" onClick={() => navigate("/")}>Volver al inicio</button>
      <div className="auth-theme-toggle">
        <ThemeToggle />
      </div>
      <section className="auth-panel">
        <div className="auth-heading">
          <span>ARCHITECT Studio</span>
          <h1>{mode === "register" ? "Crear cuenta" : "Iniciar sesion"}</h1>
          <p>Acceso al entorno de revision tecnica de planos asistida por IA.</p>
        </div>

        <div className={`auth-tabs auth-tabs--${mode}`}>
          <span className="auth-tab-indicator" aria-hidden="true" />
          <button className={mode === "login" ? "active" : ""} onClick={() => switchMode("login")}>Iniciar sesion</button>
          <button className={mode === "register" ? "active" : ""} onClick={() => switchMode("register")}>Registrarse</button>
        </div>

        <form onSubmit={submit} className="auth-form" ref={formRef} key={mode}>
          {mode === "register" && (
            <label className="auth-animated-field">
              Nombre
              <input name="full_name" autoComplete="name" placeholder="Tu nombre" />
            </label>
          )}
          <label className="auth-animated-field">
            Correo electronico
            <input name="email" type="email" autoComplete="email" required placeholder="tu@correo.com" />
          </label>
          <label className="auth-animated-field">
            Contrasena
            <div className="password-field">
              <input
                name="password"
                type={showPassword ? "text" : "password"}
                autoComplete={mode === "register" ? "new-password" : "current-password"}
                minLength={mode === "register" ? 8 : undefined}
                required
                placeholder={mode === "register" ? "Minimo 8 caracteres" : "Tu contrasena"}
              />
              <button type="button" onClick={() => setShowPassword((value) => !value)} aria-label="Mostrar contrasena">
                {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
          </label>

          {error && <p className="form-error auth-animated-field">{error}</p>}

          <button className="auth-submit auth-animated-field" type="submit" disabled={busy}>
            {busy ? "Procesando..." : mode === "register" ? "Crear cuenta" : "Entrar"}
            {mode === "register" ? <Sparkles size={18} /> : <LogIn size={18} />}
          </button>
        </form>
      </section>
    </main>
  );
}

function AppShell() {
  useEffect(() => {
    if (!getToken()) navigate("/login");
  }, []);

  return (
    <main className="legacy-shell">
      <div className="legacy-topbar">
        <strong>ARCHITECT</strong>
        <div>
          <button onClick={() => navigate("/")}>Welcome</button>
          <button
            onClick={() => {
              clearSession();
              navigate("/login");
            }}
          >
            Salir
          </button>
        </div>
      </div>
      <iframe title="ARCHITECT Workspace" src="/legacy-app" />
    </main>
  );
}

function Root() {
  const path = useRoute();
  if (path === "/login") return <Login />;
  if (path === "/app") return <AppShell />;
  return <Welcome />;
}

createRoot(document.getElementById("root")).render(<Root />);
