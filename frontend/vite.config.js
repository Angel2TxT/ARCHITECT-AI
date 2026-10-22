import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const target = env.VITE_API_PROXY_TARGET || "http://127.0.0.1:8000";

  return {
    plugins: [react()],
    build: {
      chunkSizeWarningLimit: 600,
      rollupOptions: {
        output: {
          manualChunks(id) {
            if (id.includes("node_modules")) {
              if (id.includes("three")) {
                return "vendor-three";
              }
              if (id.includes("gsap")) {
                return "vendor-gsap";
              }
              if (id.includes("lucide-react")) {
                return "vendor-icons";
              }
              if (id.includes("react") || id.includes("react-dom")) {
                return "vendor-react";
              }
              return "vendor";
            }
          }
        }
      }
    },
    server: {
      port: 3000,
      proxy: {
        "/api": target,
        "/docs": target,
        "/openapi.json": target,
        "/static": target,
        "/media": target,
        "/legacy-app": target,
        "/checkout": target,
        "/checkout/success": target
      }
    }
  };
});
