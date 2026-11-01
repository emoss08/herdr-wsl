// WSL: spaces in Linux, through WSL 2.
//
// The WSL distro is a Herdr machine (named `wsl` by default) reached over ssh:
// setup.ps1 puts an sshd on 127.0.0.1 inside the distro, a key and a `Host wsl`
// entry on Windows, and runs `hc machine add`. Spaces made on it run their shell,
// git and agents in Linux, and Herdr follows their Linux folders.
//
// This mod keeps the distro running (WSL stops an idle distro, and the machine with
// it), shows whether the machine is connected, and opens new spaces there
// (`wsl.new-space`, the + button). mods/wsl/config.json, written by setup.ps1,
// names the machine and the distro when they aren't the defaults.
import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { appHome, exec, hc, machines, nextCommand, readTextFile, run, terminals, theme } from "herdr";

const KEEPALIVE = "wsl-keepalive"; // hidden local terminal holding a wsl.exe session open

const STATE = {
  ready: { word: "connected", color: (t) => t.ansi2 },
  loading: { word: "connecting", color: (t) => t.ansi3 },
  unavailable: { word: "offline", color: (t) => t.blocked },
  missing: { word: "not set up: run setup.ps1", color: (t) => t.dim },
};

// WSL's default distro: the `*` row of `wsl -l -v`. wsl.exe writes UTF-16, hence the NULs.
async function defaultDistro() {
  try {
    const r = await exec("wsl.exe", ["-l", "-v"]);
    const row = r.stdout.replace(/[\u0000﻿]/g, "").split(/\r?\n/).find((l) => l.trim().startsWith("*"));
    return row?.trim().slice(1).trim().split(/\s+/)[0] || null;
  } catch { return null; }
}

export default class Wsl extends View {
  init(_props, cx) {
    this.width = 240;
    this.machine = "wsl";
    this.distro = null; // null: WSL's default distro
    cx.spawn(async (cx) => {
      try {
        const cfg = JSON.parse((await readTextFile(`${appHome()}/mods/wsl/config.json`)) ?? "{}");
        this.machine = cfg.machine || this.machine;
        this.distro = cfg.distro || null;
      } catch { /* defaults */ }
      this.distro ??= await defaultDistro();
      this.keepAlive();
      cx.notify();
    });
    // On a timer, not on render: an idle window doesn't render, and the session
    // must come back after `wsl --shutdown`.
    cx.timer.every(30000, () => this.keepAlive());
    cx.spawn(async (cx) => {
      for (;;) {
        const c = await nextCommand();
        if (c === "new-space") this.newSpace();
        cx.notify();
      }
    });
  }

  keepAlive() {
    if (terminals().some((t) => t.name === KEEPALIVE && t.state === "live")) return;
    hc(["run", "--bg", "--no-parent", "--no-notify", "--rm", "--name", KEEPALIVE,
      "--label", "wsl.role=keepalive",
      "wsl.exe", ...(this.distro ? ["-d", this.distro] : []), "--", "sleep", "infinity"]).catch(() => {});
  }

  newSpace() {
    run("space.new", { machine: this.machine });
  }

  render() {
    const t = theme();
    const m = machines().find((x) => x.name === this.machine);
    const s = STATE[m?.layout ?? "missing"];
    const dot = div().size(7).rounded(4).bg(s.color(t));
    const root = h_flex().id("wsl-root").size_full().items_center().text_size(12.5).text_color(t.muted)
      .on_size_change((size, cx) => { this.width = size.width; cx.notify(); });
    // Narrower than 160px the sidebar is a rail: just the dot, a click opens a WSL space.
    if (this.width < 160) {
      return root.justify_center().child(div().id("wsl-new").p(6).rounded(6)
        .hover((st) => st.bg(t.hover)).on_click(() => this.newSpace()).child(dot));
    }
    return root.px(14).gap(8)
      .child(dot)
      .child(div().text_color(t.foreground).child("WSL"))
      .child(div().flex_1().truncate().text_color(t.dim)
        .child(this.distro ? `${this.distro} · ${s.word}` : s.word))
      .when(Boolean(m), (el) => el.child(div().id("wsl-new").px(6).rounded(4).text_size(15).text_color(t.muted)
        .hover((st) => st.bg(t.hover).text_color(t.foreground))
        .on_click(() => this.newSpace()).child("+")));
  }
}
