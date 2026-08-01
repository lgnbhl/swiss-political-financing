// smoke.js
// ---------------------------------------------------------------------------
// Run every route loader, in every language, against the data that was just
// built into index.html, and check each returns the fields its page reads.
//
//   node js/smoke.js <index.html> <expected.json>
//
// build_site.R runs this after writing the page, and fails the build on a
// non-zero exit. Nothing else checks the join between the R side and the
// JavaScript side: a page asking for `sumFmt` while its loader returns
// `totalFmt` builds cleanly and is only visibly broken in a browser.
//
// The loaders touch no DOM -- they read window.SPF and return a plain object --
// so the stubs below only have to be enough for the module bodies to evaluate.

'use strict';
const fs = require('fs');
const vm = require('vm');

const [htmlPath, expectedPath] = process.argv.slice(2);
if (!htmlPath || !expectedPath) {
  console.error('usage: node js/smoke.js <index.html> <expected.json>');
  process.exit(2);
}

// ---- the page's own script, lifted back out of the built page ---------------
// Read from index.html rather than from js/*.js so this checks what actually
// shipped, including the payload the loaders run against.
const html = fs.readFileSync(htmlPath, 'utf8');
const start = html.indexOf('window.SPF = {');
if (start < 0) throw new Error('no window.SPF payload in ' + htmlPath);
const end = html.indexOf('</script>', start);
if (end < 0) throw new Error('unterminated <script> after the payload');
const source = html.slice(start, end);

// ---- enough of a browser for the module bodies to evaluate ------------------
const listeners = {};
const sandbox = {
  console,
  URL, URLSearchParams, Request, Map, Set, Headers,
  navigator: { languages: ['de'] },
  requestAnimationFrame: () => {},
  setTimeout, clearTimeout,
  document: {
    readyState: 'complete',
    documentElement: { setAttribute() {} },
    addEventListener() {},
    querySelector: () => null,
    getElementById: () => null
  },
  // The charts branch on window.spf.narrow(), which reads innerWidth. Both
  // widths are exercised below: a phone drops grid columns and clips labels,
  // and that path has to survive too.
  window: {
    innerWidth: 1200,
    location: { hash: '#/de', pathname: '/', search: '', href: 'http://x/' },
    localStorage: null,
    history: { replaceState() {}, state: null },
    addEventListener: (k, f) => { (listeners[k] = listeners[k] || []).push(f); },
    dispatchEvent: () => {}
  },
  // Only donationColumns() touches React, to build a link cell; it is never
  // rendered here, so a stub that records the call is enough.
  React: { createElement: (t, p, c) => ({ t, p, c }) }
};
sandbox.window.window = sandbox.window;
sandbox.window.document = sandbox.document;
sandbox.window.navigator = sandbox.navigator;
sandbox.window.URLSearchParams = URLSearchParams;
sandbox.window.URL = URL;
sandbox.window.setTimeout = setTimeout;
sandbox.window.clearTimeout = clearTimeout;
sandbox.window.requestAnimationFrame = () => {};
sandbox.PointerEvent = class { constructor(t, o) { Object.assign(this, o, { type: t }); } };
sandbox.window.PointerEvent = sandbox.PointerEvent;

vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: 'spf.js' });

const spf = sandbox.window.spf;
const SPF = sandbox.window.SPF;

// ---- what to run ------------------------------------------------------------
// One case per route. The parameter values come from the data, so this follows
// the dataset instead of naming ballots that may not exist next week.
const eventsWith = (category) => SPF.declarations
  .filter((d) => d.category === category)
  .map((d) => String(d.financing_id));

const firstVote = eventsWith('votes')[0];
const firstElection = eventsWith('elections')[0];
const partyYear = String(SPF.events.find((e) => e.type === 'party_financing').year);
const someDonor = SPF.donations.find((r) => r.donor_key)?.donor_key;
const someParty = SPF.donations.find((r) => r.party_key)?.party_key;

const cases = [
  ['votes',     { eventId: firstVote },     'votes/' + firstVote],
  ['elections', { eventId: firstElection }, 'elections/' + firstElection],
  ['parties',   { year: partyYear },        'parties/' + partyYear],
  ['donors',    { year: 'all' },            'donors/all'],
  // The filters live in the hash query string, so the one loader that reads
  // them is run with some set.
  ['donors',    { year: 'all' },            'donors/all?category=votes&min=50000'],
  ['donor',     { key: someDonor },         'donor/' + someDonor],
  ['party',     { key: someParty },         'party/' + someParty]
];

const expected = JSON.parse(fs.readFileSync(expectedPath, 'utf8'));

// ---- run --------------------------------------------------------------------
let failures = 0;
const fail = (msg) => { console.error('  FAIL ' + msg); failures++; };

for (const width of [1200, 380]) {
  sandbox.window.innerWidth = width;
  for (const lang of SPF.langs) {
    for (const [name, params, path] of cases) {
      const loader = spf.loaders[name];
      if (!loader) { fail(`${name}: no such loader`); continue; }

      const label = `${name} [${lang}, ${width}px]`;
      let out;
      try {
        out = loader({
          params,
          request: new Request('http://localhost/' + lang + '/' + path)
        }, lang);
      } catch (e) {
        fail(`${label} threw: ${e && e.message}`);
        continue;
      }
      if (!out || typeof out !== 'object') { fail(`${label} returned ${out}`); continue; }

      for (const field of expected[name] || []) {
        if (out[field] === undefined) fail(`${label} is missing '${field}'`);
      }
    }
  }
}

const runs = cases.length * SPF.langs.length * 2;
if (failures) {
  console.error(`smoke: ${failures} failure(s) over ${runs} loader runs`);
  process.exit(1);
}
console.log(`smoke: ${runs} loader runs OK (${SPF.langs.join('/')}, wide and narrow)`);
