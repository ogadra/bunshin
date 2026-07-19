export const sessionHexFromCookie = (cookie: string): string | null => {
  const match = cookie.match(/(?:^|;\s*)session_id=([^;]+)/);
  if (!match) return null;
  const value = match[1];
  const underscore = value.indexOf("_");
  if (underscore < 0) return null;
  return value.slice(underscore + 1);
};

export const previewUrl = (template: string, hex: string): string => {
  if (!template.includes("{hex}")) {
    throw new Error("VITE_PERL_ORIGIN_TEMPLATE must contain '{hex}' placeholder");
  }
  return template.replace("{hex}", hex);
};
