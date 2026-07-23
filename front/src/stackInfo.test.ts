import { describe, test, expect } from "vitest";
import { Cloud, Region, classifyStack } from "./stackInfo";

describe("classifyStack", () => {
  test.each([
    ["asia-northeast1", Region.TOKYO, Cloud.GOOGLE_CLOUD],
    ["asia-northeast2", Region.OSAKA, Cloud.GOOGLE_CLOUD],
    ["ap-northeast-1", Region.TOKYO, Cloud.AWS],
    ["ap-northeast-3", Region.OSAKA, Cloud.AWS],
  ])("%s → %s / %s", (stack, region, cloud) => {
    expect(classifyStack(stack)).toEqual({ region, cloud });
  });

  test("an unrecognized stack name is rejected loudly rather than falling back to Unknown", () => {
    expect(() => classifyStack("preview")).toThrow(/unknown stack name: preview/);
  });
});
