// Artifacts: reports and notes an agent left for you, written by `herdr-artifact`.
// One list per folder in <root>/artifacts, where the root is named by
// ~/.config/ooodnakov/herdr-data (or ~/.local/share/ooodnakov/herdr before that);
// click one to read its latest version, ← goes back. The panel only reads.
import { View, div } from "gpui-kit";
import { v_flex, h_flex, TextView } from "gpui-base";
import { spaces, panes, focused, exec, readTextFile, watchFolder, theme, home, checking } from "herdr";

const POINTER = `${home()}/.config/ooodnakov/herdr-data`;
const DEFAULT_ROOT = `${home()}/.local/share/ooodnakov/herdr`;
const REMOTE_ROOT = 'if [ -r "$HOME/.config/ooodnakov/herdr-data" ]; then cat "$HOME/.config/ooodnakov/herdr-data"; else printf "%s" "${XDG_DATA_HOME:-$HOME/.local/share}/ooodnakov/herdr"; fi';
const ROOTS = new Map();
const PROBES = new Map();
const norm = (path) => String(path).replace(/\\/g, "/").replace(/\/+$/, "");
const pointed = (text) => norm(String(text ?? "").trim());

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
  return { folder: pane?.cwd || f?.cwd || space?.folder, on: space?.machine ?? null };
}

// A remote machine needs the command and its store before the list means anything;
// one shell per machine answers both, and the local path never probes.
async function probeFor(on) {
  if (!on) return "ok";
  if (!PROBES.has(on)) {
    const result = await exec("sh", ["-c", "command -v herdr-task >/dev/null && ls -d ~/.local/share/ooodnakov/herdr"], { on }).catch(() => null);
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

export default class Artifacts extends View {
  init(_props, cx) {
    this.focus = null;
    this.folder = null;
    this.data = null;
    this.selected = null;
    this.content = null;
    this.error = null;
    this.loading = false;
    this.token = null;
    this.watch = null;
    this.timer = null;
    if (checking()) return;
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
    this.content = null;
    this.error = null;
    this.missing = null;
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

  async read(key, cx) {
    // Without the command or its store the list would only look empty, so the panel says why.
    if (this.missing) return;
    try {
      const on = this.on;
      const index = JSON.parse((await readTextFile(`${this.root}/index.json`, { on })) || "{}");
      const slug = index?.folders?.[this.folder];
      const text = slug ? await readTextFile(`${this.root}/artifacts/${slug}.json`, { on }) : null;
      if (this.focus !== key) return;
      this.data = text ? JSON.parse(text) : { artifacts: [] };
      this.error = null;
    } catch (error) {
      if (this.focus === key) this.error = String(error);
    }
  }

  latest(artifact) {
    return artifact.versions?.[artifact.versions.length - 1] ?? null;
  }

  open(artifact, cx) {
    const version = this.latest(artifact);
    this.selected = artifact.id;
    this.content = null;
    if (!version) return;
    const key = this.focus;
    cx.spawn(async (cx) => {
      const text = await readTextFile(`${this.root}/${version.path}`, { on: this.on }).catch(() => null);
      if (this.focus !== key || this.selected !== artifact.id) return;
      this.content = text ?? "(cannot read this version)";
      cx.notify();
    });
  }

  rows(artifacts, t) {
    return artifacts.map((artifact) => {
      const version = this.latest(artifact);
      return h_flex().id(`oo-artifact-${artifact.id}`).h(34).flex_none().mx(6).px(6).gap(8).items_center().rounded(7)
        .cursor_pointer().hover((s) => s.bg(t.hover))
        .on_click((_event, cx) => this.open(artifact, cx))
        .child(div().w(7).h(7).flex_none().rounded(4).bg(t.accent))
        .child(div().flex_1().min_w(0).truncate().child(artifact.title ?? ""))
        .child(div().text_size(11).text_color(t.dim).child(`v${version?.n ?? 0}`))
        .child(div().text_size(11).text_color(t.dim).child(age(version?.at)));
    });
  }

  detail(artifact, t) {
    return v_flex().size_full().min_h(0)
      .child(h_flex().h(36).flex_none().px(10).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().id("oo-artifact-back").w(20).cursor_pointer().text_color(t.muted)
          .on_click((_event, cx) => { this.selected = null; this.content = null; cx.notify(); }).child("←"))
        .child(div().flex_1().min_w(0).truncate().font_semibold().child(artifact.title ?? ""))
        .child(div().text_size(11).text_color(t.dim).child(`v${this.latest(artifact)?.n ?? 0}`)))
      .child(v_flex().flex_1().min_h(0).overflow_y_scrollbar().p(12)
        .when(this.content === null, (el) => el.child(div().text_size(12).text_color(t.dim).child("Loading…")))
        .when(this.content !== null, (el) => el.child(TextView.markdown("oo-artifact-body", this.content).selectable(true))));
  }

  render(cx) {
    this.ensure(cx);
    const t = theme();
    const artifacts = this.data?.artifacts ?? [];
    const selected = artifacts.find((artifact) => artifact.id === this.selected);
    return v_flex().id("oo-artifacts").size_full().min_h(0).rounded(10).overflow_hidden()
      .bg(t.background).border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .when(!selected, (el) => el
        .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
          .child(div().font_semibold().child("Artifacts"))
          .child(div().flex_1())
          .child(div().text_size(11).text_color(t.dim).child(this.folder?.split("/").pop() ?? "")))
        .child(v_flex().id("oo-artifacts-list").flex_1().min_h(0).overflow_y_scrollbar().py(4)
          .children(this.rows(artifacts, t))
          .when(!artifacts.length && !this.error && !this.missing, (el) => el.child(div().p(12).gap(4).text_size(12).text_color(t.dim)
            .child(this.loading ? "Loading…" : "No artifacts")
            .child(div().text_size(11).child('Agents add them with herdr-artifact add "…" --from report.md'))))
          .when(Boolean(this.missing), (el) => el.child(div().p(12).text_size(12).text_color(t.muted).child(this.missing)))
          .when(Boolean(this.error), (el) => el.child(div().p(12).text_size(12).text_color(t.muted).child(this.error)))))
      .when(Boolean(selected), (el) => el.child(this.detail(selected, t)));
  }
}
