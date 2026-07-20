import { describe, test, expect } from "vitest";
import { previewUrl, sessionHexFromCookie } from "./previewUrl";

describe("sessionHexFromCookie", () => {
  test("returns the hex portion of a session_id cookie", () => {
    expect(sessionHexFromCookie("session_id=ap-northeast-1_deadbeef")).toBe("deadbeef");
  });

  test("finds session_id when it is not the first cookie", () => {
    expect(sessionHexFromCookie("other=1; session_id=ap-northeast-3_cafebabe; last=2")).toBe(
      "cafebabe",
    );
  });

  test("returns null when session_id cookie is absent", () => {
    expect(sessionHexFromCookie("other=value")).toBeNull();
    expect(sessionHexFromCookie("")).toBeNull();
  });

  test("returns null when the value has no stack prefix", () => {
    expect(sessionHexFromCookie("session_id=deadbeef")).toBeNull();
  });

  test("returns null when the hex portion is empty", () => {
    expect(sessionHexFromCookie("session_id=ap-northeast-1_")).toBeNull();
  });
});

describe("previewUrl", () => {
  test("substitutes {hex} in the template", () => {
    expect(previewUrl("http://{hex}.ap-northeast-1.internal.test/", "deadbeef")).toBe(
      "http://deadbeef.ap-northeast-1.internal.test/",
    );
  });

  test("throws when the template has no {hex} placeholder", () => {
    expect(() => previewUrl("http://static.example.com/", "deadbeef")).toThrow(/\{hex\}/);
  });
});
