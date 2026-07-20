export const previewUrl = (template: string, hex: string): string => {
  if (!template.includes("{hex}")) {
    throw new Error("VITE_PERL_ORIGIN_TEMPLATE must contain '{hex}' placeholder");
  }
  return template.replace("{hex}", hex);
};
