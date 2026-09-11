export type Lang = "en" | "ja";

export const MessageKey = {
  errorNoIdleRunner: "errorNoIdleRunner",
  errorSessionLost: "errorSessionLost",
  errorGatewayTimeout: "errorGatewayTimeout",
  errorBadGateway: "errorBadGateway",
  errorNetwork: "errorNetwork",
  errorInternal: "errorInternal",
  termConnecting: "termConnecting",
  termRetrying: "termRetrying",
  termSessionRecreated: "termSessionRecreated",
} as const;

export type MessageKey = (typeof MessageKey)[keyof typeof MessageKey];

type Messages = Record<Lang, Record<MessageKey, string>>;

const MESSAGES: Messages = {
  en: {
    errorNoIdleRunner: "No available execution environment",
    errorSessionLost: "Previous execution environment was not found",
    errorGatewayTimeout: "Server response timed out",
    errorBadGateway: "Cannot reach the execution environment",
    errorNetwork: "Cannot connect to the server",
    errorInternal: "An internal server error occurred",
    termConnecting: "Connecting…",
    termRetrying: "Retrying…",
    termSessionRecreated: "Session recreated. Run the command again.",
  },
  ja: {
    errorNoIdleRunner: "実行環境に空きがありません",
    errorSessionLost: "以前実行した環境が見つかりません",
    errorGatewayTimeout: "サーバー応答がタイムアウトしました",
    errorBadGateway: "実行環境に接続できません",
    errorNetwork: "サーバーに接続できません",
    errorInternal: "サーバー内部エラーが発生しました",
    termConnecting: "接続中…",
    termRetrying: "再試行します…",
    termSessionRecreated: "セッションを作り直しました。もう一度実行してください。",
  },
};

export const detectLang = (navigatorLanguage: string | undefined): Lang =>
  navigatorLanguage?.toLowerCase().startsWith("ja") === true ? "ja" : "en";

export const translate = (lang: Lang, key: MessageKey): string => MESSAGES[lang][key];
