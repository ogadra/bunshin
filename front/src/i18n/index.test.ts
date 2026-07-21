import { describe, test, expect } from "vitest";
import { detectLang, translate, type Lang, type MessageKey } from "./index";

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
  const KEYS: MessageKey[] = [
    "errorNoIdleRunner",
    "errorSessionLost",
    "errorEditTooLarge",
    "errorGatewayTimeout",
    "errorBadGateway",
    "errorNetwork",
    "errorInternal",
    "statusSaving",
    "statusSaved",
    "statusError",
  ];

  test.each(["en", "ja"] satisfies Lang[])("every MessageKey resolves to non-empty %s", (lang) => {
    for (const key of KEYS) {
      const text = translate(lang, key);
      expect(text, `${lang}:${key}`).toBeTruthy();
    }
  });

  test("ja and en differ for every key", () => {
    for (const key of KEYS) {
      expect(translate("ja", key)).not.toBe(translate("en", key));
    }
  });
});
