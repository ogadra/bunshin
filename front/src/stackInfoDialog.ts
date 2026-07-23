import { translate, type Lang } from "./i18n";
import { classifyStack, type StackInfo } from "./stackInfo";

export type StackInfoDialogController = {
  setStack: (stack: string) => void;
};

export const createStackInfoDialog = (
  button: HTMLButtonElement,
  dialog: HTMLDialogElement,
  lang: Lang,
  initialStack: string,
): StackInfoDialogController => {
  let currentStack: StackInfo = classifyStack(initialStack);

  const t = document.createElement("template");
  t.innerHTML = `
    <h2 data-role="title" class="stack-info-title"></h2>
    <dl class="stack-info-list">
      <dt data-role="region-label"></dt><dd data-role="region-value"></dd>
      <dt data-role="cloud-label"></dt><dd data-role="cloud-value"></dd>
    </dl>
    <form method="dialog" class="stack-info-actions">
      <button type="submit" data-role="close"></button>
    </form>
  `;
  dialog.replaceChildren(t.content.cloneNode(true));

  const pick = <T extends Element>(role: string): T => {
    const el = dialog.querySelector<T>(`[data-role="${role}"]`);
    if (el === null) throw new Error(`stack info dialog: missing element with data-role="${role}"`);
    return el;
  };
  const title = pick<HTMLElement>("title");
  const regionLabel = pick<HTMLElement>("region-label");
  const regionValue = pick<HTMLElement>("region-value");
  const cloudLabel = pick<HTMLElement>("cloud-label");
  const cloudValue = pick<HTMLElement>("cloud-value");
  const closeButton = pick<HTMLButtonElement>("close");

  title.textContent = translate(lang, "stackInfoTitle");
  regionLabel.textContent = translate(lang, "stackInfoRegion");
  cloudLabel.textContent = translate(lang, "stackInfoCloud");
  closeButton.textContent = translate(lang, "stackInfoClose");

  const refresh = (): void => {
    regionValue.textContent = currentStack.region;
    cloudValue.textContent = currentStack.cloud;
  };

  button.textContent = translate(lang, "stackInfoOpen");
  button.addEventListener("click", () => {
    refresh();
    dialog.showModal();
  });

  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) dialog.close();
  });

  return {
    setStack: (stack) => {
      currentStack = classifyStack(stack);
    },
  };
};
