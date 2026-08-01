// spf-tables.js
// ---------------------------------------------------------------------------
// Row and column builders for the DataGrids, shared by every loader.
//
// Like spf-charts.js these take the loader context `c` (window.spf.ctx), so one
// copy serves all three languages.
//
// Loaded after spf-runtime.js and before spf-loaders.js; see build_site.R.

// Resolve one core donation row into the display row the grid shows. Placeholder
// labels ((no single party), (anonymous)) come from the i18n bundle, so they are
// translated like everything else.
function resolveRow(c, r) {
  var D = c.D, T = c.T;
  return {
    id: r.id,
    date: r.date,
    donor: r.is_anonymous ? T.anonymous : r.donor,
    donor_key: r.donor_key,
    donor_raw: r.donor_raw,
    donor_place: r.donor_place,
    amount: r.amount,
    recipient: D.actor[r.actor_key] || T.unknown,
    party: r.party_key == null ? T.no_party : (D.party[r.party_key] || r.party_key),
    party_key: r.party_key,
    canton: r.canton_key == null ? T.no_canton : (D.canton[r.canton_key] || r.canton_key),
    // A category the EFK adds shows its raw key rather than an empty cell: the
    // gift is real and belongs in the table even before anyone has translated
    // its name or built it a page.
    category: T.cat[r.category] || r.category,
    dtype: r.dtype_key == null ? '' : (D.dtype[r.dtype_key] || ''),
    position: r.position == null ? '' : (D.position[r.position] || ''),
    event: D.event[r.financing_id] || T.unknown,
    disclosure: r.with_budget ? T.income.budget : T.income.final,
    anonymous: r.is_anonymous
  };
}

// The whole list, which is what every loader actually wants.
function resolveRows(c, rows) {
  return rows.map(function (r) { return resolveRow(c, r); });
}

// Column set for any grid of donations. Donor and party cells link to their
// drill-downs; anonymous donors have no page to link to. The donor cell shows the
// grouped name and links by key, while `donor_raw` keeps the spelling the EFK
// actually received -- available as a column and in the CSV export, so the
// grouping is always auditable.
function donationColumns(c) {
  var T = c.T, L = c.L;
  // Underlined, not just coloured. A blue cell in a table of blue-ish chrome is
  // not read as a link -- these cells are the way into the donor and party
  // pages, and undecorated they were being missed entirely.
  var LINK = {
    color: c.K.LINK_COLOR, textDecoration: 'underline',
    textDecorationThickness: '1px', textUnderlineOffset: '2px',
    cursor: 'pointer', fontWeight: 600
  };
  var link = function (to) {
    return function (p) {
      if (!p.value) return '';
      if (to === 'donor' && (p.row.anonymous || !p.row.donor_key)) return p.value;
      if (to === 'party' && p.row.party_key == null) return p.value || '';
      var key = to === 'donor' ? p.row.donor_key : p.row.party_key;
      return React.createElement('a', {
        href: '#/' + L + '/' + to + '/' + encodeURIComponent(key),
        style: LINK, title: p.value
      }, p.value);
    };
  };

  var columns = [
    { field: 'date', headerName: T.cols.date, width: 108 },
    { field: 'donor', headerName: T.cols.donor, flex: 1.5, minWidth: 190,
      renderCell: link('donor') },
    { field: 'donor_place', headerName: T.cols.donor_place, width: 140 },
    { field: 'amount', headerName: T.cols.amount, type: 'number', width: 140,
      valueFormatter: c.F.num },
    { field: 'recipient', headerName: T.cols.recipient, flex: 1.6, minWidth: 210 },
    { field: 'event', headerName: T.cols.event, flex: 1.6, minWidth: 220 },
    { field: 'party', headerName: T.cols.party, flex: 1.1, minWidth: 150,
      renderCell: link('party') },
    { field: 'canton', headerName: T.cols.canton, width: 140 },
    { field: 'category', headerName: T.cols.category, width: 120 },
    { field: 'position', headerName: T.cols.position, width: 150 },
    { field: 'dtype', headerName: T.cols.dtype, width: 140 },
    { field: 'disclosure', headerName: T.cols.disclosure, width: 150 },
    { field: 'donor_raw', headerName: T.cols.donor_raw, flex: 1.2, minWidth: 190 }
  ];
  // Thirteen columns on a 360px screen is a horizontal scrollbar with no
  // landmarks. Who gave, how much, to whom -- the rest stays on the desktop grid
  // and in the CSV export.
  return window.spf.keepCols(columns, ['donor', 'amount', 'recipient']);
}

// ---- per-actor disclosure table ---------------------------------------------
// What each committee budgeted for a campaign event, what it finally reported,
// and the difference. This is the table view that discharges the hidden legend
// on the stacked camp chart above it.

// The two event kinds carry different dimensions and neither has the other's. A
// ballot has a camp and no candidates; an election has the party and canton of
// the candidates and no camp. Showing both sets everywhere would mean a column
// of empty cells on every page.
function declColumns(c, kind) {
  var T = c.T;
  var cols = [{ field: 'actor', headerName: T.cols.recipient, flex: 1.8, minWidth: 240 }];
  if (kind === 'votes') cols.push({ field: 'camp', headerName: T.cols.camp, width: 130 });
  cols.push(
    { field: 'budget', headerName: T.cols.budget, type: 'number', width: 150,
      valueFormatter: c.F.num },
    { field: 'final', headerName: T.cols.final, type: 'number', width: 150,
      valueFormatter: c.F.num },
    { field: 'delta', headerName: T.cols.delta, type: 'number', width: 150,
      valueFormatter: c.F.num }
  );
  if (kind === 'elections') cols.push(
    { field: 'party', headerName: T.cols.party, flex: 1, minWidth: 150 },
    { field: 'canton', headerName: T.cols.canton, width: 140 },
    { field: 'cfor', headerName: T.cols.cfor, flex: 1, minWidth: 170 }
  );
  // Both money columns survive on a phone: which of the two is filled is the
  // whole point of this table, and dropping one would read as a missing figure
  // rather than as a disclosure that has not been filed yet.
  return window.spf.keepCols(cols, ['actor', 'budget', 'final']);
}

// One row per actor and camp, with the budget and the final figures side by
// side. Grouping by actor rather than by declaration is what makes the two flags
// comparable on one line.
function declRows(c, rows) {
  var D = c.D, T = c.T;
  var camps = { yes: T.votes.kpi_yes, no: T.votes.kpi_no };
  var m = new Map();
  rows.forEach(function (d) {
    // A separator is needed: actor keys are slugs and camps are 'yes'/'no', so
    // concatenating them bare could make two different pairs the same string.
    // '|' cannot occur in either.
    var k = d.actor_key + '|' + (d.position || '');
    var e = m.get(k);
    if (!e) {
      e = { id: k, actor: D.actor[d.actor_key] || T.unknown,
            camp: d.position == null ? '' : camps[d.position],
            party: d.party_key == null ? T.no_party : (D.party[d.party_key] || d.party_key),
            canton: d.canton_key == null ? T.no_canton : (D.canton[d.canton_key] || d.canton_key),
            cfor: d.cfor_key == null ? T.unknown : (D.cfor[d.cfor_key] || T.unknown),
            budget: null, final: null, delta: null };
      m.set(k, e);
    }
    if (d.with_budget) e.budget = (e.budget || 0) + (d.total || 0);
    else               e.final  = (e.final  || 0) + (d.total || 0);
  });
  var out = Array.from(m.values());
  out.forEach(function (e) {
    e.delta = (e.budget != null && e.final != null) ? e.final - e.budget : null;
  });
  return out.sort(function (a, b) {
    return (b.final != null ? b.final : b.budget) - (a.final != null ? a.final : a.budget);
  });
}
