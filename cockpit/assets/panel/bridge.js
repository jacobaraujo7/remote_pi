// Ponte dos arquivos `.panel` (plano 67). Injetada pelo app no início do
// documento; a página só vê `window.cockpit`.
//
//   const r = await cockpit("exec git status --short");
//   r.ok, r.code, r.stdout, r.stderr, r.json (stdout parseado quando é JSON)
//   cockpit.on("theme", vars => ...)   // troca de tema do app
//   cockpit.theme                       // as CSS variables --ckp-* atuais
//   cockpit.route / cockpit.on("route") // hash routing (multi-página)
// Libs embarcadas (sem rede): /__cockpit__/{cockpit.css,petite-vue.js,
// chart.js,marked.js,tailwind.js} — servidas dos assets do app.
(function () {
  if (window.cockpit) return;
  var listeners = {};

  function ready() {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      return Promise.resolve();
    }
    return new Promise(function (resolve) {
      window.addEventListener('flutterInAppWebViewPlatformReady', function () {
        resolve();
      }, { once: true });
    });
  }

  function cockpit(line) {
    return ready().then(function () {
      return window.flutter_inappwebview.callHandler('cockpit', String(line));
    });
  }

  cockpit.on = function (event, fn) {
    (listeners[event] = listeners[event] || []).push(fn);
    return function () {
      listeners[event] = (listeners[event] || []).filter(function (f) {
        return f !== fn;
      });
    };
  };

  cockpit.theme = {};


  cockpit.__emit = function (event, data) {
    (listeners[event] || []).forEach(function (fn) {
      try {
        fn(data);
      } catch (e) {
        console.error(e);
      }
    });
  };

  cockpit.__setTheme = function (vars) {
    cockpit.theme = vars;
    var root = document.documentElement;
    for (var k in vars) root.style.setProperty(k, vars[k]);
    cockpit.__emit('theme', vars);
  };

  // Roteamento por hash para painéis com mais de uma "página" num arquivo só.
  //   cockpit.route.path            // "/" | "/detail/3" (location.hash sem "#")
  //   cockpit.route.params          // { id: "3" } quando casou com um pattern
  //   cockpit.route.go("/detail/3") // navega (muda o hash)
  //   cockpit.route.match("/detail/:id")  // params ou null
  //   cockpit.on("route", route => ...)   // dispara a cada mudança
  var route = {
    path: '/',
    params: {},
    go: function (path) {
      location.hash = path.charAt(0) === '/' ? path : '/' + path;
    },
    match: function (pattern) {
      var p = pattern.split('/').filter(Boolean);
      var c = route.path.split('/').filter(Boolean);
      if (p.length !== c.length) return null;
      var params = {};
      for (var i = 0; i < p.length; i++) {
        if (p[i].charAt(0) === ':') params[p[i].slice(1)] = decodeURIComponent(c[i]);
        else if (p[i] !== c[i]) return null;
      }
      return params;
    },
  };
  function readHash() {
    var h = location.hash.replace(/^#/, '');
    route.path = h.charAt(0) === '/' ? h : '/' + h;
    route.params = {};
    cockpit.__emit('route', route);
  }
  window.addEventListener('hashchange', readHash);
  readHash();
  cockpit.route = route;

  window.cockpit = cockpit;
})();
