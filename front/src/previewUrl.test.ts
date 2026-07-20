import { describe, test, expect } from "vitest";
import { previewUrl } from "./previewUrl";

describe("previewUrl", () => {
  test("substitutes {hex} in the template", () => {
    expect(previewUrl("http://{hex}.ap-northeast-1.localhost/", "deadbeef")).toBe(
      "http://deadbeef.ap-northeast-1.localhost/",
    );
  });

  test("throws when the template has no {hex} placeholder", () => {
    expect(() => previewUrl("http://static.example.com/", "deadbeef")).toThrow(/\{hex\}/);
  });
});
