// spf-loaders.js
// ---------------------------------------------------------------------------
// The route loaders. Every subject page is URL-driven -- a ballot, a scrutiny,
// a party year, a donor year -- so what it shows is decided here, in the
// browser, from the core tables embedded once in window.SPF.
//
// One copy of each loader serves all three languages: `window.spf.ctx(args)`
// reads the routed language off the request and hands back that language's
// dictionary, strings and formatters. build_site.R wires a route to a loader
// with JS("(a) => window.spf.loaders.<name>(a)").
//
// Two rules run through all of them:
//
//   * `is_latest` for any figure that is a total. An actor files a budget and
//     then final accounts for the same campaign; counting both counts the same
//     francs twice (see prepare_data.R).
//   * both flags, side by side, only where the comparison itself is the point --
//     the camp chart on the votes page, which is the one place budgeted and
//     final income are meant to appear together.
//
// Loaded last; see build_site.R.

window.spf.loaders = {};

// A route addresses a subject that must exist. React Router turns this into the
// route's errorElement, which offers the way back.
function notFound() { throw new Response('Not found', { status: 404 }); }

// ---- votes ------------------------------------------------------------------
// The page the EFK's own ballot write-ups are built around: how much each camp
// disclosed, who put it there, and how the budget compares with the final
// accounts.
//
// Which bars exist is decided by what was actually filed. Most ballots carry
// both a budget and final accounts; a ballot whose vote has not happened yet
// carries only a budget; one June 2024 object has a Yes camp and no No camp at
// all. Assuming four bars would draw three empty ones.
//
// Colour is unconditional, which is what makes the chart safe to leave running
// for years: a budget bar is always grey, a final-accounts bar always carries
// its camp's colour, and the ramp step inside a bar is the contributor's rank.
// Nothing is recoloured because of what else the ballot happens to contain, so
// adding a filing only ever adds bars -- it never restyles the ones already
// there. A bar is absent if and only if nothing was filed for it.
//
// Grey for the budget is the point rather than a fallback: the reader is here
// for what a campaign actually raised, and the plan belongs beside that figure
// without competing with it. On a ballot where only a budget exists the chart is
// therefore all grey, which is the honest reading -- nothing final has been
// filed yet. The camp is still named on the axis and carried by the colour of
// the two camp figures above the chart.
window.spf.loaders.votes = function (args, lang) {
  var c = window.spf.ctx(args, lang);
  var S = c.S, D = c.D, T = c.T, F = c.F, K = c.K;

  var id = decodeURIComponent(c.P.eventId);
  var ev = S.events.find(function (e) { return String(e.financing_id) === id; });
  if (!ev) notFound();
  var decl = S.declarations.filter(function (d) {
    return String(d.financing_id) === id && d.category === 'votes';
  });
  if (!decl.length) notFound();

  // The source wording for a camp is a 45-character sentence; these are the
  // short forms used on axes and in the camp column.
  var campLabel = { yes: T.votes.kpi_yes, no: T.votes.kpi_no };
  var hasB = decl.some(function (d) { return d.with_budget; });
  var hasF = decl.some(function (d) { return !d.with_budget; });

  // ---- bands: every (camp, flag) pair that was actually filed ----------------
  var camps = ['yes', 'no'].filter(function (camp) {
    return decl.some(function (d) { return d.position === camp; });
  });
  var flags = [];
  if (hasB) flags.push(true);
  if (hasF) flags.push(false);
  var bands = [];
  camps.forEach(function (camp) {
    flags.forEach(function (b) {
      if (decl.some(function (d) { return d.position === camp && d.with_budget === b; })) {
        bands.push({ camp: camp, budget: b });
      }
    });
  });
  // Short forms. The full wording (camp name plus disclosure kind) overruns the
  // plot width at four bands, and MUI silently drops colliding ticks.
  var bandLabels = bands.map(function (b) {
    return (b.camp === 'yes' ? T.votes.short_yes : T.votes.short_no) + ' · ' +
           (b.budget ? T.votes.short_budget : T.votes.short_final);
  });

  var series = [];
  bands.forEach(function (b, bi) {
    var rows = decl.filter(function (d) {
      return d.position === b.camp && d.with_budget === b.budget;
    });
    var ramp = b.budget ? K.GREY : (b.camp === 'yes' ? K.YES : K.NO);
    // The ramp length caps how many committees are drawn separately; the rest
    // fold into one segment rather than re-using a colour already on screen.
    foldTop(window.spf.sumBy(rows, function (r) { return r.actor_key; },
                             function (r) { return r.total; }),
            ramp.length - 1, T.votes.other)
      .forEach(function (e, i) {
        var data = bands.map(function () { return null; });
        data[bi] = e.value;
        series.push({
          label: e.label || (D.actor[e.key] || T.unknown),
          data: data, stack: 'camp', color: ramp[i], valueFormatter: F.chf
        });
      });
  });

  // ---- headline figures: each committee counted once ------------------------
  var latest = decl.filter(function (d) { return d.is_latest; });
  var campSum = function (camp) {
    return window.spf.sum(latest.filter(function (d) { return d.position === camp; }),
                          function (d) { return d.total; });
  };
  var yes = campSum('yes'), no = campSum('no');
  var gapValue, gapNote;
  if (yes > 0 && no > 0) {
    var ratio = yes >= no ? yes / no : no / yes;
    gapValue = ratio.toFixed(ratio >= 10 ? 0 : 1).replace(/\.0$/, '') + '×';
    gapNote = ratio < 1.05 ? T.votes.gap_even
            : (yes >= no ? T.votes.gap_more_yes : T.votes.gap_more_no);
  } else {
    gapValue = '–';
    gapNote = T.votes.gap_one_sided;
  }

  // ---- who funded each camp -------------------------------------------------
  var don = S.donations.filter(function (r) {
    return r.is_latest && String(r.financing_id) === id && !r.is_anonymous;
  });
  var topDonors = window.spf.topN(
    window.spf.sumBy(don, function (r) { return r.donor_key; },
                     function (r) { return r.amount; }), 12);
  var donorLabels = topDonors.map(function (e) { return S.donors[e[0]] || e[0]; });
  var campOf = function (key, camp) {
    return window.spf.sum(don.filter(function (r) {
      return r.donor_key === key && r.position === camp;
    }), function (r) { return r.amount; }) || null;
  };
  var donorSeries = camps.map(function (camp) {
    return {
      label: campLabel[camp], stack: 'd', color: K.POLE[camp], valueFormatter: F.chf,
      data: topDonors.map(function (e) { return campOf(e[0], camp); })
    };
  });

  var scope = D.event[id] || T.unknown;

  return {
    title: D.event[id] || T.unknown,
    subtitle: T.events.type_campaign + (ev.date ? ' · ' + ev.date : ''),
    // Repeated on every chart card, so a chart scrolled far below the picker
    // still says which ballot it is about.
    scope: scope,
    options: c.M.voteEvents,
    current: c.M.voteEvents.find(function (o) { return o.key === id; }) || null,

    yesFmt: F.chf(yes), noFmt: F.chf(no),
    gap: gapValue, gapNote: gapNote,
    state: (hasB && hasF) ? T.votes.state_both
           : (hasF ? T.votes.state_final : T.votes.state_budget),

    // Two bands would otherwise be drawn as two slabs half the plot wide, so the
    // gap widens as bands get scarcer: a ballot with only a budget filed looks
    // like the same chart rather than a different one.
    camps: barVS(c, bandLabels, series, {
      categoryGapRatio: bands.length >= 4 ? 0.5 : (bands.length === 2 ? 0.72 : 0.82)
    }),
    donors: barHS(c, donorLabels, donorSeries, 250),
    donorsStyle: hide(topDonors.length === 0),
    donorsNoneStyle: show(topDonors.length === 0),

    declRows: declRows(c, decl),
    declColumns: declColumns(c, 'votes'),
    rows: don.length ? resolveRows(c, S.donations.filter(function (r) {
      return r.is_latest && String(r.financing_id) === id;
    })) : [],
    columns: donationColumns(c),

    // Set by prepare_data.R::joint_event_ids() where a committee filed one
    // disclosure covering this ballot and another of the same polling day, so
    // the same francs are listed under both.
    jointStyle: hide(!ev.joint)
  };
};

// ---- elections --------------------------------------------------------------
// Elections have no Yes/No camp -- `campaign` there is the list of supported
// candidates -- so the money is broken down by the party and the canton of those
// candidates instead. Both breakdowns carry an explicit bucket for the
// declarations that back candidates from several parties or cantons: roughly a
// third of them, and splitting one across eleven parties would count the same
// franc eleven times.
window.spf.loaders.elections = function (args, lang) {
  var c = window.spf.ctx(args, lang);
  var S = c.S, D = c.D, T = c.T, F = c.F;

  var id = decodeURIComponent(c.P.eventId);
  var ev = S.events.find(function (e) { return String(e.financing_id) === id; });
  if (!ev) notFound();
  var all = S.declarations.filter(function (d) {
    return String(d.financing_id) === id && d.category === 'elections';
  });
  if (!all.length) notFound();

  var decl = all.filter(function (d) { return d.is_latest; });
  var total = window.spf.sum(decl, function (d) { return d.total; });
  var mixed = window.spf.sum(decl.filter(function (d) { return d.party_key == null; }),
                             function (d) { return d.total; });

  // How many bands these two charts may draw. The boxes are 340px tall on a
  // phone (pages.R) and a band needs about 20px for an 11px tick label, so past
  // fifteen MUI X starts dropping the ticks that collide -- silently, leaving
  // bars with nothing naming them. One scrutiny breaks down into 24 cantons, so
  // the tail folds into a single 'other' band instead: the same thing the votes
  // page does to a ballot with more committees than its ramp has steps.
  var BANDS = 15;

  // A key of null means "several, or none stated", which is a bucket of its own
  // rather than a missing value; MIXED stands in for it while ranking.
  //
  // It is set aside before the fold and put back in rank order afterwards. The
  // mixedPct figure directly above these charts states its share, so a reader
  // who comes down looking for that band has to find it, however it ranks --
  // folding it into 'other' would answer the KPI with a bar that is not there.
  var MIXED = '\u0000';
  var rank = function (keyFn, dict, missing) {
    var m = window.spf.sumBy(decl,
      function (d) { var k = keyFn(d); return k == null ? MIXED : k; },
      function (d) { return d.total; });
    var mixed = m.get(MIXED);
    if (mixed != null) m.delete(MIXED);

    // One band spent on the fold, and one on the mixed bucket where there is one.
    var r = foldTop(m, BANDS - (mixed == null ? 1 : 2), T.votes.other);
    if (mixed != null) {
      // Ahead of the folded tail whatever either sums to: 'other' is the end of
      // the ranking by construction, not an entry competing in it. It is also
      // the one entry foldTop() leaves with a null key, which is what stops the
      // scan.
      var at = 0;
      while (at < r.length && r[at].key != null && r[at].value > mixed) at++;
      r.splice(at, 0, { key: MIXED, value: mixed });
    }

    return {
      labels: r.map(function (e) {
        return e.label || (e.key === MIXED ? missing : (dict[e.key] || e.key));
      }),
      values: r.map(function (e) { return e.value; })
    };
  };
  var byParty  = rank(function (d) { return d.party_key; },  D.party,  T.no_party);
  var byCanton = rank(function (d) { return d.canton_key; }, D.canton, T.no_canton);

  var scope = D.event[id] || T.unknown;

  return {
    title: D.event[id] || T.unknown,
    subtitle: T.events.type_campaign + (ev.date ? ' · ' + ev.date : ''),
    scope: scope,
    options: c.M.electionEvents,
    current: c.M.electionEvents.find(function (o) { return o.key === id; }) || null,

    incomeFmt: F.chf(total),
    count: decl.length.toLocaleString(F.loc),
    actors: new Set(decl.map(function (d) { return d.actor_key; })).size.toLocaleString(F.loc),
    mixedPct: total > 0 ? F.pct(mixed / total) : '–',

    party:  barH(c, byParty.labels,  byParty.values,  240),
    canton: barH(c, byCanton.labels, byCanton.values, 200),

    declRows: declRows(c, all),
    declColumns: declColumns(c, 'elections'),
    rows: resolveRows(c, S.donations.filter(function (r) {
      return r.is_latest && String(r.financing_id) === id;
    })),
    columns: donationColumns(c)
  };
};

// ---- party financing --------------------------------------------------------
// One calendar year at a time. Unlike the campaign categories, every party
// declaration reports the same income components -- own funds are always empty
// here, membership fees and mandate contributions only exist here -- so stacking
// the components against each other is a comparison that holds.
window.spf.loaders.parties = function (args, lang) {
  var c = window.spf.ctx(args, lang);
  var S = c.S, D = c.D, T = c.T, F = c.F, K = c.K;

  var year = decodeURIComponent(c.P.year);
  var ev = S.events.find(function (e) {
    return e.type === 'party_financing' && String(e.year) === year;
  });
  if (!ev) notFound();
  var fid = String(ev.financing_id);

  var decl = S.declarations.filter(function (d) {
    return d.category === 'party' && String(d.financing_id) === fid && d.is_latest;
  });
  if (!decl.length) notFound();

  // ---- income by party, stacked by component --------------------------------
  // Horizontal bands draw the first entry at the top, so descending order puts
  // the largest party on top -- the ranking the EFK's own release uses.
  var order = window.spf.ranked(window.spf.sumBy(decl,
    function (d) { return d.actor_key; }, function (d) { return d.total; }));
  var partyLabels = order.map(function (e) { return D.actor[e[0]] || T.unknown; });
  // Only the components anyone actually reported: an empty band in every bar is
  // a legend entry that explains nothing.
  var used = K.PARTS.filter(function (p) {
    return decl.some(function (d) { return (d[p] || 0) > 0; });
  });
  var partName = function (p) { return (T.income.parts && T.income.parts[p]) || p; };
  var incomeSeries = used.map(function (p, i) {
    return {
      label: partName(p), stack: 'inc', color: slot(K.SERIES, i), valueFormatter: F.chf,
      data: order.map(function (e) {
        return window.spf.sum(decl.filter(function (d) { return d.actor_key === e[0]; }),
                              function (d) { return d[p]; }) || null;
      })
    };
  });

  // ---- named donations ------------------------------------------------------
  var don = S.donations.filter(function (r) {
    return r.is_latest && String(r.financing_id) === fid && !r.is_anonymous;
  });
  var total = window.spf.sum(decl, function (d) { return d.total; });
  var named = window.spf.sum(don, function (r) { return r.amount; });

  var topDonors = window.spf.topN(
    window.spf.sumBy(don, function (r) { return r.donor_key; },
                     function (r) { return r.amount; }), 15);
  // Recipients are capped at the categorical slot count; past that a colour
  // would have to repeat, so the tail folds into one 'other' series.
  var recipients = window.spf.ranked(window.spf.sumBy(don,
    function (r) { return r.actor_key; }, function (r) { return r.amount; }));
  var namedRecip = recipients.slice(0, K.SERIES.length - 1).map(function (e) { return e[0]; });
  var donorSeries = namedRecip.map(function (a, i) {
    return {
      label: D.actor[a] || T.unknown, stack: 'r', color: K.SERIES[i], valueFormatter: F.chf,
      data: topDonors.map(function (e) {
        return window.spf.sum(don.filter(function (r) {
          return r.donor_key === e[0] && r.actor_key === a;
        }), function (r) { return r.amount; }) || null;
      })
    };
  });
  if (recipients.length > namedRecip.length) {
    donorSeries.push({
      label: T.votes.other, stack: 'r', color: K.SERIES[K.SERIES.length - 1],
      valueFormatter: F.chf,
      data: topDonors.map(function (e) {
        return window.spf.sum(don.filter(function (r) {
          return r.donor_key === e[0] && namedRecip.indexOf(r.actor_key) < 0;
        }), function (r) { return r.amount; }) || null;
      })
    });
  }

  // ---- mandate contributions ------------------------------------------------
  var mand = S.mandates.filter(function (m) { return String(m.financing_id) === fid; });
  var mRank = window.spf.ranked(window.spf.sumBy(mand,
    function (m) { return m.actor_key; }, function (m) { return m.amount; }));
  var mandRows = mand.map(function (m) {
    return {
      id: m.id, person: m.person,
      institution: D.inst[m.inst_key] || T.unknown,
      actor: D.actor[m.actor_key] || T.unknown,
      amount: m.amount
    };
  });

  var scope = String(year);

  return {
    title: T.parties.title + ' ' + year,
    subtitle: T.events.type_party + ' · ' + year,
    scope: scope,
    options: c.M.partyYears,
    current: c.M.partyYears.find(function (o) { return o.key === year; }) || null,

    totalFmt: F.chf(total),
    parties: decl.length.toLocaleString(F.loc),
    namedPct: total > 0 ? F.pct(named / total) : '–',

    income: barHS(c, partyLabels, incomeSeries, 260),
    donors: barHS(c, topDonors.map(function (e) { return S.donors[e[0]] || e[0]; }),
                  donorSeries, 250),
    donorsStyle: hide(topDonors.length === 0),
    donorsNoneStyle: show(topDonors.length === 0),

    mandates: barH(c, mRank.map(function (e) { return D.actor[e[0]] || T.unknown; }),
                   mRank.map(function (e) { return e[1]; }), 260),
    mandRows: mandRows,
    mandColumns: window.spf.keepCols([
      { field: 'person', headerName: T.cols.person, flex: 1.3, minWidth: 180 },
      { field: 'institution', headerName: T.cols.institution, flex: 1.2, minWidth: 180 },
      { field: 'amount', headerName: T.cols.amount, type: 'number', width: 150,
        valueFormatter: F.num },
      { field: 'actor', headerName: T.cols.recipient, flex: 1.5, minWidth: 200 }
    ], ['person', 'amount', 'actor']),
    mandatesStyle: hide(mand.length === 0),
    mandatesNoneStyle: show(mand.length === 0),

    declRows: decl.map(function (d) {
      var row = { id: d.declaration_id, actor: D.actor[d.actor_key] || T.unknown,
                  total: d.total };
      used.forEach(function (p) { row[p] = d[p]; });
      return row;
    }),
    // The income components are what the chart above already shows; on a phone
    // the table is here for the party and its total.
    declColumns: window.spf.keepCols(
      [{ field: 'actor', headerName: T.cols.recipient, flex: 1.6, minWidth: 260 },
       { field: 'total', headerName: T.cols.total, type: 'number', width: 180,
         valueFormatter: F.num }].concat(
        used.map(function (p) {
          return { field: p, headerName: partName(p), type: 'number', width: 170,
                   valueFormatter: F.num };
        })),
      ['actor', 'total']),

    rows: resolveRows(c, S.donations.filter(function (r) {
      return r.is_latest && String(r.financing_id) === fid;
    })),
    columns: donationColumns(c)
  };
};

// ---- donors -----------------------------------------------------------------
// `params.year` is 'all' or a calendar year and governs the whole page, so the
// grid below the charts has no year filter of its own -- two year controls on
// one page would disagree with each other. The remaining query filters narrow
// the grid and the charts together.
window.spf.loaders.donors = function (args, lang) {
  var c = window.spf.ctx(args, lang);
  var S = c.S, D = c.D, T = c.T, F = c.F, M = c.M;

  var year = c.P.year ? decodeURIComponent(c.P.year) : 'all';
  var g = function (k) { return c.q.getAll(k); };
  var parties = g('party'), cantons = g('canton'), cats = g('category'),
      positions = g('position'), events = g('event');
  var minStr = c.q.get('min') || '';
  var minAmt = parseFloat(minStr) || 0;
  var kd = function (v) { return v == null ? '-' : String(v); };

  var rows = S.donations.filter(function (r) { return r.is_latest; });
  if (year !== 'all') rows = rows.filter(function (r) { return String(r.year) === year; });
  if (parties.length)   rows = rows.filter(function (r) { return parties.includes(kd(r.party_key)); });
  if (cantons.length)   rows = rows.filter(function (r) { return cantons.includes(kd(r.canton_key)); });
  if (cats.length)      rows = rows.filter(function (r) { return cats.includes(r.category); });
  if (positions.length) rows = rows.filter(function (r) { return positions.includes(kd(r.position)); });
  if (events.length)    rows = rows.filter(function (r) { return events.includes(String(r.financing_id)); });
  if (minAmt)           rows = rows.filter(function (r) { return (r.amount || 0) >= minAmt; });

  var named = rows.filter(function (r) { return !r.is_anonymous; });
  var sum = window.spf.sum(rows, function (r) { return r.amount; });

  // ---- ranked donors --------------------------------------------------------
  var byDonor = window.spf.ranked(window.spf.sumBy(named,
    function (r) { return r.donor_key; }, function (r) { return r.amount; }));
  var top = byDonor.slice(0, 20);
  var topTen = byDonor.slice(0, 10).reduce(function (a, e) { return a + e[1]; }, 0);

  // ---- where the money comes from -------------------------------------------
  // Two bands (organisations, private individuals), stacked by whether the gift
  // was money or goods and services.
  var kinds = [
    { label: T.donors.kind_org,    test: function (r) { return r.donor_is_org; } },
    { label: T.donors.kind_person, test: function (r) { return !r.donor_is_org; } }
  ];
  var dtypes = Array.from(new Set(rows.map(function (r) { return r.dtype_key; })))
    .filter(function (k) { return k != null; }).sort();
  var kindSeries = dtypes.map(function (k, i) {
    return {
      label: D.dtype[k] || k, stack: 'k', color: slot(c.K.SERIES, i), valueFormatter: F.chf,
      data: kinds.map(function (kind) {
        return window.spf.sum(rows.filter(function (r) {
          return kind.test(r) && r.dtype_key === k;
        }), function (r) { return r.amount; }) || null;
      })
    };
  });

  var imputed = rows.filter(function (r) { return r.year_source !== 'donation'; }).length;

  var pick = function (all, keys) {
    return all.filter(function (o) { return keys.includes(o.key); });
  };
  var cur = M.donorYears.find(function (o) { return o.key === year; }) || M.donorYears[0];

  var scope = cur ? cur.label : String(year);

  return {
    options: M.donorYears,
    current: cur,
    // The chosen year, worded as the picker words it -- all-years is a period
    // too. Without it a ranked donor chart states an amount whose period is only
    // knowable by scrolling back up to the picker.
    scope: scope,

    sumFmt: F.chf(sum),
    count: rows.length.toLocaleString(F.loc),
    donorCount: byDonor.length.toLocaleString(F.loc),
    topShare: sum > 0 ? F.pct(topTen / sum) : '–',
    imputed: imputed,
    imputedFmt: imputed.toLocaleString(F.loc),

    top: barH(c, top.map(function (e) { return S.donors[e[0]] || e[0]; }),
              top.map(function (e) { return e[1]; }), 260),
    kind: barVS(c, kinds.map(function (k) { return k.label; }), kindSeries),
    emptyStyle: hide(rows.length > 0),
    imputedStyle: hide(imputed === 0),

    rows: resolveRows(c, rows),
    columns: donationColumns(c),
    parties: M.parties, cantons: M.cantons, categories: M.categories,
    positions: M.positions, events: M.events,
    curParty: pick(M.parties, parties), curCanton: pick(M.cantons, cantons),
    curCat: pick(M.categories, cats), curPosition: pick(M.positions, positions),
    curEvent: pick(M.events, events), curMin: minStr
  };
};

// ---- drill-downs ------------------------------------------------------------
// One donor, or one party, across everything it appears in.
//
// The two pages ask the same three questions -- how much, to whom, on what --
// and render through the same page_drill() in pages.R, so they are one loader
// with the two differences named: which rows belong to the subject, and what
// the second chart and the third figure count.
//
// Both are addressed by key rather than by name: the slug of the grouped donor
// name, or the party key. So the URL is stable across the spellings the same
// body files under, and /de/party/die-mitte and /fr/party/die-mitte are the same
// page in two languages.
function drill(mode) {
  return function (args, lang) {
    var c = window.spf.ctx(args, lang);
    var S = c.S, D = c.D, T = c.T, F = c.F;
    var key = decodeURIComponent(c.P.key);

    var isDonor = mode === 'donor';
    var rows = S.donations.filter(isDonor
      ? function (r) { return r.is_latest && !r.is_anonymous && r.donor_key === key; }
      : function (r) { return r.is_latest && r.party_key === key; });
    if (!rows.length) notFound();

    var name = isDonor ? (S.donors[key] || key) : (D.party[key] || key);
    var sum = window.spf.sum(rows, function (r) { return r.amount; });

    // Who is at the other end of the money: for a donor the committees it gave
    // to, for a party the donors that gave to it.
    var who = window.spf.topN(window.spf.sumBy(
      isDonor ? rows : rows.filter(function (r) { return !r.is_anonymous; }),
      isDonor ? function (r) { return r.actor_key; }
              : function (r) { return r.donor_key; },
      function (r) { return r.amount; }), 12);
    var whoLabel = isDonor
      ? function (k) { return D.actor[k] || T.unknown; }
      : function (k) { return S.donors[k] || k; };

    // What it was for -- the same question on both pages.
    var what = window.spf.topN(window.spf.sumBy(rows,
      function (r) { return r.financing_id; }, function (r) { return r.amount; }), 12);

    // The third figure. A donor's is how many committees it reached, which is
    // `who`. A party's is how many donors it had -- including the anonymous
    // ones, which `who` leaves out, and which count as one between them because
    // there is no way to tell them apart.
    var extra = isDonor
      ? who.length
      : new Set(rows.map(function (r) { return r.is_anonymous ? '?' : r.donor_key; })).size;

    var scope = name;

    return {
      title: (isDonor ? T.drill.donor_title : T.drill.party_title) + ' ' + name,
      scope: scope,
      rows: resolveRows(c, rows),
      columns: donationColumns(c),
      sumFmt: F.chf(sum),
      count: rows.length.toLocaleString(F.loc),
      extra: extra.toLocaleString(F.loc),
      extraLabel: isDonor ? T.drill.kpi_recipients : T.drill.kpi_donors,
      who: barH(c, who.map(function (e) { return whoLabel(e[0]); }),
                who.map(function (e) { return e[1]; }), 250),
      // Event labels are the full wording of a federal act; clipped here because
      // the row is named in full in the table under the chart.
      what: barH(c, what.map(function (e) {
                   return window.spf.clip(D.event[e[0]] || T.unknown, 52);
                 }),
                 what.map(function (e) { return e[1]; }), 300)
    };
  };
}

window.spf.loaders.donor = drill('donor');
window.spf.loaders.party = drill('party');
