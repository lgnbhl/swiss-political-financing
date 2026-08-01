# =============================================================================
# Politikfinanzierung Schweiz — trilingual static exploration app
#
# Builds one fully static, server-less page (index.html) that serves German,
# French and Italian:
#
#   reactRouter  hash routing; language is the first route segment (#/de/…),
#                so every page in every language is a shareable URL, and JS
#                data loaders drive the filterable views
#   muiMaterial  layout and controls
#   muiDataGrid  sortable / filterable / CSV-exportable tables
#   muiCharts    bar charts
#
# There is no server and no build toolchain. The data is embedded once as
# window.SPF: language-free core tables plus one small dictionary per language
# (see prepare_data.R), so the francs are stored once rather than three times.
#
# Build:  Rscript app/build_site.R  ->  app/index.html (+ app/lib/)
# The result opens over file:// as well as over http.
# =============================================================================

library(reactRouter)
library(muiMaterial)
library(muiDataGrid)
library(muiCharts)
library(htmltools)
library(jsonlite)

setwd_here <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) setwd(dirname(normalizePath(f)))
}
setwd_here()

# The build has to be reproducible, because index.html is a committed artefact
# that an unattended weekly job rebuilds and pushes.
#
# htmltools and shiny.react draw random identifiers -- the container's
# data-react-id and 57 React `key` props in the element tree. Left to chance,
# every rebuild produced a different 2.4 MB file even when the EFK had published
# nothing, so the job's "commit only when data changed" test could never be
# true and the repository grew by 2.4 MB a week for no reason.
#
# Seeding makes those identifiers a function of the tree rather than of the
# clock. They still have to be unique within the document, and they are: the
# generator yields 58 distinct values, seeded or not.
set.seed(20240101)

# -----------------------------------------------------------------------------
# CONFIGURATION
#
# Both come from the environment so that publishing settings are a property of
# where the site is built, not an edit to this file. The defaults are what an
# unconfigured checkout gets, and are what the site ships with today.
#
#   SPF_REPO_URL        the GitHub repository this app is published from,
#                       e.g. https://github.com/lgnbhl/swiss-political-financing
#                       While it is empty the app still builds and works; the
#                       "report an error" and "browse the data on GitHub"
#                       buttons are left out, because a dead link is worse than
#                       no link.
#
#   SPF_DATA_PUBLISHED  "true" once data/ is served next to index.html. The
#                       download buttons on the data page link to
#                       data/<lang>/..., which only resolves then -- and a
#                       checkout is not that layout: data/ sits at the repository
#                       root, one level above app/. The workflow that copies both
#                       into place sets this (publish.yml, "Stage the site").
#                       While it is false the buttons open a "not published yet"
#                       note instead of a link that would 404, and the page still
#                       does its other job -- saying which tables exist and how
#                       big they are.
# -----------------------------------------------------------------------------
REPO_URL <- Sys.getenv("SPF_REPO_URL", "")
DATA_PUBLISHED <- isTRUE(as.logical(Sys.getenv("SPF_DATA_PUBLISHED", "FALSE")))

source("i18n.R")
source("prepare_data.R")
source("components.R")
source("aggregate.R")
source("pages.R")
source("build_checks.R")

# The hand-written browser JavaScript, in the order it is embedded.
#
# These are ordinary .js files, not strings built here: an editor, a linter and
# `node --check` can all read them, quotes do not have to be escaped, and each
# one is embedded once rather than once per language. Anything that needs a
# value from R belongs in the payload above, not spliced into the source.
#
# The order is the dependency order -- the runtime defines window.spf, the
# helpers use it, the loaders use both. build_checks.R refuses to continue when
# any of them does not parse.
SPF_JS <- c("js/spf-runtime.js", "js/spf-charts.js",
            "js/spf-tables.js",  "js/spf-loaders.js")

check_js(SPF_JS)
check_i18n()
D <- prepare_app_data()

# Which income components exist is read off the declarations table rather than
# declared (prepare_data.R::income_parts), so the loaders take it from the data.
INCOME_PARTS <- D$income_parts
# ...and the palette has to have a slot for each of them, which today it exactly
# does. See check_palette() for what happens when the EFK adds one.
check_palette(INCOME_PARTS, SERIES)

# =============================================================================
# EMBEDDED PAYLOAD
# =============================================================================
# Everything the loaders need, in one object. `dataframe = "rows"` matches what
# the DataGrid and the loaders expect; `na = "null"` keeps missing party/canton
# keys as null so the loaders can map them to "(no single party)".
json <- function(x) toJSON(x, dataframe = "rows", auto_unbox = TRUE, na = "null")

# Only the strings the loaders actually use are sent to the browser; the rest of
# I18N is already baked into the three static component trees.
i18n_for_js <- lapply(LANGS, function(l) list(
  cols      = tr_group("cols", l),
  cat       = tr_group("cat", l),
  drill     = tr_group("drill", l),
  votes     = tr_pick("votes", l, c("kpi_yes", "kpi_no", "other", "gap_even",
                                    "short_yes", "short_no", "short_budget", "short_final",
                                    "gap_more_yes", "gap_more_no", "gap_one_sided",
                                    "state_budget", "state_final", "state_both")),
  parties   = tr_pick("parties", l, "title"),
  donors    = tr_pick("donors", l, c("kind_org", "kind_person")),
  income    = c(tr_pick("income", l, c("budget", "final")),
                # Keyed by column name, not by position: the loaders read
                # T.income.parts[<column>], and which columns exist is decided
                # by the data (prepare_data.R::income_parts).
                list(parts = tr_group("income.parts", l))),
  events    = tr_group("events", l),
  no_party  = tr("no_party", l),
  no_canton = tr("no_canton", l),
  anonymous = tr("anonymous", l),
  unknown   = tr("unknown", l)
))
names(i18n_for_js) <- LANGS

# Runs here rather than next to check_i18n(): it needs both the data (for the
# per-table description keys) and the bundle above (for the keys the loaders
# read in the browser).
check_i18n_usage(D, i18n_for_js)

meta_for_js <- lapply(LANGS, function(l) donation_meta(D, l))
names(meta_for_js) <- LANGS

# The document's title and description per language. One document cannot carry
# three <title> elements, so the head gets the German pair at build time and
# `window.spf.setTitle()` rewrites both -- plus <html lang> -- from here on the
# language switch and at first paint.
meta_page <- lapply(LANGS, function(l) list(
  title       = tr("meta.title", l),
  description = tr("meta.description", l)
))
names(meta_page) <- LANGS

# `declarations` and `mandates` now travel to the browser as well: the votes,
# elections and party pages are all decided by the URL, and their figures come
# from declared income rather than from individual gifts. Together they add
# ~1'600 rows to the ~1'800 already embedded.
# Values the browser needs that are decided here: the languages this build
# speaks, and the palette and chart constants. They travel in the payload rather
# than being spliced into the JavaScript, which is what lets js/ be ordinary
# files that no build step rewrites -- and what stops the same seven hex codes
# being written into the page once per language.
consts <- list(
  SERIES     = SERIES,        # categorical slots, assigned in fixed order
  YES        = CAMP_YES,      # Yes-camp ordinal ramp, darkest step first
  NO         = CAMP_NO,       # No-camp ordinal ramp
  GREY       = BUDGET_RAMP,   # budgeted income, on every ballot
  POLE       = CAMP_POLE,     # the single step that stands for a whole camp
  PARTS      = INCOME_PARTS,  # income components, in presentation order
  LINK_COLOR = SERIES[1],
  # Franc tick labels are long; MUI's default tick count collides them.
  TICKS      = 6,
  # Bar thickness is a property of the *band axis* in this MUI X version -- set
  # on the chart it is silently ignored, which leaves every bar a slab.
  GAP        = list(categoryGapRatio = 0.55, barGapRatio = 0.15)
)

payload <- sprintf(
  "window.SPF = {
     langs: %s,
     consts: %s,
     donations: %s,
     declarations: %s,
     mandates: %s,
     events: %s,
     dict: %s,
     donors: %s,
     i18n: %s,
     meta: %s,
     meta_page: %s,
     chLocale: %s,
     asOf: %s
   };",
  toJSON(LANGS),
  toJSON(consts, auto_unbox = TRUE),
  json(D$donations),
  json(D$declarations),
  json(D$mandates),
  json(D$events),
  toJSON(D$dict, auto_unbox = TRUE, na = "null"),
  toJSON(D$donor_dict, auto_unbox = TRUE, na = "null"),
  toJSON(i18n_for_js, auto_unbox = TRUE, na = "null"),
  toJSON(meta_for_js, auto_unbox = TRUE, na = "null"),
  toJSON(meta_page, auto_unbox = TRUE, na = "null"),
  toJSON(CH_LOCALE, auto_unbox = TRUE),
  toJSON(D$as_of, auto_unbox = TRUE)
)

# The payload first, then the code, in one <script>. The files are wrapped in a
# single function scope so that only `window.spf` and `window.SPF` are global:
# helper names like `resolve`, `hide` and `band` are shared between the files
# without being exposed to the page, where they could collide with a library.
app_js <- function(paths = SPF_JS) {
  txt <- vapply(paths, function(p) {
    if (!file.exists(p)) stop("missing ", p, call. = FALSE)
    # Strip CR so the embedded text is LF whatever the working copy checked out as.
    paste(gsub("\r", "", readLines(p, warn = FALSE, encoding = "UTF-8"), fixed = TRUE),
          collapse = "\n")
  }, character(1))
  HTML(paste0("(function () {\n", paste(txt, collapse = "\n"), "\n})();"))
}

embed_script <- tags$script(HTML(paste0(payload, "\n", app_js())))

# =============================================================================
# SHELL
# =============================================================================
# One shell per language: a dark app bar with the nav and the language switch,
# the routed page, and a footer carrying the provenance note.
app_shell <- function(lang) {
  Box(
    # One document serves three languages, so the language is declared on the
    # shell rather than on <html> -- screen readers need it to choose the right
    # pronunciation for the subtree that is actually on screen.
    lang = t_("html_lang", lang),
    sx = list(minHeight = "100vh", bgcolor = "background.default",
              display = "flex", flexDirection = "column"),
    # First in the tree, so it is the first thing the keyboard reaches. Without
    # it every navigation costs nine tab stops through the bar before the page.
    skip_link(lang),
    AppBar(
      position = "sticky",
      elevation = 0,
      sx = list(bgcolor = INK$bar, borderBottom = "1px solid rgba(255,255,255,0.08)"),
      Container(
        maxWidth = SHELL_WIDTH,
        sx = list(px = list(xs = 2, sm = 3)),
        Toolbar(
          disableGutters = TRUE,
          sx = list(gap = 1, minHeight = list(xs = 56, md = 64)),
          menu_button(lang),
          NavLink(
            to = p_(lang),
            style = JS("() => ({ textDecoration: 'none', display: 'flex', alignItems: 'center', marginRight: '14px', minWidth: 0 })"),
            # The same mark as the favicon; see swiss_cross() in components.R.
            HTML(swiss_cross(26, "margin-right:10px;display:block;flex:none;")),
            Box(
              sx = list(minWidth = 0),
              # The three titles run to 34 characters and the phone bar has room
              # for about half that, so it wraps -- but to two lines at most,
              # then clips. Left free it made the bar four lines tall and pushed
              # the hamburger and the language switch on top of each other.
              Typography(t_("app_title", lang), variant = "subtitle1",
                         sx = list(fontWeight = 700, lineHeight = 1.15, color = "#fff",
                                   fontSize = list(xs = "0.82rem", sm = "1rem"),
                                   display = "-webkit-box", overflow = "hidden",
                                   WebkitLineClamp = 2, WebkitBoxOrient = "vertical")),
              Typography(t_("app_subtitle", lang), variant = "caption",
                         sx = list(color = INK$on_bar,
                                   display = list(xs = "none", md = "block")))
            )
          ),
          # Inline on a wide screen; on a phone the same links live in the drawer
          # the hamburger opens (nav_sheet, below, which binds to it by id).
          Box(className = "spf-nav", nav_links(lang)),
          Box(sx = list(flexGrow = 1, minWidth = 8)),
          lang_switch(lang)
        )
      )
    ),

    nav_sheet(lang),
    if (!DATA_PUBLISHED) soon_dialog(lang),

    # The routed page. A <main> landmark rather than a bare div, and focusable
    # (tabIndex -1) so the skip link has somewhere to land; #spf-main:focus
    # suppresses the ring that would otherwise be drawn around the whole page.
    Container(
      id = "spf-main",
      component = "main",
      tabIndex = -1L,
      maxWidth = SHELL_WIDTH,
      sx = list(py = list(xs = 2, md = 3), px = list(xs = 2, sm = 3), flexGrow = 1),
      Outlet()
    ),

    Box(
      component = "footer",
      sx = list(borderTop = "1px solid", borderColor = "divider", py = 2, mt = 2.5,
                bgcolor = INK$surface),
      Container(
        maxWidth = SHELL_WIDTH,
        sx = list(px = list(xs = 2, sm = 3)),
        Typography(variant = "body2", color = "text.secondary",
                   HTML(t_("footer.text", lang))),
        if (!is.na(D$as_of)) {
          Typography(paste(t_("footer.as_of", lang), D$as_of),
                     variant = "caption", color = "text.secondary",
                     sx = list(display = "block", mt = 0.75))
        }
      )
    )
  )
}

# =============================================================================
# ROUTES
# =============================================================================
# One subtree per language. Building three static trees rather than translating
# at runtime keeps every string an ordinary R value and makes the language
# switch a plain navigation.
#
# Each subject page is addressed by what it is showing -- /votes/28,
# /parties/2024, /donors/2025 -- so a view is a plain shareable URL, the back
# button steps through selections, and the language switch only has to rewrite
# the first segment. Landing on the bare page redirects to the newest thing there
# is, which is what a reader almost always wants.
DEFAULT_VOTE     <- event_ids_for(D, "votes")[1]
DEFAULT_ELECTION <- event_ids_for(D, "elections")[1]
DEFAULT_YEAR     <- party_year_options(D, "de")[[1]]$key

lang_routes <- function(lang) {
  to <- function(...) p_(lang, ...)

  # A route's loader is one line pointing at the shared implementation in
  # js/spf-loaders.js, with the language handed in. The route is the only thing
  # that knows the language for certain -- it is a literal path segment here,
  # not ":lang", so it never reaches `params` -- and passing it costs three
  # copies of a two-character string rather than three copies of the loader.
  spf_loader <- function(name) {
    JS(sprintf("(a) => window.spf.loaders.%s(a, '%s')", name, lang))
  }
  redirect <- function(path, target) {
    Route(path = path, element = Navigate(to = target, replace = TRUE))
  }

  Route(
    path = lang,
    element = app_shell(lang),
    Route(index = TRUE, element = page_home(D, lang, REPO_URL)),

    # ---- votes ----
    redirect("votes", to("votes", DEFAULT_VOTE)),
    Route(
      path = "votes/:eventId",
      loader = spf_loader("votes"),
      element = page_votes(D, lang),
      errorElement = drill_error(lang, "votes", "nav.votes")
    ),

    # ---- elections ----
    redirect("elections", to("elections", DEFAULT_ELECTION)),
    Route(
      path = "elections/:eventId",
      loader = spf_loader("elections"),
      element = page_elections(D, lang),
      errorElement = drill_error(lang, "elections", "nav.elections")
    ),

    # ---- party financing ----
    redirect("parties", to("parties", DEFAULT_YEAR)),
    Route(
      path = "parties/:year",
      loader = spf_loader("parties"),
      element = page_parties(D, lang),
      errorElement = drill_error(lang, "parties", "nav.parties")
    ),

    # ---- donors ----
    redirect("donors", to("donors", "all")),
    Route(
      path = "donors/:year",
      loader = spf_loader("donors"),
      element = page_donors(D, lang),
      errorElement = drill_error(lang)
    ),
    Route(
      path = "donor/:key",
      loader = spf_loader("donor"),
      element = page_drill(D, lang),
      errorElement = drill_error(lang)
    ),
    # The same tree as the donor page, and the same way back -- the donors page
    # is the app's only index of donations -- but worded for a party, which is
    # not one of the donors it lists.
    Route(
      path = "party/:key",
      loader = spf_loader("party"),
      element = page_drill(D, lang, "donors", "drill.back_all"),
      errorElement = drill_error(lang, "donors", "drill.back_all")
    ),

    Route(path = "data", element = page_data(D, lang, REPO_URL, DATA_PUBLISHED)),

    # The paths this app published before it was reorganised. Links to them are
    # already out there, so they land on the page that now answers the same
    # question rather than on the 404.
    # Only the exact old paths. A splat sibling ("campaigns/*") stops React
    # Router from matching the bare path next to it, so deep old links fall
    # through to the 404, which offers the way back.
    redirect("donations", to("donors", "all")),
    redirect("income",    to("parties", DEFAULT_YEAR)),
    redirect("campaigns", to("votes", DEFAULT_VOTE)),
    redirect("mandates",  to("parties", DEFAULT_YEAR)),

    Route(path = "*", element = page_missing(lang))
  )
}

# A bare "#/" is resolved before the router mounts: the bootstrap script in
# js/spf-runtime.js rewrites the hash to the language the reader last
# chose from the app bar, else the first of `navigator.languages` this app
# speaks, else German. A reader whose browser is French but who prefers the
# German financial vocabulary switches once and is remembered.
#
# The two routes below stay as the declarative fallback: they catch a first
# segment that is not de|fr|it, and the bare "#/" in the case where the script
# did not run. `replace = TRUE` keeps the redirect out of the history, so the
# back button leaves the app instead of bouncing off it.
router <- createHashRouter(
  Route(
    path = "/",
    element = Outlet(),
    Route(index = TRUE, element = Navigate(to = "/de", replace = TRUE)),
    lang_routes("de"),
    lang_routes("fr"),
    lang_routes("it"),
    Route(path = "*", element = Navigate(to = "/de", replace = TRUE))
  )
)

ui <- muiMaterialPage(
  useFontRoboto = FALSE,   # system sans only; no webfont request
  embed_script,
  app_css(),
  ThemeProvider(
    theme = spf_theme(),
    CssBaseline(),
    RouterProvider(router = router)
  )
)

save_html(ui, file = "index.html", libdir = "lib")

# =============================================================================
# DOCUMENT HEAD
# =============================================================================
# save_html() writes a minimal head of its own, so the document's identity is
# patched in afterwards rather than passed down: no title, no description, no
# icon and `lang="en"` on a site that is only ever German, French or Italian.
#
# The German pair is what ships; window.spf.setTitle() corrects both, and the
# lang attribute, as soon as the router resolves a language.
finish_head <- function(file) {
  html <- readLines(file, warn = FALSE, encoding = "UTF-8")

  html[html == "<html lang=\"en\">"] <- "<html lang=\"de\">"

  # muiMaterialPage emits its own <meta charset>, so save_html()'s is a
  # duplicate. Drop the first one and keep the one that travels with the page.
  first_charset <- which(html == "<meta charset=\"utf-8\"/>")[1]
  if (!is.na(first_charset)) html <- html[-first_charset]

  head_tags <- c(
    sprintf("<title>%s</title>", htmlEscape(tr("meta.title", "de"))),
    sprintf("<meta name=\"description\" content=\"%s\"/>",
            htmlEscape(tr("meta.description", "de"), attribute = TRUE)),
    # Continues the app bar into the browser's own chrome on a phone.
    sprintf("<meta name=\"theme-color\" content=\"%s\"/>", INK$bar),
    "<meta property=\"og:type\" content=\"website\"/>",
    sprintf("<meta property=\"og:title\" content=\"%s\"/>",
            htmlEscape(tr("meta.title", "de"), attribute = TRUE)),
    sprintf("<meta property=\"og:description\" content=\"%s\"/>",
            htmlEscape(tr("meta.description", "de"), attribute = TRUE)),
    "<meta name=\"twitter:card\" content=\"summary\"/>",
    # The same Swiss cross the app bar draws, inlined as a data URI so the built
    # page still requests nothing over the network.
    sprintf("<link rel=\"icon\" href=\"%s\"/>", favicon_uri())
  )

  at <- which(html == "<head>")[1]
  if (is.na(at)) stop("finish_head(): no <head> in ", file, call. = FALSE)
  html <- append(html, head_tags, after = at)

  writeLines(html, file, useBytes = TRUE)
}

finish_head("index.html")

# Runs here rather than at the end: everything below reads the document back,
# and a page with two <html> tags is worth stopping on before the lib/ prune
# starts deleting files on the strength of what it finds in it.
check_html_shell("index.html")

# =============================================================================
# LIBRARY DIRECTORY
# =============================================================================
# save_html() copies each package's whole `www` folder into lib/, which is more
# than the page loads: React ships a development build beside the production one
# (1.2 MB that nothing references) and shiny.react ships a 1.1 MB source map.
# Left alone that is a third of everything committed here and pushed to the
# website every week, for files no reader ever requests.
#
# What to keep is not a list maintained by hand -- it is read off the page that
# was just written, so a library added or upgraded needs no edit here. The
# licences are kept unconditionally: they are a condition of shipping the code,
# not an asset the page happens to load.
KEEP_ALWAYS <- "(LICEN[CS]E|AUTHORS|COPYING|NOTICE)"

prune_lib <- function(file = "index.html", libdir = "lib") {
  if (!dir.exists(libdir)) return(invisible(NULL))

  # Split on quotes rather than matching a pattern. A regex over this document
  # segfaults R: the payload is a single line of ~1.7 MB and PCRE overflows its
  # stack on it -- the same trap build_report() documents. Splitting is also
  # exactly right here, because save_html() writes these as whole attribute
  # values (src="lib/..."), so a token is a reference or it is not.
  lines <- readLines(file, warn = FALSE, encoding = "UTF-8")
  prefix <- paste0(libdir, "/")
  toks <- unlist(strsplit(lines[grepl(prefix, lines, fixed = TRUE)], '"', fixed = TRUE))
  refs <- unique(toks[startsWith(toks, prefix)])

  # A page that references nothing means the scan broke, not that the whole
  # directory is dead. Deleting on that reading would be unrecoverable, so stop.
  if (!length(refs)) {
    stop("prune_lib(): no ", libdir, "/ references found in ", file,
         " -- refusing to prune", call. = FALSE)
  }

  all <- list.files(libdir, recursive = TRUE, full.names = TRUE)
  keep <- all %in% refs | grepl(KEEP_ALWAYS, basename(all), ignore.case = TRUE)
  drop <- all[!keep]
  if (!length(drop)) return(invisible(character(0)))

  freed <- sum(file.size(drop))
  unlink(drop)
  cat(sprintf("Pruned %d unused file(s) from %s/ (%s KB)\n",
              length(drop), libdir, format(round(freed / 1024), big.mark = "'")))
  invisible(drop)
}

prune_lib()

cat("Built:", normalizePath("index.html"), "\n")

# Which page each route renders. The smoke test reads every `selector` out of
# these trees and requires the matching loader to return that field, so this
# list is the only thing that has to be kept in step with the routes above.
check_loaders(list(
  votes     = page_votes(D, "de"),
  elections = page_elections(D, "de"),
  parties   = page_parties(D, "de"),
  donors    = page_donors(D, "de"),
  donor     = page_drill(D, "de"),
  party     = page_drill(D, "de", "donors", "drill.back_all")
))

build_report("index.html")
cat(sprintf(
  "Languages: %s | donations %d | declarations %d | mandates %d | events %d\n",
  paste(LANGS, collapse = "/"), nrow(D$donations), nrow(D$declarations),
  nrow(D$mandates), nrow(D$events)
))
