// The agent panel's header: the task whose terminal fills it, and the way back.
// `oo-tasks` publishes its selection as shared("oo-tasks.selected") = { id, title }.
import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { run, shared, theme } from "herdr";

const FALLBACK = "Agent";

export default class AgentHead extends View {
  // Selecting the Tasks stack child brings back its detail, selection intact.
  back() {
    run("layout.select", { stack: "panel-body", child: "oo-tasks" });
  }

  render() {
    const t = theme();
    const task = shared("oo-tasks.selected");
    const title = typeof task?.title === "string" && task.title ? task.title : FALLBACK;
    return h_flex().id("oo-agent-head").size_full().px(12).gap(8).items_center()
      .bg(t.background).border_b(1).border_color(t.border).text_color(t.foreground).text_size(12)
      .child(h_flex().id("oo-agent-head-back").h(22).flex_none().px(8).rounded(6).cursor_pointer()
        .text_size(11).bg(t.chrome).text_color(t.muted)
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_click(() => this.back())
        .child("← Tasks"))
      .child(div().flex_1().min_w(0).truncate().font_semibold()
        .text_color(task ? t.foreground : t.muted).child(title));
  }
}
