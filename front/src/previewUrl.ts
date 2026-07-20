export const previewUrl = (template: string, hex: string, stack: string): string => {
  if (!template.includes("{hex}")) {
    throw new Error("VITE_PERL_ORIGIN_TEMPLATE must contain '{hex}' placeholder");
  }
  if (!template.includes("{stack}")) {
    throw new Error("VITE_PERL_ORIGIN_TEMPLATE must contain '{stack}' placeholder");
  }
  return template.replace("{hex}", hex).replace("{stack}", stack);
};
