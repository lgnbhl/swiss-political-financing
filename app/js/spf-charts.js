// spf-charts.js
// ---------------------------------------------------------------------------
// Chart prop builders, shared by every loader.
//
// Each returns a complete set of MUI X BarChart props -- including live
// valueFormatter functions, which survive because loader data is never
// serialised. That keeps the R side to one generic BarChart per shape.
//
// Everything here takes the loader context `c` (window.spf.ctx) rather than
// reading globals, so one copy of each function serves all three languages.
//
// Loaded after spf-runtime.js and before spf-loaders.js; see build_site.R.
// Nothing in this file reads window.SPF while it is being parsed.

// A band axis reserves `labelWidth` for its tick labels. With no bands there is
// nothing to reserve for, and a hidden card measures zero wide -- MUI then hands
// SVG a negative rect width.
//
// On a phone the desktop gutter (up to 260px) is most of the screen, leaving the
// bars themselves a stub, so it is capped and the labels are clipped to match.
// Clipped, not shrunk: below ~11px the text stops being readable, and the row is
// identified in full in the table under every chart anyway.
var NARROW_ROOM = 112, NARROW_CHARS = 16;

function labelRoom(labels, w) {
  if (!labels.length) return 0;
  w = w || 210;
  return window.spf.narrow() ? Math.min(w, NARROW_ROOM) : w;
}

// The band axis keeps the *full* category names as its data and clips only when
// drawing a tick. `location` is 'tick' when the axis is labelling itself and
// 'tooltip' when the same value is being read out, so the axis stays narrow
// while the tooltip -- the only place a phone reader can see who a bar actually
// is -- gets the whole name.
function tickFormat(v, ctx) {
  return (ctx && ctx.location === 'tick' && window.spf.narrow())
    ? window.spf.clip(v, NARROW_CHARS) : v;
}

// ---- margins ----------------------------------------------------------------
// What the chart is scoped to is a caption in the card above the chart
// (chart_caption() in components.R), so these are constants rather than
// arithmetic over a wrapped line count.
//
// The vertical charts keep more room on top: their value axis centres the
// topmost tick label on the plot's *top edge*, so half of that label sits above
// the plot and needs somewhere to go.
var MH = { top: 6,  left: 4, right: 28, bottom: 4 };   // horizontal bars
var MV = { top: 18, left: 4, right: 8,  bottom: 4 };   // vertical bars

// ---- builders ---------------------------------------------------------------
function band(c, o, gap) {
  return Object.assign({ scaleType: 'band' }, c.K.GAP, gap || {}, o);
}

function barH(c, labels, values, labelWidth, color) {
  return {
    margin: MH,
    series: [{ data: values, color: color || c.K.SERIES[0], valueFormatter: c.F.chf }],
    xAxis: [{ valueFormatter: c.F.short, tickNumber: c.K.TICKS }],
    yAxis: [band(c, { data: labels, width: labelRoom(labels, labelWidth),
                      valueFormatter: tickFormat,
                      tickLabelStyle: { fontSize: 11 } })]
  };
}

// Horizontal bars where the series bring their own colours and stack.
function barHS(c, labels, series, labelWidth) {
  return {
    margin: MH,
    series: series,
    xAxis: [{ valueFormatter: c.F.short, tickNumber: c.K.TICKS }],
    yAxis: [band(c, { data: labels, width: labelRoom(labels, labelWidth),
                      valueFormatter: tickFormat,
                      tickLabelStyle: { fontSize: 11 } })]
  };
}

// Vertical bands whose series bring their own colours. `gap` widens the bands
// where there are few of them: two bands at the default ratio are two slabs half
// the plot wide.
function barVS(c, labels, series, gap) {
  return {
    margin: MV,
    series: series,
    xAxis: [band(c, { data: labels }, gap)],
    yAxis: [{ valueFormatter: c.F.short, width: 78, tickNumber: c.K.TICKS }]
  };
}

// ---- conditional blocks -----------------------------------------------------
// The component tree is built once in R, so a block that only sometimes applies
// is mounted always and hidden from here.
function hide(cond) { return cond ? { display: 'none' } : {}; }

// The complement, for the note that takes a hidden block's place. A chart that
// simply vanishes is indistinguishable from one that failed to draw, and on this
// site an absent bar is a factual claim -- 'nothing was filed' -- so the two
// styles are always issued as a pair and exactly one of them is visible.
function show(cond) { return hide(!cond); }

// ---- colour slots ------------------------------------------------------------
// A colour by index, never past the end of the ramp.
//
// Two series sets are sized by the data rather than by us -- the income
// components a party declaration reports, and the donation types the EFK
// publishes -- so their length is not ours to fix. An index past the last slot
// hands MUI X `undefined`, and MUI X then picks from its own palette: the chart
// still draws, with a colour that is very likely already on it. On this site two
// series in the same colour is a wrong claim about whose money it is.
//
// Clamping rather than cycling, for the same reason foldTop() folds rather than
// cycles. It is a floor under the failure, not the fix: check_palette() in
// build_checks.R stops the build before a page that would need it can ship.
function slot(ramp, i) { return ramp[Math.min(i, ramp.length - 1)]; }

// ---- ranking ----------------------------------------------------------------
// Rank a key -> amount map, keep the first `n` and fold the remainder into one
// labelled 'other' entry. Cycling a ramp past its last step would make two
// contributors the same colour, so the ramp length is the cap.
function foldTop(map, n, otherLabel) {
  var r = window.spf.ranked(map);
  var out = r.slice(0, n).map(function (e) { return { key: e[0], value: e[1] }; });
  var rest = r.slice(n);
  if (rest.length) {
    out.push({ key: null, value: rest.reduce(function (a, e) { return a + e[1]; }, 0),
               label: otherLabel + ' (' + rest.length + ')' });
  }
  return out;
}
