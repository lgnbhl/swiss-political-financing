
  // Which languages this build speaks. Read from the payload rather than
  // written here, so `LANGS` in prepare_data.R is the one place that decides.
  // The payload is assigned in the same <script>, immediately above this text.
  var SPF_LANGS = window.SPF.langs;

  window.spf = {
    // Replace one query parameter, preserving the route and the other filters.
    setParam: function (key, values) {
      var hash = window.location.hash || '#/';
      var qi = hash.indexOf('?');
      var path = qi >= 0 ? hash.slice(0, qi) : hash;
      var params = new URLSearchParams(qi >= 0 ? hash.slice(qi + 1) : '');
      params.delete(key);
      (Array.isArray(values) ? values : [values])
        .filter(function (v) { return v != null && v !== ''; })
        .forEach(function (v) { params.append(key, v); });
      var qs = params.toString();
      window.location.hash = path + (qs ? '?' + qs : '');
    },

    // Navigate to another in-app path, keeping the query string. The subject
    // pickers use this: choosing a different ballot must not silently drop the
    // filters the reader has already set on the table below it.
    goto: function (path) {
      var hash = window.location.hash || '#/';
      var qi = hash.indexOf('?');
      var query = qi >= 0 ? hash.slice(qi) : '';
      window.location.hash = '#' + path + query;
    },

    // Swap the language segment and keep everything else. This is only safe
    // because every filter value in the URL is a language-neutral key.
    //
    // The choice is remembered: it is what a bare "#/" resolves to on the next
    // visit, ahead of the browser's own preference. try/catch because
    // localStorage throws in private mode and under a file:// origin.
    setLang: function (lang) {
      try { window.localStorage.setItem('spf.lang', lang); } catch (e) {}
      window.spf.setTitle(lang);
      var hash = window.location.hash || '#/';
      var rest = hash.replace(/^#\/?/, '');
      var qi = rest.indexOf('?');
      var query = qi >= 0 ? rest.slice(qi) : '';
      var segs = (qi >= 0 ? rest.slice(0, qi) : rest).split('/');
      if (SPF_LANGS.indexOf(segs[0]) >= 0) { segs[0] = lang; }
      else { segs = [lang].concat(segs.filter(Boolean)); }
      window.location.hash = '#/' + segs.join('/') + query;
    },

    // The "CSVs not published yet" note is a native <dialog>, which gives us the
    // backdrop, Esc, the focus trap and page inertness. Not `Dialog.triggerId`
    // like the nav panel: that binds one trigger id, and this note is opened
    // from the download button of every one of the 13 tables on the data page.
    // One shared dialog opened imperatively beats 13 identical ones, or 13
    // buttons sharing an id.
    //
    // All three language shells exist in the source, but React Router mounts
    // only the routed one, so at any moment there is exactly one in the
    // document -- hence querySelector rather than an id per language.
    openDialog: function (sel) {
      var d = document.querySelector(sel);
      if (d && !d.open) { d.showModal(); }
    },
    closeDialog: function (sel) {
      var d = document.querySelector(sel);
      if (d && d.open) { d.close(); }
    },
    soon:      function () { window.spf.openDialog('dialog.spf-modal'); },
    closeSoon: function () { window.spf.closeDialog('dialog.spf-modal'); },

    // Below this width the app is being read on a phone held in one hand: charts
    // get a shorter label gutter and grids drop to their priority columns. Read
    // at loader time; `watchRotation()` below re-runs the route when the
    // threshold is actually crossed, so a rotation no longer has to wait for the
    // reader to navigate.
    narrow: function () { return window.innerWidth < 600; },

    // Move the keyboard into the page, past the app bar's nine links. Called by
    // the skip link, which is a <button> rather than an anchor because this app
    // is hash-routed and an href to a fragment would overwrite the route.
    skipToMain: function () {
      var m = document.getElementById('spf-main');
      if (!m) return;
      m.focus();
      m.scrollIntoView();
    },

    // Keep only the columns that answer the page's question when the grid is
    // narrower than about three columns. The rest are not lost: the desktop grid
    // still has them, and the CSV export writes the full row either way.
    keepCols: function (cols, keep) {
      if (!window.spf.narrow()) return cols;
      return cols.filter(function (c) { return keep.indexOf(c.field) >= 0; });
    },

    // Make chart tooltips reachable with a finger.
    //
    // MUI X resolves which item is under the pointer from pointer *movement*, so
    // on a touch screen a press that does not move never resolves one and no
    // tooltip appears -- which is every tap, and every press-and-hold. (A press
    // that happens to drift sideways works, which is why the behaviour looked
    // intermittent rather than broken.) Nudging it with a synthetic 1px move on
    // touch press makes press-and-hold show the tooltip, and sliding along the
    // bars then moves between them.
    //
    // Deliberately not paired with `touch-action: none` on the surface: that
    // would make a vertical swipe inspect instead of scrolling the page, and on
    // a phone the charts are nearly the full width, so there would be little
    // left to scroll from. A vertical swipe still scrolls; a hold still reads.
    // The tooltip shows while the finger is down and goes when it lifts, which
    // is the behaviour MUI X is built around. Making a tap *latch* it was tried
    // and rejected: the only way to do it is to stop the lift from reaching the
    // chart, and the chart then keeps a pointer it believes is still down. It
    // latched 9 taps in 16, and some of the rest showed the previous bar's
    // figures under the new bar's name. A wrong amount beside a donor's name is
    // the one failure this site must not have, so the tooltip is transient and
    // chart_card() says 'press and hold' on touch instead.
    touchNudge: function () {
      var move = function (svg, e, dx) {
        svg.dispatchEvent(new PointerEvent('pointermove', {
          bubbles: true, cancelable: true, composed: true,
          pointerId: e.pointerId, pointerType: 'touch', isPrimary: true,
          clientX: e.clientX + dx, clientY: e.clientY, pressure: 0.5, buttons: 1
        }));
      };
      document.addEventListener('pointerdown', function (e) {
        if (e.pointerType !== 'touch' || !e.target.closest) return;
        var svg = e.target.closest('.MuiChartsSurface-root');
        if (!svg) return;
        // Twice, a frame apart: the first can land before MUI X has registered
        // the press, and the second guarantees a delta from wherever it did.
        requestAnimationFrame(function () { move(svg, e, 0.5); });
        setTimeout(function () { move(svg, e, -0.5); }, 60);
      }, true);
    },

    // Axis labels are truncated rather than shrunk: below ~11px they stop being
    // readable, and MUI silently drops ticks that collide.
    clip: function (s, n) {
      s = String(s == null ? '' : s);
      return s.length > n ? s.slice(0, n - 1).trimEnd() + '…' : s;
    },

    // Franc amounts are formatted the same in all three languages: Swiss usage
    // groups thousands with an apostrophe in German, French and Italian alike
    // (CHF 923'857, not the fr-CH default CHF 923 857). It also means a figure
    // does not appear to change when the reader switches language.
    // Axis ticks are abbreviated (CHF 1.2M) so long amounts do not collide;
    // tooltips always carry the full value.
    fmt: function (lang) {
      var loc = window.SPF.chLocale;
      var chf = function (v) {
        return v == null ? '' : 'CHF ' + Math.round(v).toLocaleString(loc);
      };
      var num = function (v) {
        return v == null ? '' : Math.round(v).toLocaleString(loc);
      };
      var short = function (v) {
        if (v == null) return '';
        var a = Math.abs(v);
        if (a >= 1e6) return 'CHF ' + (v / 1e6).toFixed(a >= 1e7 ? 0 : 1) + 'M';
        if (a >= 1e3) return 'CHF ' + Math.round(v / 1e3) + 'k';
        return 'CHF ' + Math.round(v);
      };
      var pct = function (v) {
        return v == null ? '' : Math.round(v * 100) + '%';
      };
      return { chf: chf, num: num, short: short, pct: pct, loc: loc };
    },

    // One document serves three languages, so it can carry only one <title> --
    // the German one, written into the head at build time. This keeps the tab,
    // the bookmark and the shared link in the language actually on screen.
    // Also corrects <html lang>, which is the same one-document problem: the
    // shell Box carries the routed language for the subtree a screen reader is
    // in, but the root element is what a translation prompt reads.
    setTitle: function (lang) {
      var m = window.SPF.meta_page && window.SPF.meta_page[lang];
      if (!m) return;
      document.title = m.title;
      document.documentElement.setAttribute('lang', lang);
      var d = document.querySelector('meta[name="description"]');
      if (d) { d.setAttribute('content', m.description); }
    },

    // Sum, group and rank helpers used by the loaders.
    sumBy: function (rows, keyFn, valFn) {
      var m = new Map();
      rows.forEach(function (r) {
        var k = keyFn(r);
        if (k == null) return;
        m.set(k, (m.get(k) || 0) + (valFn(r) || 0));
      });
      return m;
    },
    ranked: function (map) {
      return Array.from(map.entries()).sort(function (a, b) { return b[1] - a[1]; });
    },
    topN: function (map, n) {
      return window.spf.ranked(map).slice(0, n);
    },
    sum: function (rows, valFn) {
      return rows.reduce(function (a, r) { return a + (valFn(r) || 0); }, 0);
    }
  };

  // Everything a route loader needs, in one call:
  //   `var c = window.spf.ctx(args, 'de')`
  //
  // The language is handed in by the route, because the route is the one thing
  // that knows it for certain. There are three language subtrees and the
  // language is a literal path segment in each ("de", not ":lang"), so it never
  // reaches `params`; and it must not be read from `location.hash`, which during
  // a navigation is already the *next* URL while the loader still belongs to the
  // previous one.
  //
  // What this does not do any more is bake the loader itself per language: the
  // route passes a two-character string to one shared function, instead of the
  // whole loader being written into the page three times.
  //
  // `lang` is optional so a loader can be called without a route -- which is
  // what js/smoke.js does; then it falls back to the routed hash.
  window.spf.ctx = function (args, lang) {
    var S = window.SPF, url = null;
    try { url = new URL(args.request.url); } catch (e) {}
    var L = lang;
    if (SPF_LANGS.indexOf(L) < 0) {
      var seg = (window.location.hash || '').replace(/^#\/?/, '').split(/[\/?]/)[0];
      L = SPF_LANGS.indexOf(seg) >= 0 ? seg : SPF_LANGS[0];
    }
    return {
      L: L,
      S: S,
      D: S.dict[L],          // key -> label, in this language
      T: S.i18n[L],          // the strings the loaders use
      M: S.meta[L],          // picker and filter option lists
      F: window.spf.fmt(L),  // franc / number / percent formatters
      K: S.consts,           // palette and chart constants
      P: args.params || {},
      q: url ? url.searchParams : new URLSearchParams()
    };
  };

  // The language a bare "#/" opens in. An explicit "#/fr/..." URL is never
  // touched -- a shared link means what it says. Order: the language the reader
  // last chose from the app bar, then the browser's preference list, then
  // German. Region subtags are dropped, so 'fr-CH' and 'fr' both give French.
  window.spf.resolveLang = function () {
    var stored = null;
    try { stored = window.localStorage.getItem('spf.lang'); } catch (e) {}
    if (SPF_LANGS.indexOf(stored) >= 0) { return stored; }
    var prefs = navigator.languages || [navigator.language || ''];
    for (var i = 0; i < prefs.length; i++) {
      var tag = String(prefs[i]).toLowerCase().split('-')[0];
      if (SPF_LANGS.indexOf(tag) >= 0) { return tag; }
    }
    return 'de';
  };

  // This runs while the document is still parsing, before shiny.react mounts
  // the router at the end of the body, so the router reads the resolved hash on
  // creation and the declarative "/de" index route never fires. replaceState
  // rather than assigning location.hash: assigning pushes a history entry, and
  // the back button would then bounce off the redirect instead of leaving.
  (function () {
    var h = window.location.hash;
    if (h === '' || h === '#' || h === '#/') {
      window.history.replaceState(
        null, '',
        window.location.pathname + window.location.search +
          '#/' + window.spf.resolveLang()
      );
    }
  })();

  // The title has to be right from the first paint, not from the first
  // language switch, so it is set from whatever the hash resolved to above.
  (function () {
    var seg = (window.location.hash || '').replace(/^#\/?/, '').split(/[\/?]/)[0];
    window.spf.setTitle(SPF_LANGS.indexOf(seg) >= 0 ? seg : 'de');
  })();

  // `narrow()` is read at loader time, so turning a phone sideways used to leave
  // the dropped grid columns and the clipped axis labels in place until the
  // reader navigated. Re-entering the route re-runs the loader and fixes both.
  //
  // Only on an actual crossing of the 600px threshold: that is the only width
  // any of this depends on, so an ordinary window drag changes nothing and must
  // not cost a re-render.
  //
  // The event is 'popstate', not 'hashchange'. This version of React Router
  // listens to popstate alone -- there is no hashchange listener anywhere in
  // lib/reactRouter-0.2.0/react-router-dom.js, so dispatching one would have
  // been a no-op that looked like a fix. Dispatching rather than writing to
  // location.hash because writing the same value changes nothing, and writing a
  // different one would push a history entry per rotation.
  //
  // If a future router version stops re-running loaders on a same-URL pop, this
  // degrades to exactly the old behaviour -- stale until the next navigation --
  // rather than to something broken.
  window.spf.watchRotation = function () {
    var was = window.spf.narrow();
    var t = null;
    window.addEventListener('resize', function () {
      clearTimeout(t);
      t = setTimeout(function () {
        var now = window.spf.narrow();
        if (now === was) return;
        was = now;
        window.dispatchEvent(new PopStateEvent('popstate', {
          state: window.history.state
        }));
      }, 180);
    });
  };

  // One delegated listener for the whole app, so it survives every navigation
  // without being re-attached per chart.
  window.spf.touchNudge();

  window.spf.watchRotation();
  
