import { FitAddon } from "@xterm/addon-fit";
import { Terminal } from "@xterm/xterm";
import "@xterm/xterm/css/xterm.css";

const FONT_SIZE = 22;

const ESCAPE = "\u001b";

export interface OutputBlock {
  write(data: string): void;
  finish(): void;
}

/**
 * Upper bound on the rows the data needs, counting every visible character as full width.
 * lolcat colours a single character with a whole escape sequence, so the escapes are dropped
 * rather than counted.
 */
const requiredRows = (data: string, cols: number): number => {
  let visible = 0;
  let escaped = false;
  for (const char of data) {
    if (char === ESCAPE) {
      escaped = true;
      continue;
    }
    if (escaped) {
      escaped = char < "@" || char > "~" || char === "[";
      continue;
    }
    visible += 1;
  }
  return Math.ceil((visible * 2) / cols) + 1;
};

export const createOutputBlock = (container: HTMLElement): OutputBlock => {
  // runner の stdout は \n だけを返す。
  // convertEol で行頭復帰込みに解釈させる
  const term = new Terminal({ convertEol: true, fontSize: FONT_SIZE, rows: 1 });
  const fit = new FitAddon();
  term.loadAddon(fit);
  term.open(container);

  let written = false;
  // 末尾の改行をそのまま書くとカーソルが空行へ進む。
  // その空行に合わせて rows を詰めると、xterm は先頭の行を scrollback へ捨てる
  let trailingNewlines = "";

  const columns = (): number => {
    const proposed = fit.proposeDimensions();
    if (proposed === undefined) {
      throw new Error("output block: the container width is not measurable");
    }
    return proposed.cols;
  };

  // 高さは FitAddon に決めさせない。
  // ブロックはページと一緒に縦へ伸び、内側にスクロールを持たない
  const fitToContent = (): void => {
    const buffer = term.buffer.active;
    term.resize(columns(), Math.max(buffer.baseY + buffer.cursorY + 1, 1));
  };

  let width = container.clientWidth;
  const observer = new ResizeObserver(() => {
    // 行数を変えると container の高さも動く。
    // 幅が変わったときだけ折り返しを取り直す
    if (container.clientWidth === width) return;
    width = container.clientWidth;
    const previousCols = term.cols;
    const cols = columns();
    term.resize(cols, term.rows * Math.max(Math.ceil(previousCols / cols), 1) + 1);
    term.write("", fitToContent);
  });
  observer.observe(container);

  return {
    write(data: string): void {
      const buffered = trailingNewlines + data;
      const body = buffered.replace(/\n+$/, "");
      trailingNewlines = buffered.slice(body.length);
      if (body === "") return;

      written = true;
      const cols = columns();
      // rows が足りないと xterm は溢れた行を scrollback へ送る。
      // 送られた行は rows を戻しても表示に返らないので、書く前に確保する
      term.resize(cols, term.rows + requiredRows(body, cols));
      term.write(body, fitToContent);
    },
    finish(): void {
      term.write("", () => {
        if (!written) {
          container.hidden = true;
          observer.disconnect();
          return;
        }
        fitToContent();
      });
    },
  };
};
