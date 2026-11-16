// Tasks: the folder's task list, written by the `herdr-task` command.
// A task is a title, an optional note and a status; agents add and move them,
// this panel only reads ~/.local/share/ooodnakov/herdr/tasks/<slug>.json.
// Click a task to read its note; ← goes back to the list.
import { View, div } from "gpui-kit";
import { v_flex, h_flex, TextView } from "gpui-base";
import { spaces, panes, focused, exec, readTextFile, theme, home, checking } from "herdr";

const ROOT = `${home()}/.local/share/ooodnakov/herdr`;
const ROOTS = new Map();
const ORDER = ["blocked", "doing", "todo", "done"];
const TITLES = { blocked: "Blocked", doing: "Doing", todo: "To do", done: "Done" };
const DOTS = { blocked: "blocked", doing: "working", todo: "muted", done: "done" };

const norm = (path) => String(path).replace(/\\/g, "/").replace(/\/+$/, "");

// Each machine keeps its own lists; a space on another machine reads them there.
async function rootFor(on) {
  if (!on) return ROOT;
  if (!ROOTS.has(on)) {
    const homeDir = await exec("sh", ["-c", 'printf %s "$HOME"'], { on }).catch(() => null);
    const path = homeDir?.code === 0 ? homeDir.stdout.trim() : "";
    ROOTS.set(on, path ? `${path}/.local/share/ooodnakov/herdr` : null);
  }
  return ROOTS.get(on);
}

function here() {
  const space = spaces().find((s) => s.active);
  const f = focused();
  const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
  return { folder: pane?.cwd || f?.cwd || space?.folder, on: space?.machine ?? null, name: space?.name };
}

function age(iso) {
  const then = Date.parse(iso || "");
  if (!then) return "";
  const minutes = Math.max(0, Math.round((Date.now() - then) / 60000));
  if (minutes < 60) return `${minutes}m`;
  if (minutes < 60 * 24) return `${Math.round(minutes / 60)}h`;
  return `${Math.round(minutes / (60 * 24))}d`;
}

export default class Tasks extends View {
  init(_props, cx) {
    this.focus = null;
    this.folder = null;
    this.data = null;
    this.selected = null;
    this.error = null;
    this.loading = false;
    if (checking()) return;
    cx.timer.every(5000, (cx) => this.reload(cx));
  }

  // The list follows the focused pane's folder, so the panel always shows where you are.
  ensure(cx) {
    const at = here();
    const key = `${at.folder}|${at.on ?? ""}`;
    if (key === this.focus) return;
    this.focus = key;
    this.folder = null;
    this.root = null;
    this.on = at.on ?? null;
    this.data = null;
    this.selected = null;
    this.error = null;
    if (!at.folder) {
      this.error = "No folder";
      return;
    }
    this.loading = true;
    cx.spawn(async (cx) => {
      const root = await rootFor(at.on);
      if (!root) {
        if (this.focus === key) { this.error = `Cannot find this machine's home (${at.on})`; this.loading = false; }
        cx.notify();
        return;
      }
      const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd: at.folder, on: at.on }).catch(() => null);
      const folder = norm(top?.code === 0 && top.stdout.trim() ? top.stdout.trim() : at.folder);
      if (this.focus !== key) return;
      this.root = root;
      this.folder = folder;
      await this.read(key, cx);
      this.loading = false;
      cx.notify();
    });
  }

  reload(cx) {
    if (!this.folder) {
      this.focus = null;
      cx.notify();
      return;
    }
    cx.spawn(async (cx) => {
      await this.read(this.focus, cx);
      cx.notify();
    });
  }

  async read(key, cx) {
    try {
      const on = this.on;
      const index = JSON.parse((await readTextFile(`${this.root}/index.json`, { on })) || "{}");
      const slug = index?.folders?.[this.folder];
      const text = slug ? await readTextFile(`${this.root}/tasks/${slug}.json`, { on }) : null;
      if (this.focus !== key) return;
      this.data = text ? JSON.parse(text) : { tasks: [] };
      this.error = null;
    } catch (error) {
      if (this.focus === key) this.error = String(error);
    }
  }

  rows(tasks, t) {
    const out = [];
    for (const status of ORDER) {
      const group = tasks.filter((task) => (task.status || "todo") === status);
      if (!group.length) continue;
      out.push(h_flex().id(`oo-tasks-group-${status}`).h(26).flex_none().px(12).items_center().gap(7)
        .child(div().text_size(11).font_semibold().text_color(t.dim).child(TITLES[status].toUpperCase()))
        .child(div().text_size(11).text_color(t.dim).child(String(group.length))));
      for (const task of group) {
        out.push(h_flex().id(`oo-task-${task.id}`).h(30).flex_none().mx(6).px(6).gap(8).items_center().rounded(7)
          .cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click((_event, cx) => { this.selected = task.id; cx.notify(); })
          .child(div().w(7).h(7).flex_none().rounded(4).bg(t[DOTS[status]]))
          .child(div().flex_1().min_w(0).truncate().text_color(status === "done" ? t.muted : t.foreground).child(task.title ?? ""))
          .child(div().text_size(11).text_color(t.dim).child(age(task.updated))));
      }
    }
    return out;
  }

  detail(task, t) {
    const note = (task.note || "").trim();
    return v_flex().size_full().min_h(0)
      .child(h_flex().h(36).flex_none().px(10).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().id("oo-task-back").w(20).cursor_pointer().text_color(t.muted)
          .on_click((_event, cx) => { this.selected = null; cx.notify(); }).child("←"))
        .child(div().flex_1().min_w(0).truncate().font_semibold().child(task.title ?? ""))
        .child(div().text_size(11).text_color(t.dim).child(task.status ?? "todo")))
      .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar().p(12).gap(10)
        .when(Boolean(note), (el) => el.child(TextView.markdown("oo-task-note", note).selectable(true)))
        .when(!note, (el) => el.child(div().text_size(12).text_color(t.dim).child("No note")))
        .child(div().text_size(11).text_color(t.dim).child(`${task.id} · updated ${age(task.updated)} ago`)));
  }

  render(cx) {
    this.ensure(cx);
    const t = theme();
    const tasks = this.data?.tasks ?? [];
    const selected = tasks.find((task) => task.id === this.selected);
    const counts = ORDER.map((status) => `${status} ${tasks.filter((task) => (task.status || "todo") === status).length}`);
    return v_flex().id("oo-tasks").size_full().min_h(0).rounded(10).overflow_hidden()
      .bg(t.background).border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .when(!selected, (el) => el
        .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
          .child(div().font_semibold().child("Tasks"))
          .child(div().flex_1())
          .child(div().text_size(11).text_color(t.dim).child(this.folder?.split("/").pop() ?? "")))
        .child(v_flex().id("oo-tasks-list").flex_1().min_h(0).overflow_y_scrollbar().py(4)
          .children(this.rows(tasks, t))
          .when(!tasks.length && !this.error, (el) => el.child(div().p(12).gap(4).text_size(12).text_color(t.dim)
            .child(this.loading ? "Loading…" : "No tasks")
            .child(div().text_size(11).child('Agents add them with herdr-task add "…"'))))
          .when(Boolean(this.error), (el) => el.child(div().p(12).text_size(12).text_color(t.muted).child(this.error))))
        .child(h_flex().h(26).flex_none().px(14).gap(10).items_center().border_t(1).border_color(t.border)
          .children(counts.map((count) => div().text_size(11).text_color(t.dim).child(count)))))
      .when(Boolean(selected), (el) => el.child(this.detail(selected, t)));
  }
}
