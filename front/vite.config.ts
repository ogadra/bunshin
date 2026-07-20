import { defineConfig, loadEnv } from "vite-plus";
import { viteSingleFile } from "vite-plugin-singlefile";

// process.env は config 評価時点で front/.env を含まないため、loadEnv で明示的に読む
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, import.meta.dirname, "");
  const apiTarget = env.VITE_API_TARGET;
  return {
    plugins: [viteSingleFile()],
    server: apiTarget
      ? {
          proxy: {
            "/api": {
              target: apiTarget,
              changeOrigin: true,
            },
          },
        }
      : undefined,
  };
});
