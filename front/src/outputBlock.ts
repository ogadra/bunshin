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
export const requiredRows = (data: string, cols: number): number => {
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

  // 末尾の改行をそのまま書くとカーソルが空行へ進む。
  // その空行に合わせて rows を詰めると、xterm は先頭の行を scrollback へ捨てる
  let trailingNewlines = "";
  let content = "";

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

  const push = (data: string): void => {
    const cols = columns();
    // rows が足りないと xterm は溢れた行を scrollback へ送る。
    // 送られた行は rows を戻しても表示に返らないので、書く前に確保する
    term.resize(cols, term.rows + requiredRows(data, cols));
    term.write(data, fitToContent);
  };

  let width = container.clientWidth;
  const observer = new ResizeObserver(() => {
    // 行数を変えると container の高さも動く。
    // 幅が変わったときだけ折り返しを取り直す
    if (container.clientWidth === width) return;
    width = container.clientWidth;
    // 折り返しが増えると xterm は溢れた行を scrollback へ送る。
    // 幅に合わせた行数を確保しなおすため、空の端末に書き直す
    term.reset();
    term.resize(columns(), 1);
    if (content !== "") push(content);
  });
  observer.observe(container);

  return {
    write(data: string): void {
      const buffered = trailingNewlines + data;
      const body = buffered.replace(/\n+$/, "");
      trailingNewlines = buffered.slice(body.length);
      if (body === "") return;

      content += body;
      push(body);
    },
    finish(): void {
      term.write("", () => {
        if (content === "") {
          container.hidden = true;
          observer.disconnect();
          return;
        }
        fitToContent();
      });
    },
  };
};
