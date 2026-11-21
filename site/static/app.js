(() => {
  "use strict";

  const root = document.documentElement;
  const baseMeta = document.querySelector('meta[name="site-base"]');
  const BASE = baseMeta ? baseMeta.getAttribute("content") || "" : "";

  const THEME_SWATCHES = {
    gruvbox: {
      dark: ["#1d2021", "#282828", "#ff765b", "#b8bb26", "#fabd2f"],
      light: ["#fbf1c7", "#ebdbb2", "#af3a03", "#79740e", "#076678"],
    },
    noctalia: {
      dark: ["#101316", "#1c2023", "#8eb2c7", "#99cc99", "#f99157"],
      light: ["#f6f7f9", "#e2e7ed", "#2c6b8e", "#2d7a47", "#b85c1b"],
    },
    catppuccin: {
      dark: ["#11111b", "#1e1e2e", "#89b4fa", "#a6e3a1", "#f38ba8"],
      light: ["#eff1f5", "#dce0e8", "#1e66f5", "#40a02b", "#d20f39"],
    },
    nord: {
      dark: ["#242933", "#3b4252", "#88c0d0", "#a3be8c", "#ebcb8b"],
      light: ["#eceff4", "#d8dee9", "#2e6f95", "#4b7447", "#9e6a15"],
    },
    tokyonight: {
      dark: ["#11121b", "#1a1b26", "#7aa2f7", "#9ece6a", "#f7768e"],
      light: ["#e1e2e7", "#c8cad0", "#2e7de9", "#485e30", "#b53447"],
    },
  };

  function getSavedTheme() {
    try {
      const savedTheme = localStorage.getItem("oooconf-theme");
      const savedMode = localStorage.getItem("oooconf-mode");
      const preferredMode =
        window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches
          ? "light"
          : "dark";
      return {
        theme: savedTheme && THEME_SWATCHES[savedTheme] ? savedTheme : "gruvbox",
        mode: savedMode === "light" || savedMode === "dark" ? savedMode : preferredMode,
      };
    } catch {
      return { theme: "gruvbox", mode: "dark" };
    }
  }

  function applyTheme(theme, mode) {
    root.dataset.theme = theme;
    root.dataset.mode = mode;
    try {
      localStorage.setItem("oooconf-theme", theme);
      localStorage.setItem("oooconf-mode", mode);
    } catch {
      // Ignore storage errors in restricted contexts.
    }

    const themeSelect = document.getElementById("theme-select");
    if (themeSelect && themeSelect.value !== theme) {
      themeSelect.value = theme;
    }

    const modeBtn = document.getElementById("mode-toggle");
    if (modeBtn) {
      modeBtn.setAttribute("aria-label", `Switch to ${mode === "dark" ? "light" : "dark"} mode`);
      modeBtn.setAttribute("title", `Mode: ${mode} (click to switch)`);
      const iconMoon = modeBtn.querySelector("[data-icon='moon']");
      const iconSun = modeBtn.querySelector("[data-icon='sun']");
      if (iconMoon && iconSun) {
        iconMoon.style.display = mode === "dark" ? "none" : "block";
        iconSun.style.display = mode === "dark" ? "block" : "none";
      }
    }

    document.querySelectorAll("[data-theme-pick]").forEach((btn) => {
      btn.classList.toggle("is-active", btn.getAttribute("data-theme-pick") === theme);
    });
    document.querySelectorAll("[data-mode-pick]").forEach((btn) => {
      btn.classList.toggle("is-active", btn.getAttribute("data-mode-pick") === mode);
    });

    const themeCmd = document.getElementById("theme-command-text");
    if (themeCmd) {
      const cmd = `oooconf color ${theme} ${mode}`;
      themeCmd.textContent = cmd;
      const copyBtn = document.getElementById("theme-command-copy");
      if (copyBtn) copyBtn.setAttribute("data-copy-text", cmd);
    }

    const swatchRow = document.getElementById("theme-swatches");
    if (swatchRow) {
      const colors = THEME_SWATCHES[theme]?.[mode] || [];
      swatchRow.replaceChildren(
        ...colors.map((hex) => {
          const span = document.createElement("span");
          span.className = "swatch";
          span.style.backgroundColor = hex;
          span.title = hex;
          return span;
        })
      );
    }
  }

  function copyText(text, btn) {
    const done = () => {
      const prev = btn.textContent;
      btn.classList.add("is-copied");
      btn.textContent = "Copied";
      window.setTimeout(() => {
        btn.classList.remove("is-copied");
        btn.textContent = prev;
      }, 1500);
    };

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done).catch(() => fallbackCopy(text, done));
    } else {
      fallbackCopy(text, done);
    }
  }

  function fallbackCopy(text, done) {
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.select();
    try {
      document.execCommand("copy");
      done();
    } catch {
      // Clipboard unavailable.
    }
    document.body.removeChild(area);
  }

  function initThemeControls() {
    const initial = getSavedTheme();
    applyTheme(initial.theme, initial.mode);

    const select = document.getElementById("theme-select");
    if (select) {
      select.addEventListener("change", () => {
        applyTheme(select.value, root.dataset.mode || "dark");
      });
    }

    const modeToggle = document.getElementById("mode-toggle");
    if (modeToggle) {
      modeToggle.addEventListener("click", () => {
        const nextMode = root.dataset.mode === "dark" ? "light" : "dark";
        applyTheme(root.dataset.theme || "gruvbox", nextMode);
      });
    }

    document.querySelectorAll("[data-theme-pick]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const nextTheme = btn.getAttribute("data-theme-pick") || "gruvbox";
        applyTheme(nextTheme, root.dataset.mode || "dark");
      });
    });

    document.querySelectorAll("[data-mode-pick]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const nextMode = btn.getAttribute("data-mode-pick") || "dark";
        applyTheme(root.dataset.theme || "gruvbox", nextMode);
      });
    });
  }

  function initCopyButtons() {
    document.addEventListener("click", (event) => {
      const btn = event.target.closest(".copy-btn");
      if (!btn) return;
      const explicitText = btn.getAttribute("data-copy-text");
      if (explicitText) {
        copyText(explicitText, btn);
        return;
      }
      const targetSelector = btn.getAttribute("data-copy-target");
      if (targetSelector) {
        const target = document.querySelector(targetSelector);
        if (target) copyText(target.textContent || "", btn);
        return;
      }
      const codeBlock = btn.closest(".code-block");
      const code = codeBlock ? codeBlock.querySelector("pre code, pre") : null;
      if (code) copyText(code.textContent || "", btn);
    });
  }

  function initQuickStartTabs() {
    const buttons = document.querySelectorAll("[data-qs-tab]");
    const panels = document.querySelectorAll("[data-qs-panel]");
    if (!buttons.length) return;

    buttons.forEach((btn) => {
      btn.addEventListener("click", () => {
        const tab = btn.getAttribute("data-qs-tab");
        buttons.forEach((item) => item.classList.toggle("is-active", item === btn));
        panels.forEach((panel) =>
          panel.classList.toggle("is-active", panel.getAttribute("data-qs-panel") === tab)
        );
      });
    });
  }

  function createChip(text, className) {
    const span = document.createElement("span");
    span.className = className ? `chip ${className}` : "chip";
    span.textContent = text;
    return span;
  }

  function initExplorers() {
    const profileExplorer = document.getElementById("profile-explorer");
    const cliList = document.getElementById("cli-list");
    const depsGrid = document.getElementById("deps-grid");
    if (!profileExplorer && !cliList && !depsGrid) return;

    fetch(`${BASE}/data/site-data.json`)
      .then((res) => (res.ok ? res.json() : Promise.reject(new Error("Failed to load site data"))))
      .then((data) => {
        if (profileExplorer) setupProfileExplorer(data);
        if (cliList) setupCliExplorer(data);
        if (depsGrid) setupDepsExplorer(data);
      })
      .catch(() => {
        // Static initial HTML stays visible if fetch fails.
      });
  }

  function setupProfileExplorer(data) {
    let activeProfile = "developer";
    let activePlatform = "linux";

    const profileBtns = document.querySelectorAll("[data-profile-pick]");
    const platformBtns = document.querySelectorAll("[data-profile-platform]");
    const summaryEl = document.getElementById("profile-summary-desc");
    const cmdEl = document.getElementById("profile-command-text");
    const copyBtn = document.getElementById("profile-command-copy");
    const capsEl = document.getElementById("profile-caps-list");
    const linksEl = document.getElementById("profile-links-list");
    const depsEl = document.getElementById("profile-deps-list");
    const capsCountEl = document.getElementById("profile-caps-count");
    const linksCountEl = document.getElementById("profile-links-count");
    const depsCountEl = document.getElementById("profile-deps-count");

    function render() {
      const profile = data.profiles?.[activeProfile];
      const resolved = profile?.platforms?.[activePlatform];
      if (!profile || !resolved) return;

      profileBtns.forEach((btn) =>
        btn.classList.toggle("is-active", btn.getAttribute("data-profile-pick") === activeProfile)
      );
      platformBtns.forEach((btn) =>
        btn.classList.toggle("is-active", btn.getAttribute("data-profile-platform") === activePlatform)
      );

      if (summaryEl) {
        const extendsLabel = profile.extends ? ` (extends ${profile.extends})` : "";
        summaryEl.textContent = `${profile.name}${extendsLabel} — ${profile.description}`;
      }

      const cmd = `oooconf install --profile ${activeProfile}`;
      if (cmdEl) cmdEl.textContent = cmd;
      if (copyBtn) copyBtn.setAttribute("data-copy-text", cmd);

      if (capsEl) {
        const activeCaps = (resolved.capabilities || []).filter(
          (name) => !(resolved.skipped_capabilities || []).includes(name)
        );
        const chips = activeCaps.map((name) => createChip(name, "chip-active"));
        (resolved.skipped_capabilities || []).forEach((name) => {
          const skipped = createChip(`${name} (other OS)`, "chip-skipped");
          chips.push(skipped);
        });
        capsEl.replaceChildren(...chips);
        if (capsCountEl) capsCountEl.textContent = `${activeCaps.length} active`;
      }

      if (linksEl) {
        const links = resolved.links || [];
        linksEl.replaceChildren(...links.map((item) => createChip(item)));
        if (linksCountEl) linksCountEl.textContent = `${links.length} links`;
      }

      if (depsEl) {
        const deps = resolved.dependencies || [];
        depsEl.replaceChildren(...deps.map((item) => createChip(item)));
        if (depsCountEl) depsCountEl.textContent = `${deps.length} deps`;
      }
    }

    profileBtns.forEach((btn) => {
      btn.addEventListener("click", () => {
        activeProfile = btn.getAttribute("data-profile-pick") || "developer";
        render();
      });
    });

    platformBtns.forEach((btn) => {
      btn.addEventListener("click", () => {
        activePlatform = btn.getAttribute("data-profile-platform") || "linux";
        render();
      });
    });

    render();
  }

  function setupCliExplorer(data) {
    const commands = data.cli_commands || [];
    const searchInput = document.getElementById("cli-search");
    const familyBtns = document.querySelectorAll("[data-cli-family]");
    const platformBtns = document.querySelectorAll("[data-cli-platform]");
    const statusEl = document.getElementById("cli-status");
    const listEl = document.getElementById("cli-list");

    let family = "all";
    let platform = "all";
    let query = "";

    function render() {
      const q = query.trim().toLowerCase();
      const filtered = commands.filter((cmd) => {
        if (family !== "all" && cmd.family !== family) return false;
        if (platform !== "all" && !(cmd.platforms || []).includes(platform)) return false;
        if (!q) return true;
        const hay = `${cmd.command} ${cmd.description} ${(cmd.options || []).join(" ")}`.toLowerCase();
        return hay.includes(q);
      });

      const visible = q || family !== "all" || platform !== "all" ? filtered : filtered.slice(0, 18);
      if (statusEl) {
        statusEl.textContent =
          visible.length < filtered.length
            ? `Showing ${visible.length} of ${filtered.length} matching commands (${commands.length} total) — filter or search to explore all`
            : `Showing ${filtered.length} of ${commands.length} commands`;
      }

      if (!listEl) return;
      if (!visible.length) {
        const empty = document.createElement("p");
        empty.className = "search-empty";
        empty.textContent = "No commands match this filter.";
        listEl.replaceChildren(empty);
        return;
      }

      listEl.replaceChildren(
        ...visible.map((cmd) => {
          const card = document.createElement("article");
          card.className = "cli-item";

          const top = document.createElement("div");
          top.className = "cli-item-top";

          const name = document.createElement("code");
          name.className = "cli-cmd";
          name.textContent = cmd.command;
          top.appendChild(name);

          const plats = document.createElement("div");
          plats.className = "cli-platforms";
          (cmd.platforms || []).forEach((p) => {
            const tag = document.createElement("span");
            tag.className = "plat-tag";
            tag.textContent = p;
            plats.appendChild(tag);
          });
          top.appendChild(plats);
          card.appendChild(top);

          const desc = document.createElement("p");
          desc.className = "cli-desc";
          desc.textContent = cmd.description;
          card.appendChild(desc);

          if ((cmd.options || []).length) {
            const meta = document.createElement("div");
            meta.className = "cli-meta";
            cmd.options.slice(0, 6).forEach((opt) => {
              const span = document.createElement("span");
              span.className = "opt-tag";
              span.textContent = opt;
              meta.appendChild(span);
            });
            card.appendChild(meta);
          }

          return card;
        })
      );
    }

    if (searchInput) {
      searchInput.addEventListener("input", () => {
        query = searchInput.value;
        render();
      });
    }

    familyBtns.forEach((btn) => {
      btn.addEventListener("click", () => {
        family = btn.getAttribute("data-cli-family") || "all";
        familyBtns.forEach((item) => item.classList.toggle("is-active", item === btn));
        render();
      });
    });

    platformBtns.forEach((btn) => {
      btn.addEventListener("click", () => {
        platform = btn.getAttribute("data-cli-platform") || "all";
        platformBtns.forEach((item) => item.classList.toggle("is-active", item === btn));
        render();
      });
    });

    render();
  }

  function setupDepsExplorer(data) {
    const deps = data.optional_deps || [];
    const searchInput = document.getElementById("deps-search");
    const filterBtns = document.querySelectorAll("[data-deps-filter]");
    const statusEl = document.getElementById("deps-status");
    const gridEl = document.getElementById("deps-grid");

    let modeFilter = "minimal";
    let query = "";

    function render() {
      const q = query.trim().toLowerCase();
      const filtered = deps.filter((dep) => {
        if (modeFilter === "minimal" && !dep.minimal) return false;
        if (modeFilter === "linux" || modeFilter === "macos" || modeFilter === "windows") {
          if (!(dep.platforms || []).includes(modeFilter)) return false;
        }
        if (!q) return true;
        const hay = `${dep.key} ${dep.display} ${dep.description}`.toLowerCase();
        return hay.includes(q);
      });

      const visible = q || modeFilter !== "all" ? filtered : filtered.slice(0, 24);
      if (statusEl) {
        statusEl.textContent =
          visible.length < filtered.length
            ? `Showing ${visible.length} of ${filtered.length} matching packages (${deps.length} total)`
            : `Showing ${filtered.length} of ${deps.length} tracked packages`;
      }

      if (!gridEl) return;
      gridEl.replaceChildren(
        ...visible.map((dep) => {
          const card = document.createElement("article");
          card.className = "dep-card";

          const head = document.createElement("div");
          head.className = "dep-head";

          const name = document.createElement("span");
          name.className = "dep-name";
          name.textContent = dep.key;
          head.appendChild(name);

          if (dep.version) {
            const ver = document.createElement("span");
            ver.className = "dep-ver";
            ver.textContent = dep.version;
            head.appendChild(ver);
          }
          card.appendChild(head);

          const desc = document.createElement("p");
          desc.className = "dep-desc";
          desc.textContent = dep.description;
          card.appendChild(desc);

          const chips = document.createElement("div");
          chips.className = "chip-list";
          if (dep.minimal) chips.appendChild(createChip("minimal", "chip-minimal"));
          (dep.platforms || []).forEach((p) => {
            const plat = document.createElement("span");
            plat.className = "plat-tag";
            plat.textContent = p;
            chips.appendChild(plat);
          });
          card.appendChild(chips);
          return card;
        })
      );
    }

    if (searchInput) {
      searchInput.addEventListener("input", () => {
        query = searchInput.value;
        render();
      });
    }

    filterBtns.forEach((btn) => {
      btn.addEventListener("click", () => {
        modeFilter = btn.getAttribute("data-deps-filter") || "minimal";
        filterBtns.forEach((item) => item.classList.toggle("is-active", item === btn));
        render();
      });
    });

    render();
  }

  function initSearchModal() {
    const modal = document.getElementById("search-modal");
    const input = document.getElementById("search-modal-input");
    const resultsEl = document.getElementById("search-results");
    const triggers = document.querySelectorAll("[data-open-search]");
    if (!modal || !input || !resultsEl) return;

    let index = null;
    let loading = false;
    let selectedIdx = 0;
    let lastResults = [];

    function loadIndex() {
      if (index || loading) return;
      loading = true;
      fetch(`${BASE}/data/search-index.json`)
        .then((res) => (res.ok ? res.json() : Promise.reject(new Error("Search index failed"))))
        .then((payload) => {
          index = payload.items || [];
          renderResults();
        })
        .catch(() => {
          index = [];
          renderResults();
        })
        .finally(() => {
          loading = false;
        });
    }

    function openModal() {
      modal.hidden = false;
      document.body.style.overflow = "hidden";
      loadIndex();
      window.setTimeout(() => input.focus(), 10);
      renderResults();
    }

    function closeModal() {
      modal.hidden = true;
      document.body.style.overflow = "";
    }

    function scoreItem(item, terms) {
      const title = (item.title || "").toLowerCase();
      const body = (item.body || "").toLowerCase();
      const section = (item.section || "").toLowerCase();
      let score = 0;
      for (const term of terms) {
        if (title.includes(term)) score += 6;
        else if (section.includes(term)) score += 3;
        else if (body.includes(term)) score += 1;
        else return -1;
      }
      return score;
    }

    function renderResults() {
      if (!index) {
        resultsEl.innerHTML = '<div class="search-empty">Loading search index...</div>';
        return;
      }

      const raw = input.value.trim().toLowerCase();
      const terms = raw ? raw.split(/\s+/).filter(Boolean) : [];
      if (!terms.length) {
        lastResults = index.slice(0, 12);
      } else {
        lastResults = index
          .map((item) => ({ item, score: scoreItem(item, terms) }))
          .filter((entry) => entry.score > 0)
          .sort((a, b) => b.score - a.score)
          .slice(0, 16)
          .map((entry) => entry.item);
      }

      selectedIdx = 0;
      if (!lastResults.length) {
        resultsEl.innerHTML = '<div class="search-empty">No matching docs or commands.</div>';
        return;
      }

      resultsEl.replaceChildren(
        ...lastResults.map((item, idx) => {
          const link = document.createElement("a");
          link.className = idx === selectedIdx ? "search-result is-selected" : "search-result";
          link.href = item.url;
          link.addEventListener("click", closeModal);

          const top = document.createElement("div");
          top.className = "search-result-top";

          const title = document.createElement("span");
          title.className = "search-result-title";
          title.textContent = item.title;
          top.appendChild(title);

          const kind = document.createElement("span");
          kind.className = "search-result-kind";
          kind.textContent = item.section || item.kind;
          top.appendChild(kind);

          link.appendChild(top);

          if (item.snippet) {
            const snippet = document.createElement("span");
            snippet.className = "search-result-snippet";
            snippet.textContent = item.snippet;
            link.appendChild(snippet);
          }
          return link;
        })
      );
    }

    function updateSelection() {
      const items = resultsEl.querySelectorAll(".search-result");
      items.forEach((el, idx) => {
        el.classList.toggle("is-selected", idx === selectedIdx);
        if (idx === selectedIdx) el.scrollIntoView({ block: "nearest" });
      });
    }

    triggers.forEach((btn) => btn.addEventListener("click", openModal));
    modal.addEventListener("click", (event) => {
      if (event.target === modal) closeModal();
    });

    input.addEventListener("input", renderResults);
    input.addEventListener("keydown", (event) => {
      if (event.key === "ArrowDown" && lastResults.length) {
        event.preventDefault();
        selectedIdx = (selectedIdx + 1) % lastResults.length;
        updateSelection();
      } else if (event.key === "ArrowUp" && lastResults.length) {
        event.preventDefault();
        selectedIdx = (selectedIdx - 1 + lastResults.length) % lastResults.length;
        updateSelection();
      } else if (event.key === "Enter" && lastResults[selectedIdx]) {
        event.preventDefault();
        closeModal();
        window.location.href = lastResults[selectedIdx].url;
      }
    });

    document.addEventListener("keydown", (event) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        if (modal.hidden) openModal();
        else closeModal();
        return;
      }
      if (event.key === "Escape" && !modal.hidden) {
        closeModal();
        return;
      }
      if (
        event.key === "/" &&
        modal.hidden &&
        !["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName || "")
      ) {
        event.preventDefault();
        openModal();
      }
    });
  }

  function initDocsUi() {
    const toggle = document.getElementById("docs-sidebar-toggle");
    const sidebar = document.getElementById("docs-sidebar");
    if (toggle && sidebar) {
      toggle.addEventListener("click", () => {
        const open = sidebar.classList.toggle("is-open");
        toggle.setAttribute("aria-expanded", open ? "true" : "false");
      });
    }

    const tocLinks = Array.from(document.querySelectorAll(".docs-toc a"));
    if (!tocLinks.length || !("IntersectionObserver" in window)) return;

    const map = new Map();
    const targets = [];
    tocLinks.forEach((link) => {
      const id = decodeURIComponent((link.getAttribute("href") || "").replace(/^#/, ""));
      const heading = id ? document.getElementById(id) : null;
      if (heading) {
        map.set(heading, link);
        targets.push(heading);
      }
    });

    if (!targets.length) return;
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            tocLinks.forEach((item) => item.classList.remove("is-active"));
            const active = map.get(entry.target);
            if (active) active.classList.add("is-active");
            break;
          }
        }
      },
      { rootMargin: "-80px 0px -70% 0px", threshold: 0 }
    );
    targets.forEach((heading) => observer.observe(heading));
  }

  initThemeControls();
  initCopyButtons();
  initQuickStartTabs();
  initExplorers();
  initSearchModal();
  initDocsUi();
})();
