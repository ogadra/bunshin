import { FitAddon } from "@xterm/addon-fit";
import { Terminal } from "@xterm/xterm";
import "@xterm/xterm/css/xterm.css";
import type { TerminalView } from "./terminal";

const FONT_SIZE = 18;

export const createXtermView = (container: HTMLElement): TerminalView => {
  // runner の stdout は \n だけを返す。
  // convertEol で行頭復帰込みに解釈させる
  const term = new Terminal({ convertEol: true, fontSize: FONT_SIZE });
  const fit = new FitAddon();
  term.loadAddon(fit);
  term.open(container);
  fit.fit();

  window.addEventListener("resize", () => {
    fit.fit();
  });

  return {
    write(data: string): void {
      term.write(data);
    },
  };
};
