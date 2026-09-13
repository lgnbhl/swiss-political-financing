
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

  // ---- the app bar search ----------------------------------------------------
  // How many matches each group shows before it is cut short.
  //
  // A cap there must be: MUI renders every option it is given into the DOM, and
  // "e" matches some three thousand of them -- enough to make typing stutter on
  // a phone, and enough to hang the popup that opens on the arrow button with no
  // query at all.
  //
  // But a flat cap over the whole list was worse than slow, it was misleading.
  // Ten rows with nothing after them read as "that is all there is", when the
  // truth was ten of two hundred; and because people are listed first, a common
  // surname filled all ten and the Parteien and Zuwendende groups vanished from
  // a box whose whole point is that it covers them too. So the cap is per group,
  // and a group that overflows says by how much.
  var SEARCH_LIMIT = 12;

  // Created once per language and kept: MUI treats `filterOptions` as an
  // ordinary prop, so a fresh closure on every render would be a fresh filter on
  // every keystroke. Lazily, because window.jsmodule is not populated when this
  // file is read.
  var searchFilterFns = {};
  window.spf.searchFilter = function (lang) {
    if (searchFilterFns[lang]) return searchFilterFns[lang];
    var of = window.SPF.i18n[lang].search.of;
    var match = window.jsmodule['@mui/material'].createFilterOptions({
      // No `limit` here -- this matcher has to see every hit for the counts
      // below to be true. The cutting happens after.
      //
      // `alt` is matched but never shown: a person's name the other way round,
      // and a party's initials in all three languages. Without it "Josef
      // Dittli" and "SVP" both come back empty from a box that has them.
      stringify: function (o) { return o.alt ? o.label + ' ' + o.alt : o.label; }
    });

    searchFilterFns[lang] = function (options, state) {
      var hits = match(options, state);

      // Group order follows first appearance, which is the order
      // searchOptions() built -- people, parties, donors. MUI's groupBy renders
      // options in the order it is given them and starts a new header whenever
      // the group changes, so the groups have to stay contiguous here.
      var order = [], byGroup = {};
      hits.forEach(function (o) {
        if (!byGroup[o.groupLabel]) { byGroup[o.groupLabel] = []; order.push(o.groupLabel); }
        byGroup[o.groupLabel].push(o);
      });

      // The count goes in the group header -- "Personen (12 von 2299)" -- and not
      // into an extra row at the foot of the group. An extra row would be a
      // thing in the list that is not a result: it has to be disabled, skipped
      // by the keyboard, and guarded against in onChange, and MUI still writes
      // a clicked option's text into the input before any of that. A header is
      // none of those things, it is already sticky while the group scrolls, and
      // it says how deep the list is before the reader scrolls rather than
      // after.
      //
      // The header text lives on the options because that is where groupBy
      // reads it, so the shown ones are copied with a new groupLabel. The
      // originals are the cached list and must not be touched.
      var out = [];
      order.forEach(function (g) {
        var list = byGroup[g];
        var head = list.length > SEARCH_LIMIT
          ? g + ' (' + SEARCH_LIMIT + ' ' + of + ' ' + list.length + ')'
          : g + ' (' + list.length + ')';
        list.slice(0, SEARCH_LIMIT).forEach(function (o) {
          out.push({
            key: o.key, label: o.label, alt: o.alt, path: o.path, groupLabel: head
          });
        });
      });
      return out;
    };
    return searchFilterFns[lang];
  };

  // From `lg` the app bar has no room left for a readable search box beside the
  // seven section links: at 210px the placeholder and every result label were
  // cut off. So there it is a magnifier, and opening it swaps the links out for
  // a wide field. The swap is one class on the toolbar (see app.css) rather
  // than React state: the Autocomplete stays mounted, its cached options and
  // filter untouched, and like nav_sheet this binds to its trigger by id.
  //
  // It closes when focus leaves the field. A click on a result does not count:
  // MUI prevents the option's mousedown, so the input keeps focus; the pick
  // then blurs it (blurOnSelect) and the field closes by itself.
  window.spf.bindSearchToggle = function () {
    var wide = function () { return window.innerWidth >= 1200; };
    var bar = function () { return document.querySelector('.spf-bar'); };
    var open = function () {
      var b = bar();
      if (!b || !wide()) return;
      b.classList.add('spf-search-open');
      requestAnimationFrame(function () {
        var input = b.querySelector('.spf-search input');
        if (input) input.focus();
      });
    };
    var close = function (refocus) {
      var b = bar();
      if (!b || !b.classList.contains('spf-search-open')) return;
      b.classList.remove('spf-search-open');
      if (refocus) {
        var t = document.getElementById('spf-search-trigger');
        if (t) t.focus();
      }
    };

    document.addEventListener('click', function (e) {
      if (e.target.closest && e.target.closest('#spf-search-trigger')) open();
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && e.target.closest && e.target.closest('.spf-bar .spf-search')) {
        close(true);
        return;
      }
      if (e.key !== '/' || e.ctrlKey || e.metaKey || e.altKey) return;
      var t = e.target;
      if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
      var b = bar();
      if (!b || !wide() || b.classList.contains('spf-search-open')) return;
      e.preventDefault();
      open();
    });
    document.addEventListener('focusout', function (e) {
      var s = e.target.closest && e.target.closest('.spf-bar .spf-search');
      if (!s || (e.relatedTarget && s.contains(e.relatedTarget))) return;
      close(false);
    });
  };

  // The one place a person's two name halves are put back together, so the page
  // title, the search label and anything later cannot disagree about the order.
  window.spf.personName = function (p) {
    return ((p.l || '') + ' ' + (p.f || '')).trim();
  };

  // Everything the reader can name, in one list: the ~2250 people the person
  // index knows, the parties, and the donors. Each option carries the path it
  // goes to, so one control serves three kinds of subject and the box never
  // dead-ends -- typing "SVP" or a company name lands on the page that already
  // exists rather than on "no results" beside data that plainly has the answer.
  //
  // Built once per language and kept, because it is ~3300 options and the
  // control is on every page: rebuilding it on each render made typing visibly
  // lag on a phone. Nothing in it changes after load, so a cache is safe.
  //
  // People come first. A search here is nearly always for a person -- that is
  // what the rest of the app cannot already do -- and MUI renders the groups in
  // the order the options arrive in.
  var searchCache = {};
  window.spf.searchOptions = function (lang) {
    if (searchCache[lang]) return searchCache[lang];
    var S = window.SPF, T = S.i18n[lang], D = S.dict[lang];
    var out = [];

    // Every option is also matched by its own key, spaces for hyphens.
    //
    // MUI folds accents, so "mull" already finds "Müller". What it cannot do is
    // the German expansion: a reader typing "mueller", or "gruene", or
    // "hauseigentuemerverband" -- which is how you type an umlaut on a keyboard
    // that has none, and is exactly what the URL of the page says -- got
    // nothing. slugify() in prepare_data.R has already done that expansion to
    // build the key, so the key is the transliteration, free and already here.
    var deSlug = function (k) { return k.replace(/-/g, ' '); };

    // "Dittli Josef (Uri, FDP.Die Liberalen)". The canton and the party are what
    // tell two candidates of the same name apart, so far as anything can; a
    // person known only as a donor or a mandate contributor has neither, and
    // then the parenthesis is left off rather than shown empty.
    //
    // The label is surname-first, the way the EFK writes it and the way the
    // tables here read; `alt` carries the other order, so the reader may type
    // whichever they think of first. See window.spf.searchFilter.
    S.people.forEach(function (p) {
      var q = [p.c && D.canton[p.c], p.p && D.party[p.p]].filter(Boolean).join(', ');
      out.push({
        key: p.k,
        label: window.spf.personName(p) + (q ? ' (' + q + ')' : ''),
        alt: ((p.f || '') + ' ' + (p.l || '')).trim() + ' ' + deSlug(p.k),
        groupLabel: T.search.group_person,
        path: 'person/' + encodeURIComponent(p.k)
      });
    });

    Object.keys(D.party).forEach(function (k) {
      out.push({
        key: k, label: D.party[k],
        alt: (S.partyAbbr[k] ? S.partyAbbr[k] + ' ' : '') + deSlug(k),
        groupLabel: T.search.group_party,
        path: 'party/' + encodeURIComponent(k)
      });
    });

    // A private donor who is also a candidate or a mandate contributor is in
    // both groups, under two different keys: the person key is the bare name,
    // the donor key carries their place of residence. The person page is the
    // fuller view and the donor page is the money. A donor who is neither has
    // no person entry at all (see the people index in prepare_data.R).
    Object.keys(S.donors).forEach(function (k) {
      out.push({
        key: k, label: S.donors[k], alt: deSlug(k),
        groupLabel: T.search.group_donor,
        path: 'donor/' + encodeURIComponent(k)
      });
    });

    searchCache[lang] = out;
    return out;
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
  window.spf.bindSearchToggle();

  window.spf.watchRotation();
  
