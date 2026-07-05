import { createPerlEditor } from "./editor";
import { samplePerl } from "./samplePerl";
import "./style.css";

createPerlEditor(document.getElementById("editor")!, samplePerl);
