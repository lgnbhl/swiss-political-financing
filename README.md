# Swiss Political Financing — an open, ready-to-analyse dataset

**Who pays for Swiss political campaigns and parties? This project makes that
easier to find out.**

Switzerland's Federal Audit Office (EFK) publishes political-financing disclosures
— campaign budgets, donations, party accounts — on its transparency portal,
[politikfinanzierung.efk.admin.ch](https://politikfinanzierung.efk.admin.ch). The
information is public, but it lives behind a click-through website: to study it you
have to open each vote, election or party one by one and download separate Excel
files. There is no single, tidy dataset to work with.

**This repository fills that gap.** It automatically gathers everything from the
portal and turns it into clean, spreadsheet-ready tables (CSV) that anyone can open
in Excel, R, Python or any data tool — updated every week, in German, French and
Italian. The goal is simple: **lower the barrier to analysing money in Swiss
politics** for journalists, researchers, students and curious citizens.

## What you can do with it

- See **who donated how much** to which campaign, party or candidate, and when.
- Compare **total income and where it came from** across votes, elections and
  parties — donations, own funds, membership fees, events and the rest.
- Compare **budgets against final accounts**: what a campaign expected to take in
  against what it actually did.
- Track changes over time — the data is refreshed weekly and every update is kept
  in the project's history.
- Skip the tedious data-gathering and go straight to the analysis.

One thing you **cannot** do: study spending. Switzerland's disclosure obligation
covers income only, so the EFK publishes no expenditure figures and neither does
this dataset. A missing value never means zero.

No programming is required to *use* the data: just download the CSV files in the
[`data/`](data/) folder, or explore it in the browser. The files are written for
that audience: UTF-8 with a byte-order mark and semicolon-delimited, which is
what Excel on a Swiss or European locale expects, so a downloaded file opens with
the columns split and the accents intact on a double-click. Decimals use `.`.
Reading them in code therefore needs the delimiter spelled out:
`readr::read_delim(path, delim = ";")`, `read.csv(path, sep = ";")` or
`pandas.read_csv(path, sep=";")`. (Not `read.csv2()`: it also switches the
decimal mark to `,` and would mangle the amounts.)

## Explore it in the browser

**→ [felixluginbuhl.com/swiss-political-financing](https://felixluginbuhl.com/swiss-political-financing/)**

[`app/`](app/) holds that trilingual (German, French, Italian) point-and-click
explorer — a static page with no server behind it, rebuilt and republished
automatically after every weekly refresh. It covers donations, income and budgets,
votes and elections, mandate contributions, and offers every table above as a CSV
download. Open `app/index.html` from a checkout to run it offline. See
[`app/README.md`](app/README.md).

## The data, in plain terms

**Pick a language, then use that folder and nothing else.** The portal publishes
the same facts in German, French and Italian, so the repository keeps three
parallel datasets — `data/de/`, `data/fr/` and `data/it/`. They contain identical
figures and differ only in the wording of labels (`Zug` / `Zoug` / `Zugo`). Each
folder is complete on its own; combining them would count every franc three times.

| File (in `data/<lang>/`) | One row is… |
|---|---|
| `exports/declarations.csv` | **One filed disclosure** — the income an actor / campaign / party reported |
| `exports/contributions.csv` | **One donation** (donor, amount, date) |
| `exports/mandate_contributions.csv` | One mandate contribution paid to a party |
| `exports/declaration_candidates.csv` | One candidate supported by a declaration (the link table, no amounts) |
| `forms/forms.csv` | One disclosure form in the portal's catalogue |
| `allowances/allowances.csv` | One donation as listed in the portal's donations view |
| `relationships/financing_events.csv` | One vote, election or party year |
| `relationships/actors.csv` | One actor, with its canton, type and party |
| `relationships/candidates.csv` | One candidate, with their party, canton and election |

There's also a `people/` file reserved for elected candidates' declared interests
(the portal hasn't published these yet — it will fill in automatically once they
appear).

### You can sum these columns directly

A column of francs in `data/<lang>/` can be summed as-is: no filtering, no
de-duplication. That takes some deliberate work, because the official source is
not shaped that way.

The EFK's bulk Excel files repeat a declaration **once per candidate it supports**.
A single CHF 40,000 donation to a group of 36 candidates appears as 36 identical
rows. Summed naively, that overstated declared income roughly fourfold and
donations roughly twofold. Here, the candidate list is split into its own table,
`exports/declaration_candidates.csv`, which carries no amounts — so it cannot
inflate a total. Join it back on `declaration_id` when you want per-candidate
detail.

Two keys tie the tables together, and they are the **same in all three
languages**, so you can compare or join across them:

- `declaration_id` — one filed disclosure, e.g. `elections-1-B-057`
- `contribution_id` — one donation, e.g. `elections-1-B-057-d002`

Because party and canton describe the *candidate* rather than the declaration,
`declarations.csv` exposes them as `candidate_party` / `candidate_canton` only
when every candidate on that declaration agrees; otherwise they are empty and
`candidate_count` tells you how many candidates were involved. About 5% of
declarations back candidates from several parties — one industry association
backs candidates from 11 parties across 23 cantons. Breaking its donations down
by party would count each one eleven times.

To sanity-check a copy of the data yourself:

```sh
Rscript R/checks.R
```

It verifies that the ids are unique, that every donation resolves to a
declaration, and that the totals agree across the three languages. It also prints
reference totals both counted once and summed as-is — see the note on budgets
below.

Alongside the tables, the project keeps a full archive of the **original official
Excel files** in [`files/`](files/) and a raw snapshot of the source data in
[`raw/`](raw/), so nothing is lost and every figure can be traced back to its
source.

### A couple of things to know about the numbers

- **Money amounts** are in Swiss francs (CHF).
- **Every campaign is disclosed twice, so do not sum across both.** An actor files
  a **budget** up front and the **final accounts** afterwards — see the
  `with_budget` column (`TRUE` = budget, `FALSE` = final). Most events carry both,
  and the two rows describe the same francs at two points in time. Adding them up
  turns CHF 92.5M of disclosed donations into CHF 150M that never existed.

  For a headline figure, count each actor's **latest** disclosure once: the final
  accounts where they have been filed, the budget where they have not yet (the
  normal state for a vote that has not happened).
  [`R/disclosures.R`](R/disclosures.R) does exactly that, and
  `Rscript R/checks.R` prints both sets of totals side by side so you can see the
  difference. Use the budget and final rows together only when the comparison
  itself is the point.
- Values are kept **exactly as published** by the EFK, without rounding or
  reformatting. One quirk: a few date cells appear as Excel's internal date numbers
  (e.g. `45987`) instead of a normal date — this is how the source stores them.

## Where the data comes from

All data originates from the **Swiss Federal Audit Office (EFK)** and is official
[Open Government Data](https://opendata.swiss/en/dataset/politikfinanzierung). It is
published under the **"Open use"** terms, which explicitly allow reuse and
redistribution — including a project like this one. The EFK is the source and does
not endorse this repository.

Please cite it as:

> Source: Swiss Federal Audit Office (EFK), *Politikfinanzierung*, retrieved from
> https://politikfinanzierung.efk.admin.ch (catalogued on opendata.swiss,
> "Open use").

For the full licensing details see **[DATA-LICENSE.md](DATA-LICENSE.md)**, and for
the independence notice and responsible-use / data-protection guidance see
**[DISCLAIMER.md](DISCLAIMER.md)**.

---

## For developers

The rest is only relevant if you want to run or modify the collection script
yourself.

An R script ([`R/main.R`](R/main.R)) reads the portal's public JSON API, downloads
the official Excel files and consolidates them into the CSV tables above. A weekly
[GitHub Action](.github/workflows/update-data.yml) re-runs it and commits any
changes, so the repository stays current. New entries appear as new API nodes and
are discovered automatically — nothing is hardcoded.

### Run it locally

Requires R (≥ 4.2). Install the dependencies once:

```r
install.packages(c("httr2","jsonlite","readxl","dplyr","tidyr",
                   "readr","purrr","digest","stringr","fs"))
```

Then, from the repository root:

```sh
Rscript R/main.R
```

### Configuration (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `EFK_LANGUAGES` | `de,fr,it` | Languages to fetch |
| `EFK_ARCHIVE_FORMS` | `true` | Download every individual form `.xlsx` |
| `EFK_ARCHIVE_FORM_LANGS` | `de,fr,it` | Languages for the form-file archive |
| `EFK_REFRESH_FORMS` | `false` | Re-download form files even if already present |
| `EFK_THROTTLE` | `0.15` | Seconds between HTTP requests (politeness) |
| `EFK_MAX_TRIES` | `4` | Retries per request on transient errors |

### How updates work

The scraper is a full, idempotent rebuild. Tables are written in a deterministic
row order, so a run with no upstream changes produces **no git diff** (except the
timestamp in `state/run_info.json`). Individual form files are content-immutable and
are skipped if already archived. When EFK adds or changes data, only the affected
rows and files change in the commit.

### Technical notes on the tables

`declarations`, `contributions` and `mandate_contributions` come from the bulk Excel
exports (the most complete source). The three export categories
(elections / votes / party) have slightly different columns, so each table is a
**union** with a `category` column; columns that don't apply to a category are left
empty. Localized Excel headers are mapped to stable `snake_case` names via a
trilingual dictionary in [`R/config.R`](R/config.R). The `file_sha256` column links
each row to its source Excel file and changes only when the EFK republishes it.

The de-fanning in [`R/exports.R`](R/exports.R) is **positional**, not a
`distinct()`: within one export file the rows for a declaration are contiguous and
donation-major (n donations × n candidates, the candidate list repeating in each
block), so every *n*-th row is kept. De-duplicating instead would silently merge a
declaration's two genuinely identical donations — the current snapshot contains
exactly such a pair, two CHF 11,250 gifts from the same donor on the same day.
Declaration numbering follows row order within an export file, which the portal
keeps identical across languages; `process_exports()` warns if that ever stops
holding rather than emitting ids that quietly fail to line up.

### Full output layout

```
data/<lang>/      one complete dataset per language (de, fr, it)
  exports/        declarations.csv, declaration_candidates.csv,
                  contributions.csv, mandate_contributions.csv
  forms/          forms.csv, form_appearances.csv
  allowances/     allowances.csv, allowance_appearances.csv
  people/         people.csv
  relationships/  financing_events.csv, actors.csv, candidates.csv
  manifest.csv    every downloaded artifact + content sha256
raw/trees/        raw JSON snapshot of every theme × grouping × language
files/
  exports/<lang>/financings_<id>_budget<T|F>.xlsx   bulk Excel files
  forms/<lang>/<campaign_id>_<form_id>.xlsx          every individual filed form
state/run_info.json   last run timestamp, duration, row counts
app/              the browser explorer; index.html is the built artifact
```

Every CSV under `data/` is semicolon-delimited UTF-8 with a byte-order mark, `.`
as the decimal mark and empty (never `NA`) for a missing value — see
`write_table()` in [`R/write_out.R`](R/write_out.R) for why. Rows are sorted on a
stable key so a weekly rebuild diffs only where the data actually changed.

`R/disclosures.R` holds `latest_disclosure()`, the one definition of which
disclosures count once. Both `R/checks.R` and the app read it, so the reference
totals and the published figures cannot drift apart.

### Licensing for reuse

- **Data** — © Swiss Federal Audit Office (EFK), "Open use" (see
  [DATA-LICENSE.md](DATA-LICENSE.md)).
- **Code** — the R scripts and workflow are released under the [MIT License](LICENSE).
