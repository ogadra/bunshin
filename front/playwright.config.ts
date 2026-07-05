import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  testMatch: /.*\.e2e\.ts/,
  use: {
    baseURL: "http://localhost:4273",
    // Playwright 同梱ブラウザを実行できない環境 (NixOS 等) ではシステムのブラウザを指定する
    launchOptions: process.env.PLAYWRIGHT_BROWSER_PATH
      ? { executablePath: process.env.PLAYWRIGHT_BROWSER_PATH }
      : {},
  },
  webServer: {
    command: "pnpm build && pnpm preview --port 4273 --strictPort",
    url: "http://localhost:4273",
    reuseExistingServer: !process.env.CI,
  },
});
