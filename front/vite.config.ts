import { defineConfig } from "vite-plus";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  plugins: [viteSingleFile()],
  server: process.env.VITE_API_TARGET
    ? {
        proxy: {
          "/api": {
            target: process.env.VITE_API_TARGET,
            changeOrigin: true,
          },
        },
      }
    : undefined,
});
