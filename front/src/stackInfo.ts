export type StackInfo = {
  region: string;
  cloud: string;
};

const STACK_TABLE: Record<string, StackInfo> = {
  "asia-northeast1": { region: "東京", cloud: "Google Cloud" },
  "asia-northeast2": { region: "大阪", cloud: "Google Cloud" },
  "ap-northeast-1": { region: "東京", cloud: "AWS" },
  "ap-northeast-3": { region: "大阪", cloud: "AWS" },
};

export const classifyStack = (stack: string): StackInfo => {
  const known = STACK_TABLE[stack];
  if (known === undefined) throw new Error(`unknown stack name: ${stack}`);
  return known;
};
