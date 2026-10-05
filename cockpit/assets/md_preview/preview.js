/* Pipeline do preview de markdown (plano 58) — receita VS Code:
   markdown-it (GFM) → DOMPurify (allowlist) → rewrite de imagens relativas
   pro scheme controlado → morphdom (diff de DOM, preserva scroll).
   API chamada pelo Dart: window.__cockpit.setContent(md, docDir) e
   window.__cockpit.setTheme(vars). */
(function () {
  "use strict";

  var md = window.markdownit({
    html: true, // HTML embutido entra cru aqui; quem filtra é o DOMPurify
    linkify: true,
    typographer: false,
  });

  // Allowlist do DOMPurify: default seguro + alvos comuns de README.
  var SANITIZE = {
    USE_PROFILES: { html: true },
    ADD_TAGS: ["details", "summary"],
    // "checked"/"disabled" preservam o checkbox de task list do GFM
    ADD_ATTR: ["align", "width", "height", "open", "checked", "disabled"],
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
    var html = md.render(front ? front.body : markdown);
    var clean = window.DOMPurify.sanitize(html, SANITIZE);
    var next = document.createElement("div");
    next.id = "content";
    next.innerHTML = clean;
    if (front) next.insertBefore(frontmatterTable(front.fields), next.firstChild);
    rewriteImages(next, docDir);
    var cur = document.getElementById("content");
    // Diff de DOM: só os nós que mudaram trocam — sem piscar, sem perder scroll.
    window.morphdom(cur, next);
  }

  window.__cockpit = {
    setContent: function (markdown, docDir) {
      try {
        render(markdown, docDir || "");
      } catch (e) {
        var cur = document.getElementById("content");
        cur.textContent = String((e && e.message) || e);
      }
    },
    setTheme: function (vars) {
      var root = document.documentElement;
      for (var k in vars) {
        if (Object.prototype.hasOwnProperty.call(vars, k)) {
          root.style.setProperty(k, vars[k]);
        }
      }
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
