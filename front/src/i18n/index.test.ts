import { describe, test, expect } from "vitest";
import { detectLang, MessageKey, translate, type Lang } from "./index";

describe("detectLang", () => {
  test.each([
    ["ja", "ja"],
    ["ja-JP", "ja"],
    ["JA-jp", "ja"],
    ["en", "en"],
    ["en-US", "en"],
    ["fr", "en"],
    ["", "en"],
    [undefined, "en"],
  ] satisfies Array<[string | undefined, Lang]>)("navigator.language %s → %s", (input, want) => {
    expect(detectLang(input)).toBe(want);
  });
});

describe("translate", () => {
  const EXPECTED: Record<MessageKey, { en: string; ja: string }> = {
    errorNoIdleRunner: {
      en: "No available execution environment",
      ja: "実行環境に空きがありません",
    },
    errorSessionLost: {
      en: "Previous execution environment was not found",
      ja: "以前実行した環境が見つかりません",
    },
    errorEditTooLarge: { en: "Edit content is too large", ja: "編集内容が大きすぎます" },
    errorGatewayTimeout: {
      en: "Server response timed out",
      ja: "サーバー応答がタイムアウトしました",
    },
    errorBadGateway: {
      en: "Cannot reach the execution environment",
      ja: "実行環境に接続できません",
    },
    errorNetwork: { en: "Cannot connect to the server", ja: "サーバーに接続できません" },
    errorInternal: {
      en: "An internal server error occurred",
      ja: "サーバー内部エラーが発生しました",
    },
    statusSaving: { en: "Saving…", ja: "保存中…" },
    statusSaved: { en: "Saved", ja: "保存済み" },
    statusError: { en: "Error", ja: "エラー" },
    stackInfoOpen: { en: "Stack info", ja: "接続先" },
    stackInfoTitle: { en: "Connected stack", ja: "接続中のスタック" },
    stackInfoRegion: { en: "Region", ja: "リージョン" },
    stackInfoCloud: { en: "Cloud", ja: "クラウド" },
    stackInfoClose: { en: "Close", ja: "閉じる" },
  };

  test.each(Object.values(MessageKey))("%s resolves to expected en/ja", (key) => {
    expect(translate("en", key)).toBe(EXPECTED[key].en);
    expect(translate("ja", key)).toBe(EXPECTED[key].ja);
  });
});
