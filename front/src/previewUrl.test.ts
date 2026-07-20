import { describe, test, expect } from "vitest";
import { previewUrl } from "./previewUrl";

describe("previewUrl", () => {
  test("substitutes {hex} and {stack} in the template", () => {
    expect(previewUrl("http://{hex}.{stack}.localhost/", "deadbeef", "ap-northeast-1")).toBe(
      "http://deadbeef.ap-northeast-1.localhost/",
    );
  });

  test("throws when the template has no {hex} placeholder", () => {
    expect(() =>
      previewUrl("http://static.{stack}.example.com/", "deadbeef", "ap-northeast-1"),
    ).toThrow(/\{hex\}/);
  });

  test("throws when the template has no {stack} placeholder", () => {
    expect(() => previewUrl("http://{hex}.example.com/", "deadbeef", "ap-northeast-1")).toThrow(
      /\{stack\}/,
    );
  });
});
