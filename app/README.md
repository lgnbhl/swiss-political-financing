# Politikfinanzierung Schweiz — the exploration app

A trilingual (de / fr / it), fully static single-page app over the CSVs in
[`../data/`](../data). No server, no build toolchain, no network calls: one R
script produces one `index.html` that works over `http` and over `file://`.

```
Rscript app/build_site.R      # -> app/index.html (+ app/lib/)
```

Then open `app/index.html`. The published copy lives at
**[felixluginbuhl.com/swiss-political-financing](https://felixluginbuhl.com/swiss-political-financing/)**;
see *Publishing* below.

Built entirely on R wrappers for React:

| Package | Role |
|---|---|
| [`reactRouter`](https://felixluginbuhl.com/reactRouter/) | Hash routing + JS data loaders that drive all filtering |
| [`muiMaterial`](https://felixluginbuhl.com/muiMaterial/) | Material UI layout and controls |
| [`muiDataGrid`](https://felixluginbuhl.com/muiDataGrid/) | Sortable, filterable, CSV-exportable tables |
| [`muiCharts`](https://felixluginbuhl.com/muiCharts/) | MUI X bar charts |

## Pages

Language is the **first route segment**, so every page in every language is a
shareable URL.

The app is organised around the four questions the EFK's own press releases are
written to answer — who funded each side of a ballot, what was declared for an
election, how a party is financed in a given year, and who the big donors are.
Each of those is a page with a **single-select picker**, and the selection is part
of the path, so a ballot or a year is a plain shareable URL.

| Route | What it shows |
|---|---|
| `#/` | Redirects to the language the reader last chose from the app bar, else the browser's own preference (`navigator.languages`) if it is German, French or Italian, else `#/de`. An explicit `#/:lang/...` URL is never rewritten |
| `#/:lang` | Landing page: four entry cards and the most recent ballot's two camps |
| `#/:lang/votes/:id` | One ballot: what the Yes camp and the No camp declared, stacked by committee, budget beside final accounts; who funded each camp; the per-committee disclosures and the individual gifts |
| `#/:lang/elections/:id` | One scrutiny: declared income by party and by canton of the supported candidates |
| `#/:lang/parties/:year` | One calendar year: each party's income stacked by component, who gives to them, and the mandate contributions its elected officials pay in |
| `#/:lang/donors/:year` | One year or all of them: the biggest donors, where the money comes from, and the full filterable table of every gift |
| `#/:lang/donor/:key` | One donor: total, count, to whom and for what |
| `#/:lang/party/:key` | One party: total, count, distinct donors |
| `#/:lang/data` | Every consolidated table with row/column counts and CSV download links |

Landing on `#/:lang/votes` (or `elections`, `parties`, `donors`) redirects to the
newest selection there is. The paths this app published before it was reorganised —
`donations`, `income`, `campaigns`, `mandates` — redirect to the page that now
answers the same question.

## How the three languages fit in one file

The naive approach — embed `data/de`, `data/fr` and `data/it` — would store every
franc three times. Instead `prepare_data.R` splits the data:

* **core tables** that are language-free, keyed by the scraper's stable IDs and
  carrying every number plus a *key* for each translatable label;
* **one small dictionary per language**, mapping those keys to display labels.

Keys are slugs of the German label (`die-mitte`, `st-gallen`). They are what
travels in the URL, and that is what makes the language switch keep your place:
`?party=die-mitte` means the same thing in all three languages, so
`window.spf.setLang()` can rewrite just the language segment and leave the route
and every filter intact. Had the URL carried translated labels,
`?party=Die%20Mitte` would match nothing on the French page.

Donor names, donor locations and amounts are *not* translated by the EFK.
`check_language_invariants()` asserts that rather than trusting it, and stops the
build if a column assumed to be language-independent ever starts differing.

UI text is not translated at runtime: the whole component tree is built three
times in R, once per language, so every string is an ordinary R value.

## Where the numbers are computed

Every subject page is **URL-driven**. A JS loader (`js/spf-loaders.js`) reads the path
parameter and the hash query string, filters, aggregates and returns rows,
localised column definitions and complete chart prop objects. Neither the pickers
nor the filters hold React state: they write to the URL, the loader re-runs, and
the result flows back into the controls. So every view is linkable and the back
button steps through selections.

Only the landing page and the download page are computed in R at build time
(`aggregate.R`), which otherwise just supplies each picker's option list. The
component tree is declarative and built once, so a block that only sometimes
applies — the joint-disclosure note, an empty state — is always mounted and the
loader returns a style that hides it (`loader_toggle()`).

Charts on loader-driven pages get their `series` / `xAxis` / `yAxis` props injected
by `useLoaderData(chart, as = "series", …)`. The loader returns complete MUI X prop
objects *including live `valueFormatter` functions* — loader data is never
serialised, so functions survive.

## Five things worth knowing about the numbers

**Every campaign is disclosed twice.** An actor files a budget up front
(`with_budget = TRUE`, ids like `votes-18-B-004`) and final accounts afterwards
(`FALSE`, `votes-18-F-004`); 22 of the 31 events carry both. Summing all rows
counts the same francs twice — CHF 80.6M of final plus CHF 69.5M of budgeted
donations reads as a CHF 150M total that does not exist. Every core table
therefore carries `is_latest`: the final accounts where an actor filed them, the
budget where it has not yet (the normal state for a vote that has not happened).
Headline figures and all default views use `is_latest` only. The ballot page is
the one place that shows both flags side by side — that comparison is its point,
and it is the only planned-versus-actual axis the data offers.

The rule itself lives in [`../R/disclosures.R`](../R/disclosures.R), not here: it
is a property of the dataset, and `R/checks.R` uses the same function to print its
reference totals. So the app's headline figures and the pipeline's reported totals
cannot drift apart — both currently CHF 92.5M of donations over 512 of the 905
declarations.

**The EFK publishes no spending.** The disclosure obligation covers income only:
every bulk export has exactly two sheets, `Gesamteinnahmen` and `Zuwendungen`, and
`declarations.csv` has eight `*_income_chf` columns and no expenditure counterpart.
The party page says so in as many words, so a reader does not take absence for
zero. Where the app compares "budgeted" and "final" it is comparing *budgeted
income* with *income actually received*, never spending against a budget.

**No page adds up things that cannot be added.** The dataset spans elections,
ballots and party years between 2023 and 2026; a grand total across them has no
referent, which is what the app's earlier headline cards reported. Every figure
here is scoped to one ballot, one scrutiny or one year. Some ballots need the
same care: several objects go to the same ballot, and a committee campaigning on
two of them may file one disclosure covering both, which the EFK then lists
under each — so the same francs appear on two pages. `joint_event_ids()` finds
those by their signature (one actor, the identical figure, more than one ballot
of the same polling day) and the ballot page says so when one is selected. It is
derived rather than listed: the version that named 24.11.2024 in the loader
missed the joint filing of 09.06.2024 entirely.

**Dates come in two shapes, and one of them used to be lost.** The EFK types
`Gewährungsdatum der Zuwendung` as text (`18.07.2023`) in 41 of the 47 archived
export files and as a *date-typed* cell in the six most recent ones. Sheets are
read with `col_types = "text"` so the three category schemas can be unioned, which
renders a date-typed cell as its bare Excel serial (`46002.0`) — 136 gifts worth
CHF 18.1M with no usable date, silently absent from every per-year view.
`excel_serial_to_date()` in [`../R/exports.R`](../R/exports.R) converts a bare
serial in a plausible range back to `dd.mm.yyyy` and leaves anything that already
looks like a date untouched, so a franc amount can never be reinterpreted as one.
Every donation now resolves from its own date. The app keeps an event-year
fallback anyway, flagged as `year_source`, so the next file the EFK types
differently degrades visibly rather than disappearing.

**Donors are free text, so spellings are grouped.** The same body reaches the
export as `economiesuisse` and `Economiesuisse`, or as
`Zürich Versicherungs-Gesellschaft AG (Unterstützungsbeitrag 2023)` and
`Zürich Versicherungsgesellschaft AG`. `donor_norm()` groups spellings that differ
only in case, accents, punctuation or a *trailing* parenthetical — mechanical
enough that it can never merge two differently named bodies. Names whose words
themselves differ stay separate unless listed in `DONOR_ALIASES`, a short,
exact-match list, so a donor is understated rather than invented: without it
`Hauseigentümerverband (HEV) Schweiz` would sit at CHF 11.0M instead of 16.7M. The
raw spelling stays on every row as `donor_raw`, in the grid and in the CSV.

## Files

Two languages, kept apart: **R builds the page, JavaScript runs it.** R never
writes JavaScript, and the browser files are never templated.

| File | Role |
|---|---|
| `build_site.R` | Orchestrator: configuration, payload, app shell, router, `save_html()` |
| `build_checks.R` | The four checks that fail the build; see *Verifying a change* |
| `prepare_data.R` | Reads all three language folders; emits the core tables, the dictionaries and the download catalogue |
| `i18n.csv` | Every UI string: one row per key, one column per language |
| `i18n.R` | Reads that file. `tr()`, and a `check_i18n()` that fails the build on a duplicate, malformed or untranslated key |
| `components.R` | Design system: the validated palette, the MUI theme, cards, filters, grids |
| `css/app.css` | The stylesheet |
| `aggregate.R` | The pickers' option lists, the filter option lists and the landing page |
| `pages.R` | One function per page — layout only; every figure comes from a loader |
| `js/spf-runtime.js` | `window.spf`: URL helpers, formatters, and `ctx()` |
| `js/spf-charts.js` | Chart prop builders |
| `js/spf-tables.js` | Grid rows and columns |
| `js/spf-loaders.js` | One loader per subject page |
| `js/smoke.js` | Runs every loader against the built page; see *Verifying a change* |
| `index.html`, `lib/` | Build output, committed — and the only two things that get published |

### Configuration

Two environment variables, read at the top of `build_site.R`. Both default to
what the site ships with today, so an unconfigured checkout builds the current
page.

| Variable | Effect |
|---|---|
| `SPF_REPO_URL` | Switches on the "report an error" and "browse the data on GitHub" buttons. Empty by default, because a dead link is worse than no link |
| `SPF_DATA_PUBLISHED` | `true` once `data/` is served next to `index.html`; the download buttons become real links instead of a "not published yet" note |

Both are set as repository variables and passed in by
`.github/workflows/update-data.yml`, which sets `SPF_DATA_PUBLISHED: "true"`:
`publish.yml` ships `data/` alongside the page, so the download buttons are real
links to CSVs served next to `index.html` rather than a "not published yet" note.
`SPF_REPO_URL` is separate — it points at this repository for the source data and
the "report an error" path.

### Publishing

This repository does not serve the app. `.github/workflows/publish.yml` copies
`index.html`, `lib/` and `data/` — the three things the page needs — into
`swiss-political-financing/` in the website repository `lgnbhl/lgnbhl.github.io`,
which serves it at
[felixluginbuhl.com/swiss-political-financing](https://felixluginbuhl.com/swiss-political-financing/).

It publishes what is **committed**; it does not rebuild. So:

* after the weekly scrape, `update-data.yml` rebuilds and commits the page, and
  `publish.yml` picks it up (via `workflow_run` — a `GITHUB_TOKEN` push does not
  fire a `push` trigger);
* after a hand edit, run `Rscript app/build_site.R` and commit `index.html`
  before pushing, or the live page will lag your sources.

The page needs no base path to work in a subdirectory: `lib/` is referenced
relatively and the routing is hash-based.

Two things keep this cheap. The build is **reproducible** — identical data
produces a byte-identical `index.html` (see the `set.seed()` note in
`build_site.R`) — so a week where the EFK published nothing commits and
publishes nothing. And `prune_lib()` deletes whatever `save_html()` copied into
`lib/` that the page does not load: React's development builds and the
shiny.react source map, 2.2 MB that no reader ever requests. What to keep is
read off the page itself, so upgrading a wrapper needs no edit; licence files
are always kept.

### The rule about JavaScript

**Nothing in `js/` is interpolated from R.** They are ordinary files: an editor
highlights them, `node --check` parses them, and no quote has to be escaped
twice. Anything that needs a value from R belongs in the `window.SPF` payload,
not spliced into the source — which is why the palette, the tick count, the bar
gap and the language list travel as `SPF.consts` and `SPF.langs`.

The same rule makes one copy of each loader serve all three languages. A route
is one line:

```r
loader = JS("(a) => window.spf.loaders.votes(a, 'de')")
```

The language is handed in by the route because the route is the only thing that
knows it for certain — it is a literal path segment in each of the three
subtrees, not `:lang`, so it never reaches `params`. That costs three copies of
a two-character string instead of three copies of a 19 KB loader.

A loader's first line is `window.spf.ctx(args, lang)`, which returns that
language's dictionary (`D`), strings (`T`), option lists (`M`), formatters (`F`)
and the constants (`K`).

`css/app.css` follows the same rule: the three values it shares with the R theme
arrive as CSS custom properties in a `:root{}` block, so the file itself is
static.

## Responsive layout

The page is built for a phone first and widens from there. What constrains the
implementation is that **this tree holds no React state of its own**: it is built
once in R and rendered statically, so `useMediaQuery` is not available and there
is no server.

That limit is narrower than "no state at all", and the difference matters when
choosing how to build something. `muiMaterial` ships components that own their
state internally and need neither a server nor a hook from us — the `.triggerId()`
overlays (`Drawer`, `Dialog`, `Menu`, `Modal`, `Popover`, `SwipeableDrawer`) and
the `.static()` tabs — so reach for those first. What is not possible is writing a
*new* stateful component, so a need the package did not anticipate has to be met
another way: conditional rendering by `hide()` / `show()` below, responsiveness by
the three mechanisms here.

Every responsive decision therefore lives in one of exactly three places, and it
is worth knowing which before changing anything:

| Mechanism | Used for | Where |
|---|---|---|
| MUI `sx` breakpoint objects (`list(xs = …, md = …)`) | Card padding, type scale, Grid spans, chart and grid heights | `components.R`, `pages.R` |
| Plain CSS with a `@media` query | The app bar's inline nav, the note dialog | `css/app.css` |
| `window.innerWidth`, read at loader time | Chart label gutters and which grid columns are shown | `window.spf.narrow()` / `keepCols()` / `clip()` in `js/spf-charts.js` |

Vertical spacing is not a fourth mechanism — it is three named constants in
`components.R` (`GAP_LABEL` 8px, `GAP_BLOCK` 16px, `GAP_SECTION` 24px) used in
place of the literals that used to sit at some forty call sites with eight
distinct values between them. Anything smaller than `GAP_LABEL` is micro-spacing
*inside* a component and stays a literal there.

The constants name the rhythm; they are not licence to tighten it. Card padding
(`CARD_PAD`, 14/20px) and the gap between a card's own text and its content are
deliberately larger than the section gaps — the border is close enough already,
and text set hard against it reads as cramped. Both were tried one step tighter
and put back.

A few consequences of that split:

* **The inline nav is hidden in CSS, not with `sx`.** `css/app.css` carries a
  `<style>` in the body and emotion injects its classes into the head, so at equal
  specificity the body rule wins whatever `sx` says. Its media query breaks at
  900px, which is MUI's `md`, so the two systems change at the same width.
* **The mobile nav panel is a `Drawer.triggerId()`; the "coming soon" note is a
  native `<dialog>`.** What decides it is the number of triggers, not React state.

  `Drawer.triggerId(triggerId = "spf-nav-trigger")` holds `open` in the wrapper's
  own state and binds to the hamburger by DOM id, so `open` is never passed and
  none of ours is needed. `closeOnLinkClick` is what closes the panel when a
  NavLink navigates. There is no X, because the wrapper exposes no imperative
  close: the panel is dismissed by the backdrop, by Esc or by tapping a link.
  Those, plus the focus trap and page inertness, are MUI Modal's — which
  reimplements in JavaScript what `<dialog>` gives natively, so they are worth
  re-checking after a `muiMaterial` upgrade (verification step 12).

  The note stays a native `<dialog>` because it has **thirteen triggers**, one
  download button per table on the data page, and `.triggerId` binds a single id.
  One shared dialog opened from `window.spf.soon()` beats thirteen identical ones.
  All three language shells exist in the source but React Router mounts only the
  routed one, so `document.querySelector('dialog.spf-modal')` is unambiguous.
* **Chart heights are set on a wrapper, not on the chart.** `height` is a plain
  numeric prop on `BarChart` and cannot carry breakpoints, so `chart_box()` wraps
  every chart in a `Box` whose `height` *is* an `sx` breakpoint object and lets
  MUI X size the chart from its parent. Call sites use `chart_h(xs, md)`.
* **Loaders read the viewport, and a rotation re-runs the route.**
  `window.spf.watchRotation()` watches `resize`, and when the 600px threshold is
  actually *crossed* — not on every drag — it dispatches a `popstate`, which is
  what re-runs the loader. Note `popstate` and not `hashchange`: this version of
  React Router listens to popstate alone (`h="popstate"` in
  `lib/reactRouter-0.2.0/react-router-dom.js`, no `hashchange` listener exists),
  so a `hashchange` would have been a no-op that looked like a fix. If a future
  router version stops re-running loaders on a same-URL pop, this degrades to
  the old behaviour — stale until the next navigation — not to something broken.
  Dropping columns on a phone loses nothing either way: the desktop grid still
  has them and the CSV export always writes the full row.

## Saying what is clickable

Everything a reader does here is a click on a control or a link, so each is
stated at rest rather than left to a hover — a hover is only discoverable once
you have already guessed, and on a phone it does not exist at all.

* **Pickers and filters** sit in a `control_panel()`: a captioned, bordered box
  on the page plane, with the controls themselves given a white surface and a
  1.5px outline that turns blue on hover and focus (`CONTROL_SX`). The subject
  pickers are `size = "medium"`, not `"small"` — the control *is* the page.
  Inside a panel the control passes `show_label = FALSE`, because a floating
  label repeating the panel caption reads as a bug; the label is still passed and
  becomes the control's `aria-label`.
* **In-table links are underlined**, not merely coloured (`LINK` in `js/spf-tables.js`). Donor and party cells are the way into the drill-down pages and,
  undecorated, a blue cell in a table of blue-ish chrome is not read as a link.
  `click_hint()` says so in words above every grid whose cells link somewhere.
* **Entry cards carry a blue title and a `→`** pinned to the card's right edge,
  plus a lift-and-shadow on hover and a press-down on `:active`. The arrow is the
  same mark in both places, so "→ means this goes somewhere" is one idea.

## Every chart says what it is scoped to

The picker that chose the ballot or the year lives in the page header and
scrolls away, so a chart three screens down would otherwise state a total with
no visible referent — "who gives to the parties" is a different chart in 2023
and in 2024, and nothing on it said which.

`chart_caption()` puts it in the card, directly above the chart, bound to the
loader's `scope` — so it follows the URL like every other figure: the ballot,
the scrutiny, the calendar year, the donor year, or the donor / party on a
drill-down.

It used to be drawn **inside** the chart's SVG, as a `ChartsText` child of the
`BarChart`. SVG text does not reflow, so that meant word-wrapping the caption by
hand into tspans and then sizing the chart's top margin from the resulting line
count — about eighty lines of code and several measured pixel constants, plus a
trap where any helper that overrode `loader_chart()`'s prop list without
`"margin"` silently dropped the reservation and landed the caption on the axis.

Ordinary text in the card wraps by itself. A ballot is titled with the full
wording of the federal act it is about — 23 of the 31 events run past 58
characters, the median is 89 and the longest 210 — and it now reads in full,
with the card growing rather than the plot shrinking.

The chart margins are therefore two constants (`MH`, `MV` in `js/spf-charts.js`).
The one number still worth keeping is that a **vertical** chart reserves more on
top (18 vs 6), because its value axis centres the topmost tick label on the
plot's top edge and half of it sits above the plot.

## Chart tooltips

**One row, for the segment under the pointer** (`TOOLTIP`, passed as
`slotProps = list(tooltip = …)` — this version of MUI X reads the trigger from
`slotProps.tooltip`, and a top-level `tooltip` prop is accepted and ignored).
The default lists every series at that axis position, and a busy ballot stacks
seventeen committees: the tooltip measured **552px tall on an 844px phone**,
covering the chart it was describing. The full breakdown is not lost — it is the
table directly under every chart, which is also what discharges the hidden
legend on the stacked charts.

The tooltip is a Popper portalled to `<body>`, so the chart's own `sx` cannot
reach it and the rest is global CSS in `css/app.css`: the label cell ships as
`white-space: nowrap` and this app's series names are full committee names, so
one row measured 692px wide — fine on a desktop, wider than the whole screen on
a phone. It now wraps, and the width is capped against the viewport; the value
cell stays `nowrap`, because a franc figure broken across two lines is
unreadable as a number.

**Those rules repeat the class name** (`.MuiChartsTooltip-labelCell.MuiChartsTooltip-labelCell`).
MUI X applies each of these classes twice on the element precisely to raise its
own specificity, so a single-class rule loses however it is nested.

## Chart tooltips, and reading a chart with a finger

Two things had to be true for a phone reader: that a tooltip appears at all, and
that it names the bar in full.

**Appearing.** MUI X resolves the item under the pointer from pointer
*movement*. On a touch screen a press that does not move never resolves one, so
a tap and a press-and-hold both showed nothing; only a press that happened to
drift sideways worked, which made it look intermittent rather than broken.
`window.spf.touchNudge()` — one delegated listener for the whole app — sends a
synthetic 1px `pointermove` on touch press, twice a frame apart. Press-and-hold
then reads reliably, and sliding along the bars moves between them.

It is deliberately *not* paired with `touch-action: none` on the surface: that
would make a vertical swipe inspect instead of scrolling, and the charts are
nearly the full width of a phone, so there would be little left to scroll from.

**Latching a tap was tried and rejected.** The only way to keep the tooltip after
the finger lifts is to stop the lift reaching the chart, which leaves it holding
a pointer it believes is still down. Measured: 9 taps in 16 latched, and some of
the rest showed the *previous* bar's figures under the new bar's name. A wrong
amount beside a donor's name is the one failure this site must not have. So the
tooltip is transient, and `chart_card()` states the interaction on touch devices
— under `@media (hover: hover) and (pointer: fine)` it is hidden, because what
matters is the input device, not the width of the screen.

**Naming the bar.** `trigger: 'axis'` heads the tooltip with the category and
lists the series at that position. That header is the only place a reader can see
a category whose axis label had to be clipped to fit, so it is the default
wherever the series count is bounded — one for a ranked chart, two for the
camp-coloured ones, seven for a party's income components. Measured on a phone,
the tallest is 264px.

`trigger: 'item'` (`TOOLTIP_ITEM`) is the exception, for the one unbounded chart:
a busy ballot stacks seventeen committees on a band, and listing them measured
552px tall on an 844px phone, covering the chart it described. Note that an item
tooltip labels the row from `series.label`, so on a *single-series* ranked chart
it shows the amount with no name at all — which is why axis is the default.

The axis keeps the full names as its data and clips only when drawing a tick,
via a `valueFormatter` that checks `context.location === 'tick'`. The axis stays
narrow; the tooltip gets the whole name.

## The grid's own chrome

Everything inside the DataGrid — "Rows per page", the column and filter panels,
the export menu, the empty-state message — is out of `i18n.R`'s reach. MUI X
ships a translation per locale and `grid_locale_text()` hands the grid the right
one (`deDE` / `frFR` / `itIT`; there is no de-CH bundle, and the difference is
orthographic, so German Switzerland reads `deDE` correctly).

Those bundles also bring their locale's *number* formatting into the pagination
footer — `1–25 von 1.174` in German, `1 174` in French — and this app writes
every figure the Swiss way in all three languages on purpose. So the one string
that carries digits, `paginationDisplayedRows`, is replaced with one that
formats through `window.spf.fmt()` and takes only its preposition from
`cols.rows_of`. Note the key: this version of MUI X renders the footer itself and
reads the top-level `paginationDisplayedRows`; overriding the nested
`MuiTablePagination.labelDisplayedRows` instead is accepted and silently ignored.

## Text that has to survive a data refresh

The data is rebuilt weekly, so no interface string may state a figure the next
refresh could falsify — "about one declaration in twelve", "6% of income", "160
candidacies from eleven parties" were all true of one snapshot and are the kind of
sentence that quietly goes wrong. Notes state the *rule*; the figure beside them
comes from the loader, which recomputes it (the elections page's mixed-party note
sits under a KPI that measures exactly the share it refers to). Worth re-checking
`i18n.R` for digits whenever a note is edited.

## Colours

The categorical palette is the data-viz reference palette, validated against this
app's actual chart surface rather than eyeballed:

```
node scripts/validate_palette.js \
  "#2a78d6,#eb6834,#1baf7a,#eda100,#e87ba4,#008300,#4a3aa7" \
  --mode light --surface "#ffffff"
```

Lightness band, chroma floor, CVD separation (worst adjacent ΔE 9.1) and the
normal-vision floor (worst adjacent 19.6) all pass. Three slots fall below 3:1
contrast, which triggers the "relief" rule — discharged by construction here,
because every chart sits on a page that also shows the same figures in a table.
Ranked bar charts are single-series and use slot 1 only: colour follows the
entity, so it must never track a bar's rank.

Stacked segments are separated by a 1.5px stroke in the surface colour at 85%
opacity — MUI X stacks them flush, and without it a twenty-committee stack reads
as one block with faint banding. **The class is `MuiBarChart-element` in this
version, not `MuiBarElement-root`**, which is what the rule used to name; it
matched nothing, so the separator went undrawn for as long as it was documented.
The stroke is translucent because it straddles the segment edge and eats half
its width into the fill: a party year puts 15 segments under 2px thick on
screen, and an opaque stroke painted those out completely — which on this site
means "nothing was filed", the one thing a bar must never say by accident.

**Blue and red are the camp encoding and nothing else.** On this site blue means
Yes / *pour* and red means No / *contre*, so an informational callout painted in
either reads as taking a side. Every note card therefore carries one neutral
accent, `ACCENT_NOTE` (slot 2, orange), and `note_card()` does not vary it per
page — one accent also makes "this is a note, not a figure" learnable after the
first page. The camp colours survive where they are the encoding: the two
Yes/No KPI cards on the ballot page, and the bars themselves.

The Yes-camp / No-camp comparison is the app's one genuinely polar encoding, so it
does not use the categorical slots at all. It uses the documented diverging pair
as two **ordinal ramps**, darkest step first, validated as ramps rather than as a
categorical set:

```
node scripts/validate_palette.js "<ramp>" --ordinal --mode light --surface "#ffffff"

CAMP_YES     #0d437f,#1758a1,#246dc3,#3784e1,#609dea,#88b6f1   light end 2.10:1
CAMP_NO      #830011,#a60b1c,#c91c28,#e9343a,#f56661,#fc8f87   light end 2.23:1
BUDGET_RAMP  #444444,#585858,#6e6e6e,#848484,#9b9b9b,#b2b2b2   light end 2.12:1
```

All three pass monotone lightness, the ΔL gap and the light-end floor, and the two
poles pass against each other as a categorical pair (`--pairs all`, worst CVD
ΔE 24.1 protan, normal-vision 32.3). **The six steps are also the cap on how many
committees are drawn separately**: past five the remainder folds into one "other"
segment, because cycling a ramp would give two contributors the same colour. The
ballot chart hides its legend — a busy event puts 17 committees on one axis — and
the per-committee table directly beneath it is the identity channel that
discharges the relief rule.

**A budget bar is grey on every ballot; a final-accounts bar carries its camp's
colour on every ballot.** The reader is here for what a campaign actually raised,
and the plan belongs beside that figure without competing with it. The rule is
unconditional, which is what makes the page safe to leave running for years:
**no bar is ever restyled because of what else the ballot contains, and a bar is
absent if and only if nothing was filed for it.** A ballot that has not happened
yet therefore shows grey only — the honest reading, since no final accounts
exist. Its camp is still named on the axis and repeated in the colour of the two
camp figures above the chart.

The bands are derived per `(camp, disclosure)` from the declarations themselves,
so when the EFK later files final accounts for a ballot that has only a budget
today, the chart grows from two bars to four on the next data refresh with no
code change — see the verification step below, which checks exactly that.

Encoding the disclosure in the camp hue instead was tried and rejected on
measurement: muting the hue enough to read as "provisional" puts Yes-budget and
No-budget ΔE 9.0 apart, under the normal-vision floor of 15.

The app is light-mode only. Rather than flip the palette automatically, which the
method forbids, a dark mode would need its own validated steps.

## What the page says about its own state

Three things the app used to leave unsaid.

**The document's identity.** `save_html()` writes its own minimal head, so
`finish_head()` in `build_site.R` patches the result: a `<title>`, a
description, `theme-color` (`INK$bar`, so a phone's browser chrome continues the
app bar), Open Graph and Twitter tags, and a favicon. The icon is the *same*
Swiss cross the app bar draws — `swiss_cross()` in `components.R` is the single
source, inlined as a `data:` URI so the built page still requests nothing over
the network. It also corrects `<html lang>` from `en` to `de` and drops the
duplicate `<meta charset>` that `save_html()` and `muiMaterialPage()` each emit.

One document cannot carry three `<title>`s, so the head ships the German pair
and `window.spf.setTitle()` rewrites the title, the description and `<html lang>`
at first paint and on every language switch, from `window.SPF.meta_page`.

**Loading.** Nothing: the page is blank until React has parsed and mounted. A
boot mark and a route progress bar existed, driven from outside React's tree by
a `MutationObserver`; they were dropped along with the SVG caption machinery, as
a deliberate trade of polish for code. The document lost ~260 KB in the same
change, which is most of what they were covering for.

**Absence.** A block that simply disappears is indistinguishable from one that
failed to draw, and on this site an absent bar is a factual claim — *nothing was
filed*. So `hide(cond)` now has a complement, `show(cond)`, and the two are
issued as a pair: `donorsStyle` / `donorsNoneStyle` on the votes and party
pages, `mandatesStyle` / `mandatesNoneStyle` on the party page. Exactly one of
each pair is ever visible, and the hidden branch is replaced by a `note_card()`
that states the rule (never a figure — see the section above).

`imputedStyle` and `jointStyle` are notes themselves and correctly stay silent
when their condition does not hold, so they have no complement.

## Reaching it with a keyboard

`skip_link()` is the first child of the shell, so it is the first thing the
keyboard reaches; without it every navigation cost nine tab stops through the
bar before the page. It is a `<button>` calling `window.spf.skipToMain()`, not
the usual `<a href="#main">`: this app is hash-routed, and an anchor to a
fragment would overwrite the route and navigate the reader away from the page
they were trying to skip into. It lands on the routed `Container`, which is now
a `<main>` landmark with `id="spf-main"` and `tabIndex = -1`.

Focus is styled on everything focusable, not just the entry cards: white on the
dark chrome (nav pills, the language switch, the sheet), the link blue on light
surfaces. The UA's own ring is a thin dark outline and is effectively invisible
on `#1a1a19`.

## Verifying a change

**`Rscript app/build_site.R` is the gate.** It is what CI runs, and a non-zero
exit fails the weekly job before anything is committed — which matters because
`index.html` is a committed artefact that an unattended job rebuilds and pushes.
The checks, in `build_checks.R`:

| Check | Catches |
|---|---|
| `check_js()` | `node --check` over `js/*.js` — a stray bracket, before a browser sees it |
| `check_i18n()` / `check_i18n_usage()` | a key the R source asks for and the CSV does not have; a duplicate or malformed key; an empty cell in any language. Also reports keys nothing uses |
| `check_loaders()` | runs **every loader, in every language, at desktop and phone width**, against the data just embedded, and requires each to return the fields its page reads |
| `check_palette()` | an income component the EFK added that `SERIES` has no colour slot for — two components in the same colour misstate where a party's money came from |
| `check_html_shell()` | a second `<html>` or an unbalanced `<body>` — what a muiMaterial upgrade once shipped, because browsers recover from it silently |
| `build_report()` | writes `build-report.json` and fails past 4 MB, so a size regression shows up in the commit diff |

`check_loaders()` closes the seam nothing used to cover. The R side and the
JavaScript side agree by convention — a page reads `sumFmt`, a loader returns it
— and a mismatch built cleanly and broke only in a browser. The expected fields
are not written out anywhere: they are collected from the page trees themselves
(`page_selectors()`), so adding a figure to a page automatically requires its
loader to supply it.

The build also fails loudly on a language folder that has drifted out of
alignment, an unrecognised vote-position wording, and an unrecognised
`anonymous_donation` value.

What it still cannot check is how any of it *looks*. After a change, by hand:

1. `#/` lands on a language; the nav, headings and column headers are in that
   language on all six pages of all three languages.
2. Apply two filters plus a minimum amount on the donors page, then switch
   language: the filters, the selected year and the row count must survive, with
   labels translated. This is the canonical-key test.
3. The donors-page headline figures must be byte-identical in de, fr and it.
   Drift means the language join is duplicating rows.
4. `#/de/votes/999`, `#/de/parties/1999` and `#/de/donor/does-not-exist` must each
   render the error element, not a blank page.
5. The ballot chart must adapt to what was filed, and only to that:
   `#/de/votes/28` (14.06.2026) has a budget only, so two grey bars;
   `#/de/votes/12` has all four, grey budget beside coloured final;
   `#/de/votes/7` has a Yes camp and no No camp and must not draw an empty band.
   Grey must mean "budgeted" on all three — if a budget bar takes a camp colour
   on some ballot, the encoding has regressed.
6. **The chart must grow by itself as filings arrive.** On `#/de/votes/28`, add
   simulated final accounts in the console and re-enter the route:

   ```js
   const S = window.SPF, src = S.declarations.filter(
     d => String(d.financing_id) === '28' && d.category === 'votes' && d.with_budget);
   src.forEach(d => { d.is_latest = false; });
   S.declarations.push(...src.map(d => ({ ...d, with_budget: false,
     declaration_id: d.declaration_id.replace('-B-', '-F-') + '-sim',
     total: Math.round(d.total * 1.12), is_latest: true })));
   ```

   The chart must go from two bands to four (`Ja · Budget`, `Ja · definitiv`,
   `Nein · Budget`, `Nein · definitiv`), the budget bars must stay grey, the two
   camp figures must switch to the final amounts, and the disclosure chip must
   change from "nur Budgetzahlen" to "Budget und definitive Zahlen".
7. **On a phone** (DevTools device toolbar, 390×844 and 360×740): the app bar is
   one row with a hamburger; the sheet opens, Esc and the backdrop close it, and
   tapping a link navigates *and* closes it. No page scrolls horizontally in any
   language — a wide table scrolls inside its own card, never the document.
8. With `SPF_DATA_PUBLISHED=true` — what CI builds with — every button on
   `#/de/data` is a real `../data/<lang>/…` link. Rebuilding with the variable
   unset must fall back to the note, leaving no `<a download>` in the table.
9. Cross-check against the EFK's own releases. `#/de/parties/2024` must rank SP
   CHF 8.23M, PLR 6.63M, UDC 2.82M, Le Centre 2.61M; `#/de/donors/all` must total
   CHF 92'518'414, which is what `Rscript R/checks.R` prints as the counted-once
   reference.
10. **The head.** Exactly one `<title>` and one `<meta charset>` in
    `index.html`, `<html lang="de">`, and the favicon renders in the tab. Then
    open `#/fr/votes/28` and confirm the tab reads French; click `IT` and it
    must change without a reload, along with `<html lang>`.
11. **Empty states.** On `#/de/votes/28`, a budget-only ballot: where the donors
    chart would be there must be a note, not a gap. Apply an impossible filter on
    `#/de/donors/all` and the empty note must have a body, not a blank
    right-hand column.
12. **Keyboard.** Tab from a cold load: the skip link is first, is visible when
    focused, and lands on the content. Every nav pill, language button and sheet
    control must show a ring on the dark bar.

    Then open the nav panel with the keyboard — focus the hamburger, press Enter.
    Focus must move *into* the panel, Tab must wrap inside it rather than escape to
    the page behind, the page behind must not be focusable, and Esc must return
    focus to the hamburger. All four are MUI Modal's, not the browser's.
13. **Rotation.** At 390×844 in the device toolbar, rotate to landscape — the
    grid must regain its full column set without a manual navigation. Drag a
    desktop window across 600px once: it must re-run once, not continuously.
14. **The chart caption.** At 390px on `#/de/votes/24` — a long federal-act
    title — the caption above the chart must wrap over as many lines as it needs
    with the card growing to fit, and must not be clipped or overlap the plot.
