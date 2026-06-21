import { defineConfig } from "vite-plus";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  plugins: [viteSingleFile()],
  server: {
    proxy: {
      "/api": {
        target: `http://localhost:${process.env.NGINX_PORT ?? "80"}`,
        changeOrigin: true,
      },
    },
  },
});
