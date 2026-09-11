import { detectLang } from "./i18n";
import { initTerminal } from "./terminal";
import { createXtermView } from "./xtermView";
import "./style.css";

const form = document.getElementById("input-bar") as HTMLFormElement;
const view = createXtermView(document.getElementById("terminal") as HTMLElement);

initTerminal(
  view,
  {
    form,
    input: document.getElementById("command") as HTMLInputElement,
    button: form.querySelector("button") as HTMLButtonElement,
    status: document.getElementById("status") as HTMLElement,
  },
  detectLang(navigator.language),
);
