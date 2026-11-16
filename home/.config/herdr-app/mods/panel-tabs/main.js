// panel-tabs: the strip above the docked panels — Files, Changes, Tasks, Artifacts.
// It selects (or re-shows) the panel stack's child; hiding stays with the tab bar's
// Files / Changes buttons, so a click here can never leave the panel out of reach.
import { View, div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { theme, layout, run, shared, setShared, checking } from "herdr";

const STACK = "panel-body";
const PANEL = "panel";
const PANELS = [
  { id: "files", label: "Files", icon: "mods/files/file.svg" },
  { id: "changes", label: "Changes", icon: "mods/changes/changes.svg" },
  { id: "oo-tasks", label: "Tasks", icon: "mods/panel-tabs/tasks.svg" },
  { id: "oo-artifacts", label: "Artifacts", icon: "mods/panel-tabs/artifacts.svg" },
];

function find(node, id) {
  if (!node || typeof node !== "object") return null;
  if (node.id === id) return node;
  for (const child of node.children ?? []) {
    const hit = find(child, id);
    if (hit) return hit;
  }
  return null;
}

export default class PanelTabs extends View {
  init() {
    if (checking()) return;
    // The tab bar restores a space's panel only when its id is in this list.
    const enabled = shared("workspace.panels") ?? ["files", "changes"];
    const merged = [...new Set([...enabled, ...PANELS.map((panel) => panel.id)])];
    if (merged.length !== enabled.length) setShared("workspace.panels", merged);
  }

  render() {
    const t = theme();
    const root = layout();
    const stack = find(root, STACK);
    const panel = find(root, PANEL);
    const shown = panel ? !panel.hidden : false;
    const active = shown ? stack?.active ?? null : null;
    const tab = (entry) => {
      const on = active === entry.id;
      return h_flex().id(`panel-tab-${entry.id}`).h(24).px(7).gap(5).flex_none().items_center().rounded(6)
        .cursor_pointer().text_size(12).text_color(on ? t.foreground : t.muted)
        .when(on, (el) => el.bg(t.selected))
        .hover((s) => s.bg(on ? t.selected : t.hover))
        .on_click(() => {
          if (!on) run("layout.select", { stack: STACK, child: entry.id });
          if (!shown) run("layout.show", { id: PANEL });
        })
        .child(svg(entry.icon).size(13).flex_none())
        .child(div().child(entry.label));
    };
    return h_flex().size_full().px(6).gap(2).items_center().bg(t.chrome).border_b(1).border_color(t.border)
      .children(PANELS.map(tab));
  }
}
