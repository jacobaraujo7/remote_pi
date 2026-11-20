/* Pipeline do preview de markdown (plano 58) — receita VS Code:
   markdown-it (GFM) → DOMPurify (allowlist) → rewrite de imagens relativas
   pro scheme controlado → morphdom (diff de DOM, preserva scroll).
   API chamada pelo Dart: window.__cockpit.setContent(md, docDir),
   window.__cockpit.setTheme(vars) e window.__cockpit.setStrings(strings).

   Mermaid (plano 72): fence ```mermaid vira um placeholder
   `.ckp-mermaid[data-src-hash]` com o código escapado (fallback visível). O
   script do Mermaid (~3.5 MB) NÃO vem no esqueleto: `setContent` devolve
   `true` quando o documento tem diagrama e `window.mermaid` ainda não existe,
   e aí o Dart injeta o bundle (evaluateJavascript) e chama `mermaidLoaded()`.
   Render roda depois do morphdom, serializado, com cache hash → SVG. */
(function () {
  "use strict";

  var md = window.markdownit({
    html: true, // HTML embutido entra cru aqui; quem filtra é o DOMPurify
    linkify: true,
    typographer: false,
  });

  /* ---------- Mermaid (plano 72) ---------- */

  // Fonte de cada diagrama do render atual, por hash (o placeholder só leva o
  // hash; o <pre> dele é o fallback e some quando o SVG entra).
  var mermaidSrc = {};
  var mermaidCount = 0;

  // FNV-1a 32 bits + tamanho: identidade do fonte, não segurança.
  function hashSrc(src) {
    var h = 0x811c9dc5;
    for (var i = 0; i < src.length; i++) {
      h ^= src.charCodeAt(i);
      h = Math.imul(h, 0x01000193);
    }
    return (h >>> 0).toString(36) + "-" + src.length.toString(36);
  }

  var defaultFence = md.renderer.rules.fence;
  md.renderer.rules.fence = function (tokens, idx, options, env, self) {
    var token = tokens[idx];
    var lang = (token.info || "").trim().split(/\s+/)[0].toLowerCase();
    if (lang !== "mermaid") return defaultFence(tokens, idx, options, env, self);
    var src = token.content;
    var h = hashSrc(src);
    mermaidSrc[h] = src;
    mermaidCount++;
    return (
      '<div class="ckp-mermaid" data-src-hash="' +
      h +
      '"><pre><code>' +
      md.utils.escapeHtml(src) +
      "</code></pre></div>\n"
    );
  };

  // Allowlist do DOMPurify: default seguro + alvos comuns de README.
  var SANITIZE = {
    USE_PROFILES: { html: true },
    ADD_TAGS: ["details", "summary"],
    // "checked"/"disabled" preservam o checkbox de task list do GFM
    ADD_ATTR: [
      "align",
      "width",
      "height",
      "open",
      "checked",
      "disabled",
      // placeholder do Mermaid (plano 72) — o hash liga o container ao fonte
      "data-src-hash",
    ],
    FORBID_TAGS: ["style", "form", "button"],
    ALLOW_UNKNOWN_PROTOCOLS: false,
  };

  function rewriteImages(root, docDir) {
    var imgs = root.querySelectorAll("img");
    for (var i = 0; i < imgs.length; i++) {
      var src = imgs[i].getAttribute("src") || "";
      if (!src || /^[a-z][a-z0-9+.-]*:/i.test(src)) {
        // scheme explícito: só data: sobrevive (CSP bloqueia o resto)
        continue;
      }
      var abs = src.charAt(0) === "/" ? src : docDir + "/" + src;
      imgs[i].setAttribute("src", "ckp-res://local/" + encodeURIComponent(abs));
    }
  }

  /* Frontmatter YAML no topo do documento (--- ... ---), o cabeçalho de
     SKILL.md/agent.md. Sem este passo o markdown-it via um <hr> seguido de
     texto solto, e o bloco aparecia derretido no meio do conteúdo.

     As regras são as MESMAS do lado Flutter (MarkdownFrontmatter.split, em
     core/ui/widgets/markdown_frontmatter.dart), pra os dois caminhos de
     preview não discordarem sobre o que é frontmatter: abertura exatamente
     `---`, fechamento `---` ou `...`, e só conta como frontmatter se render
     ao menos um campo — senão `---\n\n---` (duas linhas horizontais)
     seria engolido. */
  function splitFrontmatter(source) {
    var text = source.replace(/\r\n?/g, "\n").replace(/^\uFEFF/, "");
    var lead = /^[ \t\n]*/.exec(text)[0];
    var candidate = text.slice(lead.length);
    if (candidate.slice(0, 3) !== "---") return null;
    var lines = candidate.split("\n");
    if (lines[0].replace(/\s+$/, "") !== "---") return null;
    var close = -1;
    for (var i = 1; i < lines.length; i++) {
      var t = lines[i].replace(/\s+$/, "");
      if (t === "---" || t === "...") {
        close = i;
        break;
      }
    }
    if (close < 0) return null;
    var fields = parseFields(lines.slice(1, close));
    if (!fields.length) return null;
    return { fields: fields, body: lines.slice(close + 1).join("\n") };
  }

  /* Subconjunto de YAML que aparece em frontmatter: `chave: valor` no nível
     de cima, com listas em bloco (`- item`) e continuações indentadas
     coladas ao valor da chave anterior. Não é um parser de YAML — o que ele
     não entende vira texto, que é melhor do que sumir da tela. */
  function parseFields(lines) {
    var out = [];
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (!line.trim() || line.trim().charAt(0) === "#") continue;
      if (/^\s/.test(line) && out.length) {
        // Continuação (item de lista, mapa aninhado): acumula na chave atual.
        var cont = line.trim().replace(/^-\s*/, "");
        out[out.length - 1].value += out[out.length - 1].value ? ", " + cont : cont;
        continue;
      }
      var sep = line.indexOf(":");
      if (sep < 1) continue;
      out.push({
        key: line.slice(0, sep).trim(),
        value: unquote(line.slice(sep + 1).trim()),
      });
    }
    return out;
  }

  function unquote(v) {
    if (v.length > 1) {
      var f = v.charAt(0);
      if ((f === '"' || f === "'") && v.charAt(v.length - 1) === f) {
        return v.slice(1, -1);
      }
    }
    return v;
  }

  /* Tabela chave/valor, o mesmo formato do MarkdownFrontmatterTable no
     Flutter. Montada por DOM + textContent (nunca innerHTML): o conteúdo vem
     do documento e não passa pelo DOMPurify daqui. */
  function frontmatterTable(fields) {
    var table = document.createElement("table");
    table.className = "ckp-frontmatter";
    var body = document.createElement("tbody");
    for (var i = 0; i < fields.length; i++) {
      var row = document.createElement("tr");
      var k = document.createElement("th");
      k.textContent = fields[i].key;
      var v = document.createElement("td");
      v.textContent = fields[i].value;
      row.appendChild(k);
      row.appendChild(v);
      body.appendChild(row);
    }
    table.appendChild(body);
    return table;
  }

  function render(markdown, docDir) {
    var front = splitFrontmatter(markdown);
    mermaidSrc = {};
    mermaidCount = 0;
    var html = md.render(front ? front.body : markdown);
    var clean = window.DOMPurify.sanitize(html, SANITIZE);
    var next = document.createElement("div");
    next.id = "content";
    next.innerHTML = clean;
    if (front) next.insertBefore(frontmatterTable(front.fields), next.firstChild);
    rewriteImages(next, docDir);
    var cur = document.getElementById("content");
    // Diff de DOM: só os nós que mudaram trocam — sem piscar, sem perder scroll.
    window.morphdom(cur, next, { onBeforeElUpdated: keepDiagram });
    mermaidState.src = mermaidSrc;
    pumpMermaid();
    // true = o documento tem diagrama mas o motor ainda não foi injetado
    // (o Dart injeta e chama mermaidLoaded).
    return mermaidCount > 0 && !window.mermaid;
  }

  var mermaidState = {
    ready: false, // initialize() já rodou com o tema atual
    gen: 0, // sobe a cada troca de tema: invalida cache e renders em voo
    svg: {}, // hash → svg (gen atual)
    err: {}, // hash → mensagem de erro da lib (gen atual)
    src: {}, // hash → fonte (último render)
    busy: false,
    seq: 0, // ids únicos pro mermaid.render
    strings: { mermaidError: "Diagram error" },
    printing: false, // exportação PDF em curso: a fila fica parada
    idle: [], // resolvers de whenIdle(), chamados quando a fila esvazia
  };

  /* morphdom: container de diagrama já desenhado NÃO é tocado — senão cada
     tecla fora do diagrama trocava o SVG pelo <pre> do placeholder novo e o
     diagrama piscava. Se o fonte mudou, o SVG antigo fica na tela (só o hash
     é atualizado) até o novo ficar pronto: editar o diagrama também não pisca. */
  function keepDiagram(fromEl, toEl) {
    if (
      !fromEl.classList ||
      !fromEl.classList.contains("ckp-mermaid") ||
      toEl.className !== "ckp-mermaid" ||
      !fromEl.hasAttribute("data-ckp-done")
    ) {
      return true;
    }
    var h = toEl.getAttribute("data-src-hash");
    if (fromEl.getAttribute("data-src-hash") !== h) {
      fromEl.setAttribute("data-src-hash", h);
    }
    return false;
  }

  function doneKey(h) {
    return mermaidState.gen + ":" + h;
  }

  // `vars` (opcional) sobrepõe as variáveis do tema — a exportação PDF
  // (plano 73) desenha com a paleta clara de impressão sem tocar na tela.
  function mermaidConfig(vars) {
    var css = getComputedStyle(document.documentElement);
    function v(name, fallback) {
      if (vars && vars[name]) return vars[name];
      var x = css.getPropertyValue(name).trim();
      return x || fallback;
    }
    var bg = v("--ckp-bg", "#1e1e1e");
    var text = v("--ckp-text", "#d4d4d4");
    var muted = v("--ckp-text-muted", "#9a9a9a");
    var border = v("--ckp-border", "#333333");
    var panel = v("--ckp-code-bg", "#2a2a2a");
    var accent = v("--ckp-link", "#4da3ff");
    var font = getComputedStyle(document.body).fontFamily;
    return {
      startOnLoad: false,
      // strict: sem click/callback JS, HTML dos rótulos sanitizado pela lib.
      securityLevel: "strict",
      theme: "base",
      fontFamily: font,
      themeVariables: {
        darkMode: isDark(bg),
        background: bg,
        fontFamily: font,
        fontSize: "14px",
        primaryColor: panel,
        primaryTextColor: text,
        primaryBorderColor: accent,
        secondaryColor: panel,
        secondaryTextColor: text,
        secondaryBorderColor: border,
        tertiaryColor: bg,
        tertiaryTextColor: text,
        tertiaryBorderColor: border,
        mainBkg: panel,
        nodeBorder: accent,
        clusterBkg: bg,
        clusterBorder: border,
        titleColor: text,
        textColor: text,
        lineColor: muted,
        edgeLabelBackground: bg,
        noteBkgColor: panel,
        noteTextColor: text,
        noteBorderColor: border,
        actorBkg: panel,
        actorBorder: accent,
        actorTextColor: text,
        actorLineColor: muted,
        signalColor: text,
        signalTextColor: text,
        labelBoxBkgColor: panel,
        labelBoxBorderColor: border,
        labelTextColor: text,
        loopTextColor: text,
        sequenceNumberColor: bg,
        stateBkg: panel,
        stateLabelColor: text,
        compositeBackground: bg,
        compositeTitleBackground: panel,
        altBackground: bg,
        transitionColor: muted,
        transitionLabelColor: text,
        specialStateColor: text,
        attributeBackgroundColorOdd: bg,
        attributeBackgroundColorEven: panel,
        taskBkgColor: panel,
        taskBorderColor: accent,
        taskTextColor: text,
        taskTextOutsideColor: text,
        taskTextLightColor: text,
        taskTextDarkColor: text,
        activeTaskBkgColor: accent,
        activeTaskBorderColor: accent,
        doneTaskBkgColor: border,
        doneTaskBorderColor: muted,
        critBorderColor: "#e5534b",
        critBkgColor: "#e5534b",
        gridColor: border,
        todayLineColor: accent,
        sectionBkgColor: bg,
        altSectionBkgColor: panel,
        sectionBkgColor2: bg,
      },
    };
  }

  function isDark(hex) {
    var m = /^#?([0-9a-f]{6})$/i.exec(hex);
    if (!m) return true;
    var n = parseInt(m[1], 16);
    var r = (n >> 16) & 255,
      g = (n >> 8) & 255,
      b = n & 255;
    return 0.2126 * r + 0.7152 * g + 0.0722 * b < 128;
  }

  function ensureMermaid() {
    if (!window.mermaid) return false;
    if (!mermaidState.ready) {
      window.mermaid.initialize(mermaidConfig());
      mermaidState.ready = true;
    }
    return true;
  }

  function apply(el, h) {
    var svg = mermaidState.svg[h];
    if (svg !== undefined) {
      el.classList.remove("ckp-mermaid-failed");
      // SVG gerado pela lib em modo strict (já sanitizado por ela). Não passa
      // pelo DOMPurify do HTML: ele quebra foreignObject e os <style> do SVG.
      el.innerHTML = svg;
      limitShrink(el.querySelector("svg"));
    } else {
      el.classList.add("ckp-mermaid-failed");
      el.textContent = "";
      el.appendChild(errorBox(mermaidState.err[h], mermaidState.src[h] || ""));
    }
    el.setAttribute("data-ckp-done", doneKey(h));
  }

  /* Diagrama largo encolhe com o pane só até 2/3 da largura natural (do
     viewBox); daí pra baixo o container rola de lado (overflow-x no CSS). */
  var MIN_SCALE = 0.66;
  function limitShrink(svg) {
    if (!svg) return;
    var vb = (svg.getAttribute("viewBox") || "").split(/[\s,]+/);
    var w = parseFloat(vb[2]);
    if (w > 0) svg.style.minWidth = Math.round(w * MIN_SCALE) + "px";
  }

  // Caixa de erro por DOM + textContent: mensagem da lib (texto de terceiro,
  // cru) e o fonte — nada disso é HTML confiável.
  function errorBox(message, src) {
    var box = document.createElement("div");
    box.className = "ckp-mermaid-error";
    var label = document.createElement("div");
    label.className = "ckp-mermaid-error-label";
    label.textContent = mermaidState.strings.mermaidError;
    var msg = document.createElement("pre");
    msg.className = "ckp-mermaid-error-message";
    msg.textContent = message || "";
    var code = document.createElement("pre");
    var codeInner = document.createElement("code");
    codeInner.textContent = src;
    code.appendChild(codeInner);
    box.appendChild(label);
    box.appendChild(msg);
    box.appendChild(code);
    return box;
  }

  // O mermaid desenha num nó temporário do <body> (#d<id>) e, em erro, pode
  // deixar lá o SVG "bomba". Limpa os dois em qualquer desfecho.
  function cleanupRender(id) {
    var ids = [id, "d" + id];
    for (var i = 0; i < ids.length; i++) {
      var n = document.getElementById(ids[i]);
      if (n && !n.closest("#content")) n.remove();
    }
  }

  function renderOne(h) {
    var gen = mermaidState.gen;
    var src = mermaidState.src[h] || "";
    var id = "ckp-mmd-" + ++mermaidState.seq;
    var m = window.mermaid;
    // parse antes do render: erro de sintaxe sai como mensagem, sem o SVG de
    // erro do mermaid.
    return Promise.resolve()
      .then(function () {
        return m.parse(src);
      })
      .then(function () {
        return m.render(id, src);
      })
      .then(
        function (out) {
          if (gen === mermaidState.gen) mermaidState.svg[h] = out.svg;
        },
        function (e) {
          if (gen === mermaidState.gen) {
            mermaidState.err[h] = String((e && (e.message || e.str)) || e);
          }
        },
      )
      .then(function () {
        cleanupRender(id);
      });
  }

  /* Fila serializada: um render por vez. A cada volta re-varre o DOM, então
     resultado de conteúdo que já mudou (hash fora do documento) nunca é
     aplicado — fica só no cache até a poda. */
  function pumpMermaid() {
    if (mermaidState.printing) return;
    if (mermaidState.busy || !ensureMermaid()) return flushIdle();
    var els = document.querySelectorAll("#content .ckp-mermaid");
    var present = {};
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var h = el.getAttribute("data-src-hash");
      if (!h || !Object.prototype.hasOwnProperty.call(mermaidState.src, h)) {
        continue; // div escrito à mão no HTML do markdown: não é nosso
      }
      present[h] = true;
      if (el.getAttribute("data-ckp-done") === doneKey(h)) continue;
      if (h in mermaidState.svg || h in mermaidState.err) {
        apply(el, h);
        continue;
      }
      mermaidState.busy = true;
      renderOne(h).then(function () {
        mermaidState.busy = false;
        pumpMermaid();
      });
      return;
    }
    // Tudo em dia: poda o cache (cada tecla num diagrama gera um hash novo).
    prune(mermaidState.svg, present);
    prune(mermaidState.err, present);
    flushIdle();
  }

  function flushIdle() {
    // busy = ainda tem render em voo (ele chama pumpMermaid de novo ao fim).
    if (mermaidState.busy) return;
    var waiters = mermaidState.idle;
    mermaidState.idle = [];
    for (var i = 0; i < waiters.length; i++) waiters[i]();
  }

  /* Promise que resolve quando todo diagrama do documento já foi desenhado
     (ou falhou). Sem diagrama, ou sem o motor (ainda não injetado), resolve
     na hora — quem exporta injeta o motor antes de chamar. */
  function whenIdle() {
    return new Promise(function (resolve) {
      mermaidState.idle.push(resolve);
      pumpMermaid();
    });
  }

  /* ---------- Exportação PDF (plano 73) ---------- */

  /* O PDF sai sempre na paleta clara (o `@media print` do CSS troca as
     variáveis), mas o SVG do mermaid tem as cores do tema da TELA embutidas.
     Então, sem mexer no que o usuário vê: cada diagrama desenhado ganha uma
     cópia `.ckp-mermaid-print` renderizada com a paleta de impressão, que só
     aparece no `@media print` (a do tema some ali). `finishPrint` remove as
     cópias e devolve a fila ao normal. */
  /* Título órfão no pé da página: o WebKit ignora `break-after: avoid` na
     impressão. Então o título e o bloco indivisível logo depois dele
     (diagrama, código, tabela, citação, imagem) vão juntos para um wrapper
     `.ckp-keep` com `break-inside: avoid` (CSS de print) — se não couberem no
     resto da página, descem juntos. `finishPrint` desfaz. */
  var KEEP_NEXT = "pre, table, blockquote, .ckp-mermaid, .ckp-mermaid-failed";
  function keepHeadings() {
    var hs = document.querySelectorAll(
      "#content > h1, #content > h2, #content > h3, #content > h4, #content > h5, #content > h6",
    );
    for (var i = 0; i < hs.length; i++) {
      var h = hs[i];
      var next = h.nextElementSibling;
      if (!next) continue;
      var lone = next.tagName === "P" && next.children.length === 1 &&
        next.firstElementChild.tagName === "IMG" && !next.textContent.trim();
      if (!lone && !next.matches(KEEP_NEXT)) continue;
      var wrap = document.createElement("div");
      wrap.className = "ckp-keep";
      h.parentNode.insertBefore(wrap, h);
      wrap.appendChild(h);
      wrap.appendChild(next);
    }
  }

  function unkeepHeadings() {
    var ws = document.querySelectorAll("#content .ckp-keep");
    for (var i = 0; i < ws.length; i++) {
      var w = ws[i];
      while (w.firstChild) w.parentNode.insertBefore(w.firstChild, w);
      w.remove();
    }
  }

  function preparePrint(vars) {
    return whenIdle().then(function () {
      mermaidState.printing = true;
      keepHeadings();
      var m = window.mermaid;
      var els = document.querySelectorAll("#content .ckp-mermaid[data-ckp-done]");
      if (!m || !els.length) return;
      m.initialize(mermaidConfig(vars));
      mermaidState.ready = false; // a fila reinicializa com o tema da tela
      var chain = Promise.resolve();
      Array.prototype.forEach.call(els, function (el) {
        var h = el.getAttribute("data-src-hash");
        if (!(h in mermaidState.svg)) return; // caixa de erro: sai como está
        var src = mermaidState.src[h] || "";
        chain = chain.then(function () {
          var id = "ckp-mmd-" + ++mermaidState.seq;
          return Promise.resolve()
            .then(function () {
              return m.render(id, src);
            })
            .then(
              function (out) {
                var copy = document.createElement("div");
                copy.className = "ckp-mermaid-print";
                // mesmo motivo do apply(): SVG do mermaid strict, sem DOMPurify
                copy.innerHTML = out.svg;
                el.appendChild(copy);
                el.classList.add("ckp-mermaid-has-print");
              },
              function () {
                // sem cópia, o diagrama da tela vai pro PDF mesmo
              },
            )
            .then(function () {
              cleanupRender(id);
            });
        });
      });
      return chain;
    });
  }

  function finishPrint() {
    unkeepHeadings();
    var copies = document.querySelectorAll(".ckp-mermaid-print");
    for (var i = 0; i < copies.length; i++) copies[i].remove();
    var marked = document.querySelectorAll(".ckp-mermaid-has-print");
    for (var j = 0; j < marked.length; j++) {
      marked[j].classList.remove("ckp-mermaid-has-print");
    }
    mermaidState.printing = false;
    mermaidState.ready = false;
    pumpMermaid();
  }

  function prune(cache, keep) {
    for (var k in cache) {
      if (!Object.prototype.hasOwnProperty.call(keep, k)) delete cache[k];
    }
  }

  // Troca de tema: re-inicializa e redesenha. O SVG antigo segue na tela até
  // o novo chegar (gen novo deixa todos "sujos", o cache é zerado).
  function rethemeMermaid() {
    if (!window.mermaid) return;
    mermaidState.gen++;
    mermaidState.svg = {};
    mermaidState.err = {};
    mermaidState.ready = false;
    pumpMermaid();
  }

  window.__cockpit = {
    setContent: function (markdown, docDir) {
      try {
        return render(markdown, docDir || "");
      } catch (e) {
        var cur = document.getElementById("content");
        cur.textContent = String((e && e.message) || e);
        return false;
      }
    },
    setTheme: function (vars) {
      var root = document.documentElement;
      var changed = false;
      for (var k in vars) {
        if (Object.prototype.hasOwnProperty.call(vars, k)) {
          if (root.style.getPropertyValue(k) !== vars[k]) changed = true;
          root.style.setProperty(k, vars[k]);
        }
      }
      if (changed) rethemeMermaid();
    },
    // Rótulos traduzidos (context.t no Dart). Atualiza as caixas já na tela.
    setStrings: function (strings) {
      for (var k in strings) {
        if (Object.prototype.hasOwnProperty.call(strings, k)) {
          mermaidState.strings[k] = strings[k];
        }
      }
      var labels = document.querySelectorAll(".ckp-mermaid-error-label");
      for (var i = 0; i < labels.length; i++) {
        labels[i].textContent = mermaidState.strings.mermaidError;
      }
    },
    // Exportação PDF (plano 73): o Dart chama preparePrint(paleta clara) e
    // espera a promise, gera o PDF (a impressão usa o `@media print`) e chama
    // finishPrint() em qualquer desfecho.
    preparePrint: function (vars) {
      return preparePrint(vars || {}).then(function () {
        return true;
      });
    },
    finishPrint: function () {
      finishPrint();
      return true;
    },
    // Chamado pelo Dart logo depois de injetar o mermaid.min.js.
    mermaidLoaded: function () {
      pumpMermaid();
      return !!window.mermaid;
    },
    // Windows: a rolagem vem do Flutter (roda e gesto do touchpad), não do
    // WebView2. O plugin injeta a roda como `SendMouseInput` e o gesto de
    // touchpad se perdia nesse caminho (subia travado ou nem rolava). O Dart
    // chama `captureScroll()` uma vez, que bloqueia a roda nativa (senão a roda
    // rolaria duas vezes), e depois `scrollBy(dx, dy)` a cada evento.
    captureScroll: function () {
      if (window.__cockpitScrollCaptured) return;
      window.__cockpitScrollCaptured = true;
      window.addEventListener(
        "wheel",
        function (e) {
          // Ctrl+roda segue nativo (zoom do WebView2).
          if (!e.ctrlKey) e.preventDefault();
        },
        { passive: false, capture: true },
      );
    },
    scrollBy: function (dx, dy) {
      window.scrollBy({ left: dx, top: dy, behavior: "instant" });
    },
  };
})();
