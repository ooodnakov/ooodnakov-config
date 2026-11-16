// Tasks: the folder's task list, written by the `herdr-task` command.
// A task is a title, an optional note and a status; agents add and move them,
// this panel only reads ~/.local/share/ooodnakov/herdr/tasks/<slug>.json.
// Click a task to read its note; ← goes back to the list.
import { View, div } from "gpui-kit";
import { v_flex, h_flex, TextView } from "gpui-base";
import { spaces, panes, focused, exec, readTextFile, writeTextFile, terminals, run, theme, home, checking } from "herdr";

const ROOT = `${home()}/.local/share/ooodnakov/herdr`;
const ROOTS = new Map();
const ORDER = ["blocked", "doing", "todo", "done"];
const TITLES = { blocked: "Blocked", doing: "Doing", todo: "To do", done: "Done" };
const DOTS = { blocked: "blocked", doing: "working", todo: "muted", done: "done" };
const AGENT_COLORS = { working: "working", blocked: "blocked", done: "done", idle: "idle" };

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

function chip(label, action, t, danger = false) {
  return h_flex().h(22).px(8).rounded(6).flex_none().cursor_pointer().text_size(11).bg(t.chrome)
    .text_color(danger ? t.blocked : t.muted)
    .hover((s) => s.bg(t.hover).text_color(danger ? t.blocked : t.foreground))
    .on_click(action).child(label);
}

// The terminal a task's agent runs in: the one carrying the task's
// `herdr.task=<slug>#<id>` label (or the address bound to the task), plus the
// sub-agents it started (their `parent` is that terminal, recursively).
function agentFor(task, slug, all) {
  const key = slug && task?.id ? `${slug}#${task.id}` : null;
  const root = all.find((terminal) => (key && terminal.labels?.["herdr.task"] === key) || (task?.terminal && terminal.address === task.terminal));
  if (!root) return null;
  const children = new Set();
  const collect = (address) => {
    for (const terminal of all) {
      if (terminal.parent === address && !children.has(terminal.address)) {
        children.add(terminal.address);
        collect(terminal.address);
      }
    }
  };
  collect(root.address);
  return { root, children: children.size };
}

export default class Tasks extends View {
  init(_props, cx) {
    this.focus = null;
    this.folder = null;
    this.slug = null;
    this.data = null;
    this.selected = null;
    this.confirm = null;
    this.output = null;
    this.outputFor = null;
    this.outputError = null;
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
    this.confirm = null;
    this.output = null;
    this.outputFor = null;
    this.outputError = null;
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
      this.slug = slug ?? null;
      this.data = text ? JSON.parse(text) : { tasks: [] };
      this.error = null;
    } catch (error) {
      if (this.focus === key) this.error = String(error);
    }
  }

  // Delete from the panel: the same file the CLI writes, replaced only if nothing
  // else touched it first. On a remote machine the command does it under its own lock.
  async remove(task, cx) {
    const path = `${this.root}/tasks/${this.slug}.json`;
    try {
      if (this.on) {
        const result = await exec("hc", ["exec", "--on", this.on, "--", "herdr-task", "rm", task.id, "--folder", this.folder]);
        if (result.code !== 0) throw new Error(result.stderr || `herdr-task rm failed (${result.code})`);
      } else {
        const text = await readTextFile(path);
        const data = text ? JSON.parse(text) : { tasks: [] };
        data.tasks = (data.tasks ?? []).filter((item) => item.id !== task.id);
        await writeTextFile(path, `${JSON.stringify(data, null, 2)}\n`, text);
      }
      this.selected = null;
      this.confirm = null;
      this.focus = null;
      this.data = null;
    } catch (error) {
      this.error = String(error);
      this.confirm = null;
    }
    cx.notify();
  }

  // The task's agent screen, live or after it ended: `hc read` prints the terminal's
  // text (a finished terminal stays readable until the core drops it). Read once per
  // selection; the Read chip forces another.
  loadOutput(address, cx) {
    if (!address || this.outputFor === address) return;
    this.outputFor = address;
    this.output = null;
    this.outputError = null;
    const candidates = [
      "hc",
      `${home()}/.local/bin/hc`,
      "/opt/homebrew/bin/hc",
      "/usr/local/bin/hc",
      `${home()}/AppData/Local/Programs/herdr-core/hc.exe`,
    ];
    cx.spawn(async (cx) => {
      let result = null, failure = null;
      for (const hc of candidates) {
        try {
          result = await exec(hc, ["read", address]);
          break;
        } catch (error) {
          failure = String(error);
        }
      }
      if (this.outputFor !== address) return;
      if (!result || (result.code !== 0 && !result.stdout.trim())) {
        this.outputError = (result?.stderr || failure || "the terminal is gone").trim().split("\n").pop();
        cx.notify();
        return;
      }
      const text = result.stdout
        .replace(/\u001b\[[0-9;?]*[a-zA-Z]/g, "")
        .replace(/\r/g, "")
        .split("\n")
        .map((line) => (line.length > 400 ? `${line.slice(0, 400)}…` : line));
      while (text.length && !text[text.length - 1].trim()) text.pop();
      this.output = text.slice(-120).join("\n");
      cx.notify();
    });
  }

  rows(tasks, t, all) {
    const out = [];
    for (const status of ORDER) {
      const group = tasks.filter((task) => (task.status || "todo") === status);
      if (!group.length) continue;
      out.push(h_flex().id(`oo-tasks-group-${status}`).h(26).flex_none().px(12).items_center().gap(7)
        .child(div().text_size(11).font_semibold().text_color(t.dim).child(TITLES[status].toUpperCase()))
        .child(div().text_size(11).text_color(t.dim).child(String(group.length))));
      for (const task of group) {
        const agent = agentFor(task, this.slug, all);
        const color = agent
          ? AGENT_COLORS[agent.root.status]
            ? t[AGENT_COLORS[agent.root.status]]
            : agent.root.state === "live" ? t.accent : t.dim
          : t[DOTS[status]];
        out.push(h_flex().id(`oo-task-${task.id}`).h(30).flex_none().mx(6).px(6).gap(8).items_center().rounded(7)
          .cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click((_event, cx) => {
            this.selected = task.id; this.confirm = null;
            this.output = null; this.outputFor = null; this.outputError = null;
            cx.notify();
          })
          .child(div().w(7).h(7).flex_none().rounded(4).bg(color))
          .child(div().flex_1().min_w(0).truncate().text_color(status === "done" ? t.muted : t.foreground).child(task.title ?? ""))
          .when(Boolean(agent?.children), (el) => el.child(div().text_size(11).text_color(t.dim).child(`+${agent.children}`)))
          .child(div().text_size(11).text_color(agent ? color : t.dim)
            .child(agent ? agent.root.status ?? agent.root.state ?? "live" : age(task.updated))));
      }
    }
    return out;
  }

  detail(task, t, agent, cx) {
    const note = (task.note || "").trim();
    const address = agent?.root.address ?? task.terminal ?? null;
    const outputBlock = address
      ? v_flex().gap(4)
        .child(h_flex().gap(8).items_center()
          .child(div().text_size(11).font_semibold().text_color(t.dim).child("OUTPUT"))
          .when(Boolean(this.outputError), (row) => row.child(div().text_size(11).text_color(t.blocked).child(this.outputError)))
          .child(div().flex_1())
          .child(chip("Read", () => { this.outputFor = null; this.output = null; cx.notify(); }, t)))
        .child(div().rounded(8).bg(t.surface).p(8).text_size(12).text_color(t.muted)
          .when(Boolean(this.output), (el) => el.child(TextView.markdown("oo-task-output", this.output).selectable(true)))
          .when(!this.output, (el) => el.child(div().text_size(11).child(this.outputError ? "" : "Reading…"))))
      : null;
    if (address) this.loadOutput(address, cx);
    return v_flex().size_full().min_h(0)
      .child(h_flex().h(36).flex_none().px(10).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().id("oo-task-back").w(20).cursor_pointer().text_color(t.muted)
          .on_click((_event, cx) => {
            this.selected = null; this.confirm = null;
            this.output = null; this.outputFor = null; this.outputError = null;
            cx.notify();
          }).child("←"))
        .child(div().flex_1().min_w(0).truncate().font_semibold().child(task.title ?? ""))
        .child(div().text_size(11).text_color(t.dim).child(task.status ?? "todo")))
      .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar().p(12).gap(10)
        .when(Boolean(note), (el) => el.child(TextView.markdown("oo-task-note", note).selectable(true)))
        .when(!note, (el) => el.child(div().text_size(12).text_color(t.dim).child("No note")))
        .when(Boolean(agent), (el) => el.child(v_flex().gap(6).rounded(8).p(8).bg(t.raised)
          .child(h_flex().gap(8).items_center()
            .child(div().text_size(11).font_semibold().text_color(t.dim).child("AGENT"))
            .child(div().text_size(12).child(`${agent.root.address} · ${agent.root.status ?? agent.root.state ?? "live"}`))
            .when(Boolean(agent.children), (row) => row.child(div().text_size(11).text_color(t.dim)
              .child(`+${agent.children} sub-agent${agent.children === 1 ? "" : "s"}`)))
            .child(div().flex_1())
            .when(agent.root.state === "live", (row) => row
              .child(chip("Panel", () => {
                if (!agent.root.status) {
                  // No status report: the agent block can't show it, so peek instead.
                  run("terminal.peek", { terminal: agent.root.address });
                  return;
                }
                // Show the block first: a stack child starts the first time it shows.
                run("layout.select", { stack: "panel-body", child: "oo-agent" });
                run("layout.show", { id: "panel" });
                run("agent.focus", { terminal: agent.root.address });
              }, t))
              .child(chip("Pane", () => run("terminal.keep", { terminal: agent.root.address }), t))
              .child(chip("Stop", () => run("terminal.kill", { terminal: agent.root.address }), t))))))
        .when(Boolean(outputBlock), (el) => el.child(outputBlock))
        .child(div().text_size(11).text_color(t.dim).child(`${task.id} · updated ${age(task.updated)} ago`))
        .child(h_flex().gap(6).items_center()
          .when(this.confirm !== task.id, (row) => row
            .child(chip("Delete", () => { this.confirm = task.id; cx.notify(); }, t)))
          .when(this.confirm === task.id, (row) => row
            .child(div().text_size(11).text_color(t.dim).child("Delete this task?"))
            .child(chip("Delete", () => this.remove(task, cx), t, true))
            .child(chip("Cancel", () => { this.confirm = null; cx.notify(); }, t)))));
  }

  render(cx) {
    this.ensure(cx);
    const t = theme();
    const tasks = this.data?.tasks ?? [];
    const all = terminals();
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
          .children(this.rows(tasks, t, all))
          .when(!tasks.length && !this.error, (el) => el.child(div().p(12).gap(4).text_size(12).text_color(t.dim)
            .child(this.loading ? "Loading…" : "No tasks")
            .child(div().text_size(11).child('Agents add them with herdr-task add "…"'))))
          .when(Boolean(this.error), (el) => el.child(div().p(12).text_size(12).text_color(t.muted).child(this.error))))
        .child(h_flex().h(26).flex_none().px(14).gap(10).items_center().border_t(1).border_color(t.border)
          .children(counts.map((count) => div().text_size(11).text_color(t.dim).child(count)))))
      .when(Boolean(selected), (el) => el.child(this.detail(selected, t, agentFor(selected, this.slug, all), cx)));
  }
}
