# pages.R
# ---------------------------------------------------------------------------
# One function per page. Each takes the prepared data and a language, and
# returns a component tree with that language's text already in it.
#
# The whole component tree is built three times, once per language, and all
# three live in the same index.html under /de, /fr and /it. Text is therefore
# plain static R -- no translation plumbing at runtime -- and the language
# switch is an ordinary client-side navigation.
#
# The four subject pages all have the same shape: a single-select picker for the
# thing being looked at, headline figures scoped to that thing, two charts, and
# the tables the charts are read against. Everything numeric arrives from the
# route's loader (js/spf-loaders.js), so the page functions are layout only.
# ---------------------------------------------------------------------------

# Shorthand: the string for `key` in the language being built.
t_ <- function(key, lang) tr(key, lang)

# Absolute in-app path for the language being built. Segments are joined with a
# separator each -- `paste0("/", "parties", "2024")` would silently produce
# "/parties2024", which routes to the 404 rather than to the page.
p_ <- function(lang, ...) paste0("/", paste(c(lang, unlist(list(...))), collapse = "/"))

# The EFK's own portal, in the language being built. The language segment sits
# under /app/ -- the bare /de redirects, but only to the portal's front door, so
# link to the app directly. Defined once because two pages carry this button.
efk_url <- function(lang) paste0("https://politikfinanzierung.efk.admin.ch/app/", lang)

# What these figures are and are not: declared income, not campaign spending,
# and the EFK is the source rather than an endorser. It carries the way out to
# the EFK's own portal, and -- once the repository is configured -- the way to
# report an error.
#
# The landing page and the data page both end with it, and they must not be able
# to say it differently.
truth_card <- function(lang, repo_url) {
  note_card(
    t_("home.truth_title", lang),
    t_("home.truth_text", lang),
    actions = tagList(
      Button(t_("home.truth_efk", lang), variant = "outlined", size = "small",
             component = "a", target = "_blank", rel = "noopener",
             href = efk_url(lang)),
      # A dead link is worse than no link, so this appears only once REPO_URL
      # is set (build_site.R).
      if (nzchar(repo_url)) {
        Button(t_("home.truth_report", lang), variant = "outlined", size = "small",
               component = "a", target = "_blank", rel = "noopener",
               href = paste0(repo_url, "/issues/new"))
      }
    )
  )
}

# Build-time integer formatting for the download table -- the only figures still
# rendered in R. Swiss usage puts a typographic apostrophe between thousands in
# all three languages, so this needs no per-language branch.
fmt_int_r <- function(x) formatC(x, format = "d", big.mark = "’")

# The row of headline figures every subject page opens with. It lays out however
# many cards it is given: two across on a phone in every case, and on a wide
# screen one row of whatever that number is.
#
# The cell size used to be the caller's problem -- kpi_cell() covered the
# four-card pages and the three three-card pages each wrote their own
# `Grid(size = list(...))`, seventeen of them. Counting the children is the
# whole of the decision, so the row makes it.
KPI_WIDE <- c("4" = 3, "3" = 4, "2" = 6, "1" = 12)

kpi_row <- function(...) {
  cards <- Filter(Negate(is.null), list(...))
  md <- KPI_WIDE[[as.character(min(length(cards), 4))]]
  cells <- lapply(cards, function(c) Grid(size = list(xs = 6, md = md), c))
  do.call(Grid, c(list(container = TRUE, spacing = 2), cells))
}

# A block and the note that takes its place when there is nothing to show.
#
# The component tree has no state, so both are always mounted and the loader
# decides which is visible -- it returns `<base>Style` and `<base>NoneStyle`, and
# exactly one of them is `display: none`. Naming the pair once here means the two
# selectors cannot drift apart, which is the failure this shape invites: a chart
# that vanishes with no note in its place reads as a rendering fault, and on this
# site an absent bar is a factual claim.
loader_or_note <- function(base, present, absent) {
  tagList(
    loader_toggle(paste0(base, "Style"), present),
    loader_toggle(paste0(base, "NoneStyle"), absent)
  )
}

# The picker line: one control, and the loader's own description of what is
# currently selected. It is passed to page_head() as the header's `control`, so
# on a wide screen it sits opposite the title, in the half of the header row the
# lead's measure leaves free -- the control and the sentence describing what it
# selected stay together either way.
#
# 440px, not a share of the row: the panel holds one field and two lines of
# subtitle, and a column sized as a fraction of the window grew to something the
# content could not fill on a wide screen.
PICKER_W <- 440

picker <- function(label, base, subtitle_selector = "subtitle") {
  control_panel(
    label,
    sx = list(width = list(xs = "100%", md = PICKER_W)),
    single_select(label, base, show_label = FALSE, width = PICKER_W),
    useLoaderData(
      Typography(variant = "body2", color = "text.secondary", sx = list(mt = 1)),
      as = "children", selector = subtitle_selector
    )
  )
}

# =============================================================================
# LANDING
# =============================================================================
page_home <- function(D, lang, repo_url) {
  latest <- home_latest(D, lang)

  # The one figure the landing page states. A ballot with a date is a quantity
  # that exists; a total spanning four years, three kinds of financing and two
  # disclosure rounds is not, which is what the old headline cards reported.
  latest_panel <- if (!is.null(latest)) {
    # Colour is the camp, and a single series would paint both bars from slot 1,
    # so each camp is its own one-value series sharing a stack.
    chart <- BarChart(
      layout = "horizontal",
      skipAnimation = TRUE,
      hideLegend = TRUE,
      borderRadius = 4,
      margin = list(left = 4, right = 28, top = 4, bottom = 4),
      grid = list(vertical = TRUE),
      slotProps = list(tooltip = TOOLTIP),
      yAxis = list(list(scaleType = "band", width = 120,
                        categoryGapRatio = BAR_GAP$categoryGapRatio,
                        barGapRatio = BAR_GAP$barGapRatio,
                        data = c(t_("votes.kpi_yes", lang), t_("votes.kpi_no", lang)))),
      xAxis = list(list(valueFormatter = js_short(lang), tickNumber = TICKS)),
      series = list(
        list(data = list(round(latest$yes), NULL), stack = "c",
             color = CAMP_POLE$yes, label = t_("votes.kpi_yes", lang),
             valueFormatter = js_chf(lang)),
        list(data = list(NULL, round(latest$no)), stack = "c",
             color = CAMP_POLE$no, label = t_("votes.kpi_no", lang),
             valueFormatter = js_chf(lang))
      ),
      sx = CHART_SX
    )

    Card(
      sx = CARD_SX,
      CardContent(
        sx = CARD_PAD,
        Typography(t_("home.latest.title", lang), variant = "overline",
                   color = "text.secondary", sx = list(display = "block")),
        Typography(latest$label, variant = "h6", sx = list(mt = 0.5, mb = 0.25)),
        Typography(t_("home.latest.sub", lang), variant = "body2",
                   color = "text.secondary", sx = list(mb = GAP_LABEL)),
        chart_box(220, chart),
        NavLink(
          to = p_(lang, "votes", latest$id),
          style = JS("() => ({ textDecoration: 'none' })"),
          Button(t_("home.latest.open", lang), variant = "contained", size = "small",
                 sx = list(mt = 1))
        )
      )
    )
  }

  page(
    # ---- hero, with the most recent ballot beside it ----
    # Two columns, for the same reason page_head() has two: a headline and a
    # paragraph keep a readable line length however wide the window is, so on
    # their own they leave the right half of the band empty. The ballot card is
    # the page's one figure, so it is the right thing to put there -- and it is
    # the hero's equivalent of the subject pages' picker. With no ballots to show
    # it falls away and the hero takes the full column.
    Grid(
      container = TRUE, spacing = 3, sx = list(pt = list(xs = 1, md = 2)),
      alignItems = "center",
      Grid(
        size = list(xs = 12, md = if (is.null(latest_panel)) 12 else 7),
        Typography(t_("home.title", lang), variant = "h3",
                   sx = list(fontWeight = 800, letterSpacing = "-0.025em", mb = 1.5,
                             fontSize = list(xs = "1.95rem", sm = "2.6rem", md = "3rem"))),
        Typography(t_("home.lead", lang), variant = "body1", color = "text.secondary",
                   sx = list(fontSize = list(xs = "1rem", md = "1.08rem"),
                             lineHeight = 1.65, maxWidth = "58ch")),
        # How current the figures are, next to the claim they support rather than
        # only in the footer. On a weekly-refreshed dataset this is the first
        # thing a sceptical reader looks for, and it was three screens down.
        if (!is.na(D$as_of)) {
          Typography(paste(t_("footer.as_of", lang), D$as_of),
                     variant = "caption", color = "text.secondary",
                     sx = list(display = "block", mt = GAP_BLOCK))
        }
      ),
      if (!is.null(latest_panel)) Grid(size = list(xs = 12, md = 5), latest_panel)
    ),

    # ---- the four entry points ----
    # Its own heading rather than section()'s h6: this is the landing page's one
    # sub-heading and it carries the page's scale, not a table's.
    section(
      NULL,
      Typography(t_("home.explore", lang), variant = "h5",
                 sx = list(fontSize = list(xs = "1.3rem", md = "1.5rem"))),
      Grid(
        container = TRUE, spacing = 2,
        entry_card(p_(lang, "votes"), t_("home.cards.votes.title", lang),
                   t_("home.cards.votes.text", lang)),
        entry_card(p_(lang, "elections"), t_("home.cards.elections.title", lang),
                   t_("home.cards.elections.text", lang)),
        entry_card(p_(lang, "parties"), t_("home.cards.parties.title", lang),
                   t_("home.cards.parties.text", lang)),
        entry_card(p_(lang, "donors"), t_("home.cards.donors.title", lang),
                   t_("home.cards.donors.text", lang))
      )
    ),

    # ---- downloads + provenance ----
    card_pair(
      note_card(
        t_("home.downloads_title", lang),
        t_("home.downloads_text", lang),
        actions = NavLink(
          to = p_(lang, "data"),
          style = JS("() => ({ textDecoration: 'none' })"),
          Button(t_("home.downloads_link", lang), variant = "contained", size = "small")
        )
      ),
      truth_card(lang, repo_url)
    )
  )
}

# =============================================================================
# VOTES  (one ballot at a time)
# =============================================================================
page_votes <- function(D, lang) {
  page(
    page_head(t_("votes.title", lang), t_("votes.lead", lang),
              control = picker(t_("votes.select", lang), p_(lang, "votes"))),

    loader_toggle(
      "jointStyle",
      note_card(t_("votes.joint_title", lang), t_("votes.joint_text", lang))
    ),

    kpi_row(
      loader_kpi(t_("votes.kpi_yes", lang), "yesFmt",
                 t_("votes.kpi_sub_camp", lang), accent = CAMP_POLE$yes),
      loader_kpi(t_("votes.kpi_no", lang), "noFmt",
                 t_("votes.kpi_sub_camp", lang), accent = CAMP_POLE$no),
      # The only KPI whose sub-line is a finding rather than a fixed caption:
      # the loader words the gap ("more on the Yes side", "roughly even").
      loader_kpi(t_("votes.kpi_gap", lang), "gap", from_loader("gapNote")),
      loader_kpi(t_("votes.state_label", lang), "state")
    ),

    # Stacked rather than side by side: the donor card is hidden on a ballot with
    # no disclosed gifts, and a half-width sibling would leave a gap.
    chart_card(lang, t_("votes.chart_camps", lang), t_("votes.chart_camps_sub", lang),
               # The one unbounded chart: a busy ballot stacks seventeen
               # committees on a band, so the tooltip names the segment under
               # the finger rather than listing them all.
               loader_bar("camps", height = chart_h(280, 400),
                          horizontal = FALSE, tooltip = TOOLTIP_ITEM)),

    loader_or_note(
      "donors",
      chart_card(lang, t_("votes.chart_donors", lang), t_("votes.chart_donors_sub", lang),
                 loader_bar("donors", height = chart_h(300, 420), legend = TRUE)),
      note_card(t_("empty.donors_title", lang), t_("empty.donors_text", lang))
    ),

    section(
      t_("votes.tbl_decl", lang),
      grid_card(loader_grid(lang, "politikfinanzierung-abstimmung-offenlegungen",
                            height = 380, sort_field = "final",
                            rows_selector = "declRows",
                            columns_selector = "declColumns"))
    ),

    section(
      t_("votes.donations_here", lang),
      click_hint(lang),
      grid_card(loader_grid(lang, "politikfinanzierung-abstimmung-zuwendungen", height = 520))
    )
  )
}

# =============================================================================
# ELECTIONS  (one scrutiny at a time)
# =============================================================================
page_elections <- function(D, lang) {
  page(
    page_head(t_("elections.title", lang), t_("elections.lead", lang),
              control = picker(t_("elections.select", lang), p_(lang, "elections"))),

    kpi_row(
      loader_kpi(t_("elections.kpi_income", lang), "incomeFmt",
                 t_("elections.kpi_sub_income", lang)),
      loader_kpi(t_("elections.kpi_decl", lang), "count",
                 t_("elections.kpi_sub_decl", lang)),
      loader_kpi(t_("elections.kpi_actors", lang), "actors",
                 t_("elections.kpi_sub_actors", lang)),
      loader_kpi(t_("elections.kpi_mixed", lang), "mixedPct",
                 t_("elections.kpi_sub_mixed", lang))
    ),

    note_card(t_("elections.multi_title", lang), t_("elections.multi_text", lang)),

    card_pair(
      chart_card(lang, t_("elections.chart_party", lang),
                 t_("elections.chart_party_sub", lang),
                 loader_bar("party", height = chart_h(320, 460))),
      chart_card(lang, t_("elections.chart_canton", lang),
                 t_("elections.chart_canton_sub", lang),
                 loader_bar("canton", height = chart_h(340, 560)))
    ),

    section(
      t_("elections.tbl_decl", lang),
      grid_card(loader_grid(lang, "politikfinanzierung-wahl-offenlegungen",
                            height = 420, sort_field = "final",
                            rows_selector = "declRows",
                            columns_selector = "declColumns"))
    ),

    section(
      t_("elections.donations_here", lang),
      click_hint(lang),
      grid_card(loader_grid(lang, "politikfinanzierung-wahl-zuwendungen", height = 520))
    )
  )
}

# =============================================================================
# PARTY FINANCING  (one calendar year at a time)
# =============================================================================
page_parties <- function(D, lang) {
  # The second half of the page, which only exists on a year where mandate
  # contributions were filed. It takes its own heading with it when it goes,
  # so the note that replaces it has to name what is missing.
  divider <- list(borderTop = "1px solid", borderColor = "divider", pt = GAP_SECTION)

  page(
    page_head(t_("parties.title", lang), t_("parties.lead", lang),
              control = picker(t_("parties.select", lang), p_(lang, "parties"))),

    kpi_row(
      loader_kpi(t_("parties.kpi_total", lang), "totalFmt",
                 t_("parties.kpi_sub_total", lang)),
      loader_kpi(t_("parties.kpi_parties", lang), "parties",
                 t_("parties.kpi_sub_parties", lang)),
      loader_kpi(t_("parties.kpi_named", lang), "namedPct",
                 t_("parties.kpi_sub_named", lang))
    ),

    note_card(t_("income.no_spending_title", lang),
              t_("income.no_spending_text", lang)),

    chart_card(lang, t_("parties.chart_income", lang), t_("parties.chart_income_sub", lang),
               loader_bar("income", height = chart_h(300, 440), legend = TRUE)),

    loader_or_note(
      "donors",
      chart_card(lang, t_("parties.chart_donors", lang), t_("parties.chart_donors_sub", lang),
                 loader_bar("donors", height = chart_h(320, 460), legend = TRUE)),
      note_card(t_("empty.donors_title", lang), t_("empty.donors_text", lang))
    ),

    section(
      t_("parties.tbl_decl", lang),
      grid_card(loader_grid(lang, "politikfinanzierung-parteien", height = 420,
                            sort_field = "total",
                            rows_selector = "declRows",
                            columns_selector = "declColumns"))
    ),

    loader_or_note(
      "mandates",
      page(
        sx = divider,
        page_head(t_("parties.mandates_title", lang), t_("parties.mandates_lead", lang)),
        chart_card(lang, t_("parties.chart_mandates", lang),
                   t_("parties.chart_mandates_sub", lang),
                   loader_bar("mandates", height = chart_h(240, 300))),
        section(
          t_("parties.tbl_mandates", lang),
          grid_card(loader_grid(lang, "politikfinanzierung-mandatsbeitraege", height = 460,
                                rows_selector = "mandRows",
                                columns_selector = "mandColumns"))
        )
      ),
      Box(sx = divider,
          note_card(t_("empty.mandates_title", lang), t_("empty.mandates_text", lang)))
    )
  )
}

# =============================================================================
# DONORS  (one year, or all of them)
# =============================================================================
page_donors <- function(D, lang) {
  page(
    # The year picker governs the whole page, charts and table alike, which is
    # why the table below has every filter *except* a year.
    page_head(
      t_("donors.title", lang), t_("donors.lead", lang),
      control = control_panel(
        t_("donors.select", lang),
        # Narrower than the other three: the options are years, not ballot
        # titles, so a 440px field would be mostly empty box.
        sx = list(width = list(xs = "100%", md = 300)),
        single_select(t_("donors.select", lang), p_(lang, "donors"), width = 300,
                      show_label = FALSE)
      )
    ),

    kpi_row(
      loader_kpi(t_("donors.kpi_total", lang), "sumFmt",
                 t_("donors.kpi_sub_total", lang)),
      loader_kpi(t_("donors.kpi_count", lang), "donorCount",
                 t_("donors.kpi_sub_count", lang)),
      loader_kpi(t_("donors.kpi_share", lang), "topShare",
                 t_("donors.kpi_sub_share", lang))
    ),

    # Uneven: twenty ranked donors need the room, two bands do not.
    card_pair(
      chart_card(lang, t_("donors.chart_top", lang), t_("donors.chart_top_sub", lang),
                 loader_bar("top", height = chart_h(360, 520))),
      chart_card(lang, t_("donors.chart_kind", lang), t_("donors.chart_kind_sub", lang),
                 loader_bar("kind", height = chart_h(240, 320),
                            horizontal = FALSE, legend = TRUE)),
      split = 7
    ),

    # Stacked, not side by side: the second card is hidden on a year with no
    # undated gifts, and a half-width sibling would leave the naming note -- the
    # one every reader needs -- sitting in half a row next to a gap. Same reason
    # the ballot page stacks its donor card.
    note_card(t_("donors.naming_title", lang), t_("donors.naming_text", lang)),
    loader_toggle(
      "imputedStyle",
      note_card(t_("cols.year", lang), t_("donors.imputed", lang))
    ),

    # ---- the full, filterable table --------------------------------------
    section(
      t_("donors.tbl_explore", lang),
      Typography(t_("donors.tbl_explore_sub", lang), variant = "body2",
                 color = "text.secondary", sx = list(maxWidth = LEAD_MEASURE)),
      control_panel(
        t_("donations.filters", lang),
        Box(
          sx = list(display = "flex", flexWrap = "wrap", gap = 1.5,
                    alignItems = "center"),
          filter_input("event",    t_("donations.f_event", lang),    "events",     "curEvent"),
          filter_input("party",    t_("donations.f_party", lang),    "parties",    "curParty"),
          filter_input("canton",   t_("donations.f_canton", lang),   "cantons",    "curCanton"),
          filter_input("category", t_("donations.f_category", lang), "categories", "curCat"),
          filter_input("position", t_("donations.f_position", lang), "positions",  "curPosition"),
          min_amount_input(t_("donations.f_min", lang), t_("donations.f_any", lang)),
          # Clearing drops the query string but keeps the chosen year, which is
          # part of the path -- the year picker is the page, not a filter on it.
          Button(
            t_("donations.clear", lang), size = "small", color = "inherit",
            sx = list(color = "text.secondary"),
            onClick = JS("() => { window.location.hash = window.location.hash.split('?')[0]; }")
          )
        )
      ),

      Stack(
        direction = "row", spacing = 1, alignItems = "baseline",
        useLoaderData(Typography(variant = "body1", color = "text.secondary"),
                      as = "children", selector = "count"),
        Typography(t_("donations.unit", lang), variant = "body1",
                   color = "text.secondary")
      ),

      click_hint(lang),

      loader_toggle(
        "emptyStyle",
        note_card(t_("donations.empty", lang), t_("donations.empty_body", lang))
      ),

      grid_card(loader_grid(lang, "politikfinanzierung-zuwendungen", height = 620))
    )
  )
}

# =============================================================================
# DRILL-DOWNS (donor / party)
# =============================================================================
#
# `back` / `label` for the same reason drill_error() takes them: one tree serves
# both the donor and the party route, and "← Alle Zuwendenden" is the wrong thing
# to say on /de/party/die-mitte. The destination is the donors page either way --
# it is the app's only index of donations, and it carries the party filter -- so
# what differs is the wording.
page_drill <- function(D, lang, back = "donors", label = "drill.back_donors") {
  page(
    NavLink(
      to = p_(lang, back),
      style = JS("() => ({ textDecoration: 'none' })"),
      Button(paste("←", t_(label, lang)), size = "small")
    ),
    useLoaderData(Typography(variant = "h4"), selector = "title"),
    kpi_row(
      loader_kpi(t_("drill.kpi_sum", lang), "sumFmt"),
      loader_kpi(t_("drill.kpi_count", lang), "count"),
      # A donor page counts recipients and a party page counts donors, so the
      # loader names this one as well as filling it in.
      loader_kpi(from_loader("extraLabel"), "extra")
    ),
    card_pair(
      chart_card(lang, t_("drill.chart_who", lang), t_("drill.chart_who_sub", lang),
                 loader_bar("who", height = chart_h(240, 340))),
      chart_card(lang, t_("drill.chart_what", lang), t_("drill.chart_what_sub", lang),
                 loader_bar("what", height = chart_h(240, 340)))
    ),
    grid_card(loader_grid(lang, "politikfinanzierung-auswahl", height = 520))
  )
}

# =============================================================================
# DATA & DOWNLOADS  (static per language)
# =============================================================================

# Five columns do not fit a 360px screen, and what a table does about that is
# scroll sideways -- with the bar at the foot of a fifteen-row table, so the
# download button in the last column was both off-screen and out of reach. On a
# phone each row becomes a block instead: name, size, what is in the table, and
# its button, in reading order and with no scrolling in either axis. Nothing is
# dropped; the two count columns fold into the caption under the name.
DATA_TABLE_SX <- list(
  thead = list(display = list(xs = "none", md = "table-header-group")),
  `tbody tr` = list(
    display = list(xs = "block", md = "table-row"),
    borderBottom = list(xs = paste0("1px solid ", INK$grid), md = "none"),
    `&:last-of-type` = list(borderBottom = list(xs = "none"))
  ),
  `tbody td` = list(
    display = list(xs = "block", md = "table-cell"),
    borderBottom = list(xs = "none"),
    px = list(xs = 0, md = 2),
    py = list(xs = 0.25, md = 1)
  ),
  # The counts, right-aligned and unlabelled once the header is gone.
  `tbody td:nth-of-type(3), tbody td:nth-of-type(4)` =
    list(display = list(xs = "none", md = "table-cell")),
  `tbody td:first-of-type` = list(pt = list(xs = 2)),
  `tbody td:last-of-type` = list(
    pt = list(xs = 1.25, md = 1), pb = list(xs = 2, md = 1),
    textAlign = list(xs = "left", md = "right")
  )
)

page_data <- function(D, lang, repo_url, data_published) {
  rows <- table_rows(D, lang)

  head_cell <- function(x, align = "left") {
    TableCell(sx = list(fontWeight = 600, color = "text.secondary",
                        borderColor = INK$grid), align = align, x)
  }

  # The link only resolves where data/ is served next to index.html. Where it is
  # not, the button says so instead of 404-ing: an explanation is more useful
  # than a dead link, and the row above it still tells the reader the table
  # exists and how big it is. See DATA_PUBLISHED in build_site.R.
  #
  # `download = ""` and not NA: NA reaches the browser as JSON null, and React
  # reads a null prop as "leave this attribute off", so the attribute would be
  # silently absent. The empty string is the attribute's own "save under the name
  # the server gives it" -- here, the CSV's own filename. Same-origin is the
  # other half of it: browsers ignore `download` on a cross-origin href and
  # navigate to the file instead, which is why data/ is copied to the site
  # rather than linked to GitHub.
  download_button <- function(href) {
    if (data_published) {
      Button(t_("data.download", lang), size = "small", variant = "outlined",
             component = "a", href = href, download = "")
    } else {
      Button(t_("data.download", lang), size = "small", variant = "outlined",
             onClick = JS("() => window.spf.soon()"))
    }
  }

  # The row and column counts, as one caption. On a phone the two numeric
  # columns are gone (see DATA_TABLE_SX) and their headers with them, so the
  # counts carry their own labels here. German capitalises its nouns and the
  # other two do not, which is the whole of the branch.
  size_caption <- function(n_rows, n_cols) {
    lab <- function(key) {
      x <- t_(key, lang)
      if (lang == "de") x else paste0(tolower(substr(x, 1, 1)), substr(x, 2, nchar(x)))
    }
    paste0(fmt_int_r(n_rows), " ", lab("data.col_rows"), " · ",
           n_cols, " ", lab("data.col_cols"))
  }

  div(
    page_head(t_("data.title", lang), t_("data.lead", lang)),

    Card(
      sx = CARD_SX,
      TableContainer(
        Table(
          size = "small",
          sx = DATA_TABLE_SX,
          TableHead(TableRow(
            head_cell(t_("data.col_table", lang)),
            head_cell(t_("data.col_desc", lang)),
            head_cell(t_("data.col_rows", lang), align = "right"),
            head_cell(t_("data.col_cols", lang), align = "right"),
            head_cell(t_("data.col_dl", lang), align = "right")
          )),
          TableBody(lapply(seq_len(nrow(rows)), function(i) {
            r <- rows[i, ]
            TableRow(
              key = r$path,
              TableCell(
                sx = list(borderColor = INK$grid),
                Typography(r$name, variant = "body2",
                           sx = list(fontWeight = 600, fontFamily = "ui-monospace, monospace")),
                Typography(dirname(r$path), variant = "caption", color = "text.secondary"),
                Typography(size_caption(r$rows, r$cols), variant = "caption",
                           color = "text.secondary",
                           sx = list(display = list(xs = "block", md = "none")))
              ),
              TableCell(sx = list(borderColor = INK$grid, color = "text.secondary"), r$desc),
              TableCell(sx = list(borderColor = INK$grid, fontVariantNumeric = "tabular-nums"),
                        align = "right", fmt_int_r(r$rows)),
              TableCell(sx = list(borderColor = INK$grid, fontVariantNumeric = "tabular-nums"),
                        align = "right", r$cols),
              TableCell(
                sx = list(borderColor = INK$grid), align = "right",
                download_button(r$href)
              )
            )
          }))
        )
      )
    ),

    Box(
      sx = list(mt = 3),
      truth_card(lang, repo_url)
    )
  )
}

# =============================================================================
# 404
# =============================================================================
page_missing <- function(lang) {
  Box(
    sx = list(py = 8, textAlign = "center"),
    Typography(t_("not_found", lang), variant = "h5", sx = list(mb = 2)),
    NavLink(
      to = p_(lang),
      style = JS("() => ({ textDecoration: 'none' })"),
      Button(t_("nav.home", lang), variant = "contained")
    )
  )
}

# Shared error element for every route that resolves a path parameter: an
# unknown ballot, year or donor renders this rather than a blank page.
drill_error <- function(lang, back = "donors", label = "drill.back_donors") {
  Box(
    sx = list(py = 6, textAlign = "center"),
    Typography(t_("drill.not_found", lang), variant = "h6", sx = list(mb = 2)),
    NavLink(
      to = p_(lang, back),
      style = JS("() => ({ textDecoration: 'none' })"),
      Button(paste("←", t_(label, lang)), variant = "contained")
    )
  )
}
