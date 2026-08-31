/// Script injetado via `evaluateJavascript` a cada `cockpit browser read`
/// (plano 61). Vive como constante Dart (não asset `.js` separado): é
/// pequeno, síncrono de carregar, e evita registrar mais um asset no pubspec
/// só pra um script — `CockpitCliHandler` importa e passa direto pro
/// `InAppWebViewController`.
///
/// Idempotente: reinjeção redefine as funções mas preserva o contador de
/// geração em `window.__cockpitBrowser.gen`.
///
/// Contrato: cada função devolve uma STRING JSON (não um objeto JS) — o lado
/// Dart só sabe fazer `jsonDecode` de uma `String` vinda de
/// `evaluateJavascript`, nunca confia no auto-marshalling de objetos do
/// plugin.
const String browserBridgeJs = r'''
(function () {
  var CB = window.__cockpitBrowser || { gen: 0 };
  window.__cockpitBrowser = CB;

  var SELECTOR =
    'a[href], button, input, textarea, select, ' +
    '[role="button"], [onclick], [tabindex]';

  function isVisible(el) {
    var style = window.getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden') {
      return false;
    }
    if (parseFloat(style.opacity) === 0) return false;
    var rect = el.getBoundingClientRect();
    return rect.width > 0 || rect.height > 0;
  }

  function inViewport(rect) {
    var vw = window.innerWidth || document.documentElement.clientWidth;
    var vh = window.innerHeight || document.documentElement.clientHeight;
    return rect.bottom > 0 && rect.right > 0 && rect.top < vh && rect.left < vw;
  }

  function roleOf(el) {
    var explicit = el.getAttribute('role');
    if (explicit) return explicit;
    var tag = el.tagName.toLowerCase();
    if (tag === 'a') return 'link';
    if (tag === 'button') return 'button';
    if (tag === 'input') {
      var type = (el.getAttribute('type') || 'text').toLowerCase();
      if (type === 'submit' || type === 'button' || type === 'reset') {
        return 'button';
      }
      return 'textbox';
    }
    if (tag === 'textarea') return 'textbox';
    if (tag === 'select') return 'combobox';
    if (el.hasAttribute('onclick') || el.hasAttribute('tabindex')) {
      return 'button';
    }
    return 'generic';
  }

  function textOf(el) {
    var t =
      el.innerText ||
      el.value ||
      el.getAttribute('aria-label') ||
      el.getAttribute('placeholder') ||
      el.getAttribute('alt') ||
      '';
    t = t.trim().replace(/\s+/g, ' ');
    return t.length > 200 ? t.slice(0, 200) : t;
  }

  // `read`: varre o DOM, marca cada elemento achado com `data-cockpit-id`
  // (embutindo a geração no próprio id) e limpa as marcas da geração
  // anterior — é o que torna um id de um `read` velho automaticamente
  // "stale" no próximo `read`, sem estado extra do lado Dart.
  CB.read = function (full) {
    CB.gen += 1;
    var gen = CB.gen;
    var stale = document.querySelectorAll('[data-cockpit-id]');
    for (var i = 0; i < stale.length; i++) {
      stale[i].removeAttribute('data-cockpit-id');
    }
    var out = [];
    var nodes = document.querySelectorAll(SELECTOR);
    var seq = 0;
    for (var j = 0; j < nodes.length; j++) {
      var el = nodes[j];
      var rect = el.getBoundingClientRect();
      var visible = isVisible(el);
      if (!full && (!visible || !inViewport(rect))) continue;
      seq += 1;
      var id = gen + '-' + seq;
      el.setAttribute('data-cockpit-id', id);
      out.push({
        id: id,
        role: roleOf(el),
        text: textOf(el),
        rect: { x: rect.x, y: rect.y, w: rect.width, h: rect.height },
      });
    }
    return JSON.stringify(out);
  };

  function findById(id) {
    var escaped = String(id).replace(/"/g, '\\"');
    return document.querySelector('[data-cockpit-id="' + escaped + '"]');
  }

  CB.click = function (id) {
    var el = findById(id);
    if (!el) return JSON.stringify({ error: 'stale_element_id' });
    el.scrollIntoView({ block: 'center', inline: 'center' });
    el.dispatchEvent(
      new MouseEvent('click', { bubbles: true, cancelable: true, view: window })
    );
    return JSON.stringify({ ok: true });
  };

  // Seta `.value` pelo setter nativo do protótipo, não pela propriedade da
  // instância: frameworks reativos (React e afins) trocam o setter de
  // instância por um próprio que ignora mutação direta — sem isso o `input`
  // sintético dispara mas o framework não percebe o valor novo.
  function setNativeValue(el, value) {
    var proto =
      el.tagName === 'TEXTAREA'
        ? window.HTMLTextAreaElement.prototype
        : window.HTMLInputElement.prototype;
    var desc = Object.getOwnPropertyDescriptor(proto, 'value');
    if (desc && desc.set) {
      desc.set.call(el, value);
    } else {
      el.value = value;
    }
  }

  CB.type = function (id, text) {
    var el = findById(id);
    if (!el) return JSON.stringify({ error: 'stale_element_id' });
    el.focus();
    if (el.isContentEditable) {
      el.textContent = text;
    } else {
      setNativeValue(el, text);
    }
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return JSON.stringify({ ok: true });
  };
})();
''';
