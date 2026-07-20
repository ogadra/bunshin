/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_PERL_ORIGIN_TEMPLATE: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
