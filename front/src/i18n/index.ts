export type Lang = "en" | "ja";

export type MessageKey =
  | "errorNoIdleRunner"
  | "errorSessionLost"
  | "errorEditTooLarge"
  | "errorGatewayTimeout"
  | "errorBadGateway"
  | "errorNetwork"
  | "errorInternal"
  | "statusSaving"
  | "statusSaved"
  | "statusError";

type Messages = Record<Lang, Record<MessageKey, string>>;

const MESSAGES: Messages = {
  en: {
    errorNoIdleRunner: "No available execution environment",
    errorSessionLost: "Previous execution environment was not found",
    errorEditTooLarge: "Edit content is too large",
    errorGatewayTimeout: "Server response timed out",
    errorBadGateway: "Cannot reach the execution environment",
    errorNetwork: "Cannot connect to the server",
    errorInternal: "An internal server error occurred",
    statusSaving: "Saving…",
    statusSaved: "Saved",
    statusError: "Error",
  },
  ja: {
    errorNoIdleRunner: "実行環境に空きがありません",
    errorSessionLost: "以前実行した環境が見つかりません",
    errorEditTooLarge: "編集内容が大きすぎます",
    errorGatewayTimeout: "サーバー応答がタイムアウトしました",
    errorBadGateway: "実行環境に接続できません",
    errorNetwork: "サーバーに接続できません",
    errorInternal: "サーバー内部エラーが発生しました",
    statusSaving: "保存中…",
    statusSaved: "保存済み",
    statusError: "エラー",
  },
};

export const detectLang = (navigatorLanguage: string | undefined): Lang =>
  navigatorLanguage?.toLowerCase().startsWith("ja") === true ? "ja" : "en";

export const translate = (lang: Lang, key: MessageKey): string => MESSAGES[lang][key];
