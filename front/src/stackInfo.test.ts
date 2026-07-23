import { describe, test, expect } from "vitest";
import { classifyStack } from "./stackInfo";

describe("classifyStack", () => {
  test.each([
    ["asia-northeast1", "東京", "Google Cloud"],
    ["asia-northeast2", "大阪", "Google Cloud"],
    ["ap-northeast-1", "東京", "AWS"],
    ["ap-northeast-3", "大阪", "AWS"],
  ])("%s → %s / %s", (stack, region, cloud) => {
    expect(classifyStack(stack)).toEqual({ region, cloud });
  });

  test("an unrecognized stack name is rejected loudly rather than falling back to Unknown", () => {
    expect(() => classifyStack("preview")).toThrow(/unknown stack name: preview/);
  });
});
