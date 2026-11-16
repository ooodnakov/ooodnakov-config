// Tasks: the folder's task list, written by the `herdr-task` command.
// A task is a title, an optional note and a status; agents add and move them,
// this panel adds one from its header, and rewrites statuses and deletes with
// the command's compare-and-set (the command itself on a remote machine).
// Click a task to read its note; ← goes back to the list.
import { View, div } from "gpui-kit";
import { v_flex, h_flex, TextView, Input, InputState } from "gpui-base";
import { spaces, panes, focused, exec, readTextFile, writeTextFile, watchFolder, terminals, run, theme, home, checking, setShared, notify, playSound, knownAgents } from "herdr";
import { randomBytes } from "crypto";

const POINTER = `${home()}/.config/ooodnakov/herdr-data`;
const DEFAULT_ROOT = `${home()}/.local/share/ooodnakov/herdr`;
const REMOTE_ROOT = 'if [ -r "$HOME/.config/ooodnakov/herdr-data" ]; then cat "$HOME/.config/ooodnakov/herdr-data"; else printf "%s" "${XDG_DATA_HOME:-$HOME/.local/share}/ooodnakov/herdr"; fi';
const CLI = `${home()}/.local/bin/herdr-task`;
const ROOTS = new Map();
const PROBES = new Map();
const ORDER = ["blocked", "doing", "todo", "done"];
const STATUSES = ["todo", "doing", "blocked", "done"];
const TITLES = { blocked: "Blocked", doing: "Doing", todo: "To do", done: "Done" };
const DOTS = { blocked: "blocked", doing: "working", todo: "muted", done: "done" };
const AGENT_COLORS = { working: "working", blocked: "blocked", done: "done", idle: "idle" };
// An agent that reported done or idle on a task still marked doing: offer the
// status change, never make it. No live agent, no chip.
const FINISHED = new Set(["done", "idle"]);

const norm = (path) => String(path).replace(/\\/g, "/").replace(/\/+$/, "");
const pointed = (text) => norm(String(text ?? "").trim());
const textOf = (data) => `${JSON.stringify(data, null, 2)}\n`;

// The agent panel's header reads this: the task whose terminal it can show.
function select(task) {
  setShared("oo-tasks.selected", task ? { id: task.id, title: task.title ?? "" } : null);
}

// The CLI's task ids and stamps: t-<local YYYYMMDD>-<6 hex>, seconds-precision UTC.
function isoNow() {
  return `${new Date().toISOString().slice(0, 19)}Z`;
}

function newId() {
  const now = new Date();
  const day = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, "0")}${String(now.getDate()).padStart(2, "0")}`;
  return `t-${day}-${randomBytes(3).toString("hex")}`;
}

// _herdr_store.slug_for's name rule, for a folder the index does not know yet.
function slugBase(folder) {
  const name = String(folder).split("/").filter(Boolean).pop() ?? "";
  const base = name.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^[-.]+/, "").replace(/[-.]+$/, "").toLowerCase();
  return (base || "root").slice(0, 60);
}

// Each machine keeps its own lists; a space on another machine reads them there.
// The command records the root in `herdr-data`; the mod only reads that file.
async function rootFor(on) {
  if (!on) {
    const text = await readTextFile(POINTER).catch(() => null);
    return pointed(text) || DEFAULT_ROOT;
  }
  if (!ROOTS.has(on)) {
    const probe = await exec("sh", ["-c", REMOTE_ROOT], { on }).catch(() => null);
    ROOTS.set(on, probe?.code === 0 ? pointed(probe.stdout) || null : null);
  }
  return ROOTS.get(on);
}

function here() {
  const space = spaces().find((s) => s.active);
  const f = focused();
  const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
  return { folder: pane?.cwd || f?.cwd || space?.folder, on: space?.machine ?? null, name: space?.name };
}

// A remote machine needs the command and its store before the list means anything;
// one shell per machine answers both, and the local path never probes.
async function probeFor(on) {
  if (!on) return "ok";
  if (!PROBES.has(on)) {
    const result = await exec("sh", ["-c", '(command -v herdr-task >/dev/null 2>&1 || [ -x "$HOME/.local/bin/herdr-task" ]) && ls -d "$HOME/.local/share/ooodnakov/herdr" >/dev/null'], { on }).catch(() => null);
    if (!result) return "unknown";
    // `command -v` fails silently; a missing store fails in `ls`, which writes to stderr.
    PROBES.set(on, result.code === 0 ? "ok" : String(result.stderr ?? "").trim() ? "store" : "task");
  }
  return PROBES.get(on);
}

function age(iso) {
  const then = Date.parse(iso || "");
  if (!then) return "";
  const minutes = Math.max(0, Math.round((Date.now() - then) / 60000));
  if (minutes < 60) return `${minutes}m`;
  if (minutes < 60 * 24) return `${Math.round(minutes / 60)}h`;
  return `${Math.round(minutes / (60 * 24))}d`;
}

function chip(label, action, t, danger = false, active = false, id = null) {
  const element = h_flex().id(id ?? `oo-chip-${String(label).toLowerCase().replace(/[^a-z0-9]+/g, "-")}`)
    .h(22).px(8).rounded(6).flex_none().cursor_pointer().text_size(11).bg(t.chrome)
    .text_color(danger ? t.blocked : active ? t.accent : t.muted)
    .hover((s) => s.bg(t.hover).text_color(danger ? t.blocked : t.foreground))
    .on_click((_event, cx) => action(cx)).child(label);
  return element;
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

function finished(task, agent) {
  if (!agent || agent.root.state !== "live") return false;
  if ((task.status || "todo") !== "doing") return false;
  return FINISHED.has(agent.root.status);
}

export default class Tasks extends View {
  init(_props, cx) {
    this.focus = null;
    this.folder = null;
    this.slug = null;
    this.data = null;
    this.selected = null;
    this.confirm = null;
    this.confirmClear = false;
    this.output = null;
    this.outputFor = null;
    this.outputError = null;
    this.error = null;
    this.warning = null;
    this.warningFor = null;
    // The agents people can start here, loaded once per machine for the START chips.
    this.harnesses = null;
    this.harnessError = null;
    this.loading = false;
    this.token = null;
    this.watch = null;
    this.timer = null;
    // Last status seen per task, so a transition the panel wasn't looking at still notifies.
    this.notified = new Map();
    // Ids this copy changed itself: no toast/sound for your own click.
    this.quiet = new Set();
    this.input = InputState.new({ placeholder: "New task" });
    this.input.on("submit", (_event, cx) => this.create(cx));
    this.message = InputState.new({ placeholder: "Message the agent" });
    this.message.on("submit", (_event, cx) => this.sendMessage(cx));
    this.chatAddress = null;
    this.chatError = null;
    if (checking()) return;
    select(null);
  }

  // Follow the data folder; herdr's watch is local-only, so a remote space and a
  // rejected watch (missing folder, oversized tree) fall back to the timer.
  follow(cx) {
    const token = `${this.on ?? ""}|${this.root}`;
    if (this.token === token) return;
    this.stop();
    this.token = token;
    if (checking() || !this.root) return;
    if (this.on) {
      this.poll(cx);
      return;
    }
    cx.spawn(async (cx) => {
      try {
        while (this.token === token) {
          const watch = watchFolder(this.root);
          this.watch = watch;
          await watch;
          if (this.token !== token) return;
          this.watch = null;
          if (!this.folder || !this.focus) continue;
          await this.read(this.focus, cx);
          if (this.token === token) cx.notify();
        }
      } catch {
        if (this.token !== token) return;
        this.watch = null;
        this.poll(cx);
      }
    });
  }

  stop() {
    this.watch?.cancel();
    this.watch = null;
    this.timer?.cancel();
    this.timer = null;
  }

  poll(cx) {
    if (this.timer) return;
    this.timer = cx.timer.every(5000, (cx) => this.reload(cx));
  }

  // The list follows the focused pane's folder, so the panel always shows where you are.
  ensure(cx) {
    const at = here();
    const key = `${at.folder}|${at.on ?? ""}`;
    if (key === this.focus) return;
    this.focus = key;
    this.stop();
    this.token = null;
    this.folder = null;
    this.root = null;
    this.on = at.on ?? null;
    this.data = null;
    this.selected = null;
    this.confirm = null;
    this.confirmClear = false;
    this.output = null;
    this.outputFor = null;
    this.outputError = null;
    this.error = null;
    select(null);
    this.missing = null;
    // A delete fallback reports from the folder it happened in, not the next one.
    if (this.warningFor !== key) {
      this.warning = null;
      this.warningFor = null;
    }
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
      const [probe, top] = await Promise.all([
        probeFor(at.on),
        exec("git", ["rev-parse", "--show-toplevel"], { cwd: at.folder, on: at.on }).catch(() => null),
      ]);
      const folder = norm(top?.code === 0 && top.stdout.trim() ? top.stdout.trim() : at.folder);
      if (this.focus !== key) return;
      this.root = root;
      this.folder = folder;
      this.missing = probe === "task" ? `herdr-task missing on ${at.on}` : probe === "store" ? "no store yet" : null;
      await this.read(key, cx);
      this.loading = false;
      if (this.focus === key) this.follow(cx);
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

  // Tell the person when a status change lands while they are elsewhere in the
  // window: the toast names the task, the sound matches the state. Seeding the
  // first read is silent, and this copy's own clicks never ring.
  announce(tasks) {
    const next = new Map(tasks.map((task) => [task.id, task.status || "todo"]));
    for (const [id, status] of next) {
      const was = this.notified.get(id);
      if (!was || was === status) continue;
      const mine = this.quiet.delete(id);
      if (mine || (status !== "done" && status !== "blocked")) continue;
      const task = tasks.find((entry) => entry.id === id);
      notify({
        title: status === "done" ? "Task done" : "Task blocked",
        body: task?.title ?? id,
        level: status === "done" ? "info" : "warn",
        timeout: 6000,
      });
      playSound(status);
    }
    this.notified = next;
  }

  async read(key, cx) {
    // Without the command or its store the list would only look empty, so the panel says why.
    if (this.missing) return;
    try {
      const on = this.on;
      const index = JSON.parse((await readTextFile(`${this.root}/index.json`, { on })) || "{}");
      const slug = index?.folders?.[this.folder];
      const text = slug ? await readTextFile(`${this.root}/tasks/${slug}.json`, { on }) : null;
      if (this.focus !== key) return;
      this.slug = slug ?? null;
      const next = text ? JSON.parse(text) : { tasks: [] };
      this.announce(next.tasks ?? []);
      this.data = next;
      if (this.selected && !(this.data.tasks ?? []).some((task) => task.id === this.selected)) {
        this.selected = null;
        select(null);
      }
      this.error = null;
    } catch (error) {
      if (this.focus === key) this.error = String(error);
    }
  }

  // Finished tasks pile up; one click clears the group instead of opening each.
  // Confirmed once (the header chip asks), then one write locally or one `rm`
  // per id on the task's machine, where the command takes its own lock.
  async clearDone(cx) {
    const done = (this.data?.tasks ?? []).filter((task) => (task.status || "todo") === "done");
    const ids = new Set(done.map((task) => task.id));
    this.confirmClear = false;
    if (!ids.size) {
      cx.notify();
      return;
    }
    try {
      if (this.on) {
        for (const id of ids) {
          const result = await exec("hc", ["exec", "--on", this.on, "--", "herdr-task", "rm", id, "--folder", this.folder]);
          if (result.code !== 0) throw new Error(result.stderr || `herdr-task rm failed (${result.code})`);
        }
      } else {
        const path = `${this.root}/tasks/${this.slug}.json`;
        const text = await readTextFile(path);
        const data = text ? JSON.parse(text) : { tasks: [] };
        data.tasks = (data.tasks ?? []).filter((task) => !ids.has(task.id));
        for (const task of data.tasks) {
          if (task.deps?.some((dep) => ids.has(dep))) task.deps = task.deps.filter((dep) => !ids.has(dep));
        }
        await writeTextFile(path, `${JSON.stringify(data, null, 2)}\n`, text);
      }
      if (ids.has(this.selected)) {
        this.selected = null;
        select(null);
      }
      this.error = null;
    } catch (error) {
      this.error = String(error);
    }
    this.confirm = null;
    cx.notify();
  }

  // Delete from the panel through the command, which takes the list's lock, so a
  // click and an agent's edit cannot race. The CAS rewrite below only runs where
  // the command cannot start, and then says why.
  async remove(task, cx) {
    const path = `${this.root}/tasks/${this.slug}.json`;
    try {
      if (this.on) {
        const result = await exec("hc", ["exec", "--on", this.on, "--", "herdr-task", "rm", task.id, "--folder", this.folder]);
        if (result.code !== 0) throw new Error(result.stderr || `herdr-task rm failed (${result.code})`);
        this.warning = null;
        this.warningFor = null;
      } else {
        await this.removeLocal(task, path);
      }
      this.selected = null;
      this.confirm = null;
      this.focus = null;
      this.data = null;
      select(null);
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

  // Which harnesses exist on this task's machine; the START chips offer only those.
  loadHarnesses(cx) {
    this.harnesses = [];
    cx.spawn(async (cx) => {
      try {
        const list = await knownAgents({ on: this.on });
        this.harnesses = list.filter((program) => program.installed && program.key !== "shell");
      } catch (error) {
        this.harnessError = String(error);
      }
      cx.notify();
    });
  }

  // Start a task by hand: the harness opens in a new herdr-core terminal, labelled
  // like `herdr-task spawn` does, so this panel finds it and the status turns doing.
  start(task, program, cx) {
    const prompt = [task.title, (task.note || "").trim()].filter(Boolean).join("\n\n");
    const args = ["spawn", task.id, "--folder", this.folder, "--name", task.title || task.id, "--", ...program.run, prompt];
    cx.spawn(async (cx) => {
      try {
        const result = await exec(this.on ? "herdr-task" : CLI, args, { on: this.on });
        if (result.code !== 0) throw new Error(result.stderr.trim() || `herdr-task spawn failed (${result.code})`);
        // The agent runs as a sub-agent; give it a real pane so you type in its own TUI.
        const address = result.stdout.trim().split(/\s+/)[1];
        // The terminal reaches the window a beat after hc starts it; keep until it exists.
        if (address) {
          let tries = 0;
          const attach = () => {
            if (tries++ > 12 || terminals().some((terminal) => terminal.address === address)) {
              run("terminal.keep", { terminal: address, place: "tab" });
              return;
            }
            cx.timer.after(250, (cx) => { attach(); cx.notify(); });
          };
          attach();
        }
        this.error = null;
        this.focus = null;
        this.data = null;
      } catch (error) {
        this.error = String(error);
      }
      cx.notify();
    });
  }

  // Type into the task's agent without leaving the list: `hc send` pastes the
  // text and presses Enter; the screen is re-read once the agent has had a beat.
  async sendMessage(cx) {
    const address = this.chatAddress;
    const text = this.message.value().trim();
    if (!address || !text) return;
    this.message.set_value("");
    this.chatError = null;
    try {
      const result = await exec("hc", ["send", address, text]);
      if (result.code !== 0) throw new Error(result.stderr.trim() || `hc send failed (${result.code})`);
      cx.timer.after(1500, (cx) => {
        this.outputFor = null;
        this.output = null;
        cx.notify();
      });
    } catch (error) {
      this.chatError = String(error);
    }
    cx.notify();
  }

  // Only a click lands here: the agent's report is a suggestion. Same compare-and-set
  // rewrite as Delete; a remote machine writes its own list under its own lock.
  async markDone(task, cx) {
    const path = `${this.root}/tasks/${this.slug}.json`;
    const stamp = new Date().toISOString().replace(/\.\d+Z$/, "Z");
    this.quiet.add(task.id);
    try {
      if (this.on) {
        const result = await exec("hc", ["exec", "--on", this.on, "--", "herdr-task", "set", task.id, "done", "--folder", this.folder]);
        if (result.code !== 0) throw new Error(result.stderr || `herdr-task set failed (${result.code})`);
        this.focus = null;
        this.data = null;
      } else {
        const text = await readTextFile(path);
        const data = text ? JSON.parse(text) : { tasks: [] };
        const item = (data.tasks ?? []).find((entry) => entry.id === task.id);
        if (!item) throw new Error(`${task.id} is no longer in the list`);
        item.status = "done";
        item.updated = stamp;
        await writeTextFile(path, textOf(data), text);
        this.data = data;
      }
      this.error = null;
    } catch (error) {
      this.error = String(error);
    }
    cx.notify();
  }

  // A list exists only after its first write: the CLI's index names the folder's slug.
  async assignSlug() {
    const path = `${this.root}/index.json`;
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const text = await readTextFile(path);
      const index = text ? JSON.parse(text) : {};
      const folders = index && typeof index.folders === "object" && index.folders ? index.folders : {};
      const known = folders[this.folder];
      if (typeof known === "string" && known) return known;
      const taken = new Set(Object.values(folders).filter((value) => typeof value === "string"));
      const base = slugBase(this.folder);
      let slug = base;
      let number = 1;
      while (taken.has(slug)) {
        number += 1;
        slug = `${base}-${number}`;
      }
      folders[this.folder] = slug;
      try {
        await writeTextFile(path, textOf({ format: 1, folders }), text);
        return slug;
      } catch (error) {
        if (attempt === 2) throw error;
      }
    }
    return null;
  }

  // New task from the header row: the same shape `herdr-task add` writes.
  async create(cx) {
    const title = this.input.value().trim();
    if (!title || !this.root || !this.folder) return;
    const stamp = isoNow();
    const task = { id: newId(), title, note: "", status: "todo", created: stamp, updated: stamp };
    try {
      if (this.on) {
        const result = await exec("hc", ["exec", "--on", this.on, "--", "herdr-task", "add", title, "--folder", this.folder]);
        if (result.code !== 0) throw new Error(result.stderr || `herdr-task add failed (${result.code})`);
      } else {
        const slug = this.slug ?? (await this.assignSlug());
        if (!slug) throw new Error("cannot name this folder's list");
        this.slug = slug;
        const path = `${this.root}/tasks/${slug}.json`;
        const text = await readTextFile(path);
        const data = text ? JSON.parse(text) : { format: 1, folder: this.folder, tasks: [] };
        data.tasks = [...(data.tasks ?? []), task];
        await writeTextFile(path, textOf(data), text);
        this.data = data;
      }
      this.input.set_value("");
      this.error = null;
      if (this.on) this.reload(cx);
    } catch (error) {
      this.error = String(error);
    }
    cx.notify();
  }

  // Status chips: the same compare-and-set as Delete, or `herdr-task set` under its lock.
  async setStatus(task, status, cx) {
    if ((task.status || "todo") === status) return;
    const path = `${this.root}/tasks/${this.slug}.json`;
    try {
      if (this.on) {
        const result = await exec("hc", ["exec", "--on", this.on, "--", "herdr-task", "set", task.id, status, "--folder", this.folder]);
        if (result.code !== 0) throw new Error(result.stderr || `herdr-task set failed (${result.code})`);
        this.reload(cx);
      } else {
        const text = await readTextFile(path);
        const data = text ? JSON.parse(text) : null;
        const item = data?.tasks?.find((entry) => entry.id === task.id);
        if (!item) throw new Error(`${path} no longer has ${task.id}`);
        item.status = status;
        item.updated = isoNow();
        await writeTextFile(path, textOf(data), text);
        this.data = data;
      }
      this.error = null;
    } catch (error) {
      this.error = String(error);
    }
    cx.notify();
  }

  async removeLocal(task, path) {
    const argv = ["rm", task.id, "--folder", this.folder];
    const failures = [];
    let result = null;
    try {
      result = await exec(CLI, argv);
    } catch (error) {
      failures.push(String(error));
      // An extensionless script cannot start directly on Windows: hand it to python.
      try {
        result = await exec("python3", [CLI, ...argv]);
      } catch (error) {
        failures.push(String(error));
      }
    }
    if (result) {
      if (result.code !== 0) throw new Error(result.stderr.trim() || `herdr-task rm failed (${result.code})`);
      this.warning = null;
      this.warningFor = null;
      return;
    }
    const text = await readTextFile(path);
    const data = text ? JSON.parse(text) : { tasks: [] };
    data.tasks = (data.tasks ?? []).filter((item) => item.id !== task.id);
    for (const item of data.tasks) {
      if (item.deps?.includes(task.id)) item.deps = item.deps.filter((dep) => dep !== task.id);
    }
    await writeTextFile(path, `${JSON.stringify(data, null, 2)}\n`, text);
    this.warningFor = this.focus;
    this.warning = `herdr-task could not run (${failures.join("; ")}); removed the file directly`;
  }

  rows(tasks, t, all, cx) {
    const out = [];
    for (const status of ORDER) {
      const group = tasks.filter((task) => (task.status || "todo") === status);
      if (!group.length) continue;
      out.push(h_flex().id(`oo-tasks-group-${status}`).h(26).flex_none().px(12).items_center().gap(7)
        .child(div().text_size(11).font_semibold().text_color(t.dim).child(TITLES[status].toUpperCase()))
        .child(div().text_size(11).text_color(t.dim).child(String(group.length)))
        .when(status === "done", (row) => row
          .child(div().flex_1())
          .when(!this.confirmClear, (r) => r
            .child(chip("Clear done", (cx) => { this.confirmClear = true; cx.notify(); }, t, false, false, "oo-done-clear")))
          .when(this.confirmClear, (r) => r
            .child(div().text_size(11).text_color(t.dim).child(`Delete ${group.length}?`))
            .child(chip("Delete", (cx) => this.clearDone(cx), t, true, false, "oo-done-delete"))
            .child(chip("Cancel", (cx) => { this.confirmClear = false; cx.notify(); }, t, false, false, "oo-done-cancel")))));
      for (const task of group) {
        const agent = agentFor(task, this.slug, all);
        const waiting = (task.deps ?? []).filter((id) => (tasks.find((entry) => entry.id === id)?.status || "todo") !== "done").length;
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
            select(task);
            cx.notify();
          })
          .child(div().w(7).h(7).flex_none().rounded(4).bg(color))
          .child(div().flex_1().min_w(0).truncate().text_color(status === "done" ? t.muted : t.foreground).child(task.title ?? ""))
          .when(waiting > 0, (el) => el.child(div().text_size(11).text_color(t.blocked).child(`after ${waiting}`)))
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
          .child(chip("Read", (cx) => { this.outputFor = null; this.output = null; cx.notify(); }, t)))
        .child(div().rounded(8).bg(t.surface).p(8).text_size(12).text_color(t.muted)
          .when(Boolean(this.output), (el) => el.child(TextView.markdown("oo-task-output", this.output).selectable(true)))
          .when(!this.output, (el) => el.child(div().text_size(11).child(this.outputError ? "" : "Reading…"))))
      : null;
    const deps = (task.deps ?? [])
      .map((id) => (this.data?.tasks ?? []).find((entry) => entry.id === id))
      .filter(Boolean);
    const depsBlock = deps.length
      ? v_flex().gap(6).rounded(8).p(8).bg(t.raised)
        .child(div().text_size(11).font_semibold().text_color(t.dim).child("DEPENDS ON"))
        .children(deps.map((dep) => h_flex().id(`oo-task-dep-${dep.id}`).gap(8).items_center().cursor_pointer()
          .hover((s) => s.bg(t.hover))
          .on_click((_event, cx) => {
            this.selected = dep.id;
            this.confirm = null;
            this.output = null; this.outputFor = null; this.outputError = null;
            select(dep);
            cx.notify();
          })
          .child(div().w(7).h(7).flex_none().rounded(4).bg(t[DOTS[dep.status || "todo"]]))
          .child(div().flex_1().min_w(0).truncate().text_size(12).child(dep.title ?? ""))
          .child(div().text_size(11).text_color(dep.status === "done" ? t.dim : t.muted).child(dep.status ?? "todo"))))
      : null;
    this.chatAddress = address;
    if (address) this.loadOutput(address, cx);
    if (!address && this.harnesses === null && !this.harnessError) this.loadHarnesses(cx);
    return v_flex().size_full().min_h(0)
      .child(h_flex().h(36).flex_none().px(10).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().id("oo-task-back").w(20).cursor_pointer().text_color(t.muted)
          .on_click((_event, cx) => {
            this.selected = null; this.confirm = null;
            this.output = null; this.outputFor = null; this.outputError = null;
            select(null);
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
                select(task);
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
        .when(Boolean(depsBlock), (el) => el.child(depsBlock))
        .when(Boolean(outputBlock), (el) => el.child(outputBlock))
        .when(Boolean(address), (el) => el.child(v_flex().gap(4)
          .child(h_flex().gap(6).items_center()
            .child(div().flex_1().min_w(0).h(28).px(8).flex().items_center().rounded(7).border_1().border_color(t.border).bg(t.surface)
              .on_mouse_down("left", (_event, cx) => cx.stop_propagation())
              .child(Input.new(this.message).h_full().text_size(12).text_color(t.foreground)))
            .child(chip("Send", (cx) => this.sendMessage(cx), t, false, false, "oo-task-send")))
          .when(Boolean(this.chatError), (row) => row.child(div().text_size(11).text_color(t.blocked).child(this.chatError)))))
        .child(div().text_size(11).text_color(t.dim).child(`${task.id} · updated ${age(task.updated)} ago`))
        .when(Boolean(this.error), (el) => el.child(div().text_size(11).text_color(t.muted).child(this.error)))
        .child(h_flex().gap(6).items_center().flex_wrap()
          .child(div().text_size(11).font_semibold().text_color(t.dim).child("STATUS"))
          .children(STATUSES.map((status) => chip(TITLES[status], (cx) => this.setStatus(task, status, cx), t, false, (task.status || "todo") === status))))
        .when(!address && Boolean(this.harnesses?.length), (el) => el.child(h_flex().gap(6).items_center().flex_wrap()
          .child(div().text_size(11).font_semibold().text_color(t.dim).child("START"))
          .children(this.harnesses.map((program, index) => chip(program.name, (cx) => this.start(task, program, cx), t, false, false, `oo-start-${index}`)))))
        .when(!address && Boolean(this.harnessError), (el) => el.child(div().text_size(11).text_color(t.muted).child(this.harnessError)))
        .child(h_flex().gap(6).items_center()
          .when(finished(task, agent), (row) => row
            .child(chip("Mark done", (cx) => this.markDone(task, cx), t)))
          .when(this.confirm !== task.id, (row) => row
            .child(chip("Delete", (cx) => { this.confirm = task.id; cx.notify(); }, t)))
          .when(this.confirm === task.id, (row) => row
            .child(div().text_size(11).text_color(t.dim).child("Delete this task?"))
            .child(chip("Delete", (cx) => this.remove(task, cx), t, true))
            .child(chip("Cancel", (cx) => { this.confirm = null; cx.notify(); }, t)))
          .when(Boolean(this.error), (row) => row
            .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.blocked).child(this.error)))));
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
        .child(h_flex().h(34).flex_none().px(10).gap(6).items_center().border_b(1).border_color(t.border)
          .child(div().flex_1().min_w(0).h(26).px(8).flex().items_center().rounded(7).border_1().border_color(t.border)
            .bg(t.background).cursor_text().on_mouse_down("left", (_event, cx) => cx.stop_propagation())
            .child(Input.new(this.input).h_full().text_size(12).text_color(t.foreground)))
          .child(chip("Add", (cx) => this.create(cx), t)))
        .child(v_flex().id("oo-tasks-list").flex_1().min_h(0).overflow_y_scrollbar().py(4)
          .children(this.rows(tasks, t, all, cx))
          .when(!tasks.length && !this.error && !this.missing, (el) => el.child(div().p(12).gap(4).text_size(12).text_color(t.dim)
            .child(this.loading ? "Loading…" : "No tasks")
            .child(div().text_size(11).child('Agents add them with herdr-task add "…"'))))
          .when(Boolean(this.missing), (el) => el.child(div().p(12).text_size(12).text_color(t.muted).child(this.missing)))
          .when(Boolean(this.error), (el) => el.child(div().p(12).text_size(12).text_color(t.muted).child(this.error)))
          .when(Boolean(this.warning), (el) => el.child(div().px(12).py(6).text_size(11).text_color(t.dim).child(this.warning))))
        .child(h_flex().h(26).flex_none().px(14).gap(10).items_center().border_t(1).border_color(t.border)
          .children(counts.map((count) => div().text_size(11).text_color(t.dim).child(count)))))
      .when(Boolean(selected), (el) => el.child(this.detail(selected, t, agentFor(selected, this.slug, all), cx)));
  }
}
