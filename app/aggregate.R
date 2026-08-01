# aggregate.R
# ---------------------------------------------------------------------------
# Turns the language-free core tables from prepare_data.R into the localised
# option lists and landing-page figures the static parts of the app need.
#
# The four subject pages -- votes, elections, party financing, donors -- are all
# URL-driven: what they show depends on which ballot, scrutiny, year or donor is
# selected, so their numbers are computed in the browser by the loaders in
# js/spf-loaders.js. This file supplies what the *shell* needs: the contents of each
# page's picker, the filter option lists, and the landing page.
#
# Every figure here is scoped to one event or one year. There is deliberately no
# grand total: the dataset spans elections, ballots and party years between 2023
# and 2026, and adding those together produces a number with no referent. Two
# further reasons the same franc can appear twice are handled by `is_latest`
# (budget filed before final accounts) and, for ballots carrying a joint
# disclosure, by a note on the page itself -- both in prepare_data.R.
# ---------------------------------------------------------------------------

# Resolve a key column against one of the per-language dictionaries. Unmatched
# and missing keys fall back to `missing`, which is how "(no single party)" and
# "(not stated)" reach the screen in the right language.
lookup <- function(keys, dict, missing = NA_character_) {
  # indexed one key at a time on purpose: `dict[keys]` would silently drop the
  # NULLs for absent keys and shift every later row's label by one
  vapply(as.character(keys), function(k) {
    if (is.na(k) || is.null(dict[[k]])) missing else dict[[k]]
  }, character(1), USE.NAMES = FALSE)
}

# The three categories the EFK publishes, and what each is called. A category
# outside this list keeps its raw key as its label: it is a real filter over
# real gifts from the day it appears, and the alternative -- leaving it out --
# hides money from the reader until someone notices.
cat_labels <- function(lang) {
  c(elections = tr("cat.elections", lang),
    votes     = tr("cat.votes", lang),
    party     = tr("cat.party", lang))
}

cat_label <- function(key, lang) {
  known <- cat_labels(lang)
  if (key %in% names(known)) unname(known[key]) else key
}

# Shorten a long label for use as a chart axis tick or a dropdown row. Event
# labels run past 200 characters ("08.03.2026 Bundesgesetz vom 20. Juni 2025
# über die ...").
ellipsis <- function(x, n = 58) {
  ifelse(is.na(x), NA_character_,
         ifelse(nchar(x) > n, paste0(substr(x, 1, n - 1), "…"), x))
}

# ---- event pickers ----------------------------------------------------------
# Which financing events belong to each subject page. An event's category comes
# from the declarations filed against it, not from `financing_type`, because
# `campaign_financing` covers both ballots and elections.
event_ids_for <- function(D, category) {
  ids <- unique(D$declarations$financing_id[D$declarations$category == category])
  ev <- D$events[D$events$financing_id %in% ids, ]
  # newest first: the ballot a reader is looking for is almost always the last one
  ev$sort_date <- as.Date(ev$date, format = "%d.%m.%Y")
  ev <- ev[order(ev$sort_date, decreasing = TRUE, na.last = TRUE), ]
  ev$financing_id
}

# {key, label} pairs for `single_select()`. The key is the financing id, which is
# language-neutral, so the choice survives a language switch.
event_options <- function(D, lang, category, n = 90) {
  ids <- event_ids_for(D, category)
  lapply(ids, function(id) {
    list(key = id, label = ellipsis(lookup(id, D$dict[[lang]]$event, tr("unknown", lang)), n))
  })
}

# Party financing is disclosed per calendar year, never per event, so its picker
# is a year. Two years cannot be added together, which is why this is
# single-select.
party_year_options <- function(D, lang) {
  ev <- D$events[D$events$type == "party_financing" & !is.na(D$events$year), ]
  years <- sort(unique(ev$year), decreasing = TRUE)
  lapply(as.character(years), function(y) list(key = y, label = y))
}

# The donors page can legitimately span all years -- a donor's total is a real
# quantity -- so "all" leads and the individual years follow.
donor_year_options <- function(D, lang) {
  don <- D$donations[D$donations$is_latest & !is.na(D$donations$year), ]
  years <- sort(unique(don$year), decreasing = TRUE)
  c(list(list(key = "all", label = tr("donors.all_years", lang))),
    lapply(as.character(years), function(y) list(key = y, label = y)))
}

# ---- landing ----------------------------------------------------------------
# The one figure the landing page states: the most recent ballot for which
# anything has been disclosed, and how the two camps compare on it. A concrete
# event with a date beats a headline total that spans four years and three kinds
# of financing.
home_latest <- function(D, lang) {
  ids <- event_ids_for(D, "votes")
  dec <- D$declarations[D$declarations$is_latest & D$declarations$category == "votes", ]

  for (id in ids) {
    rows <- dec[dec$financing_id == id, ]
    if (!nrow(rows)) next
    yes <- sum(rows$total[rows$position == "yes"], na.rm = TRUE)
    no  <- sum(rows$total[rows$position == "no"],  na.rm = TRUE)
    if (yes + no <= 0) next
    return(list(
      id    = id,
      label = lookup(id, D$dict[[lang]]$event, tr("unknown", lang)),
      date  = D$events$date[D$events$financing_id == id][1],
      yes   = yes,
      no    = no,
      yes_label = D$dict[[lang]]$position$yes,
      no_label  = D$dict[[lang]]$position$no
    ))
  }
  NULL
}

# ---- data page --------------------------------------------------------------
# A table the pipeline has started writing is listed as soon as it exists
# (catalogue_tables() scans the folder). Its description is written by hand, so
# a new table shows up undescribed rather than stopping the weekly build over a
# missing sentence -- the file is still downloadable, which is the point of the
# page.
table_desc <- function(key, lang) {
  path <- paste0("data.tables.", key)
  if (!path %in% i18n_keys("de")) {
    message("! no description for data table '", key, "' (add ", path, " to i18n)")
    return("")
  }
  tr(path, lang)
}

table_rows <- function(D, lang) {
  t <- D$tables
  data.frame(
    path = t$path,
    name = basename(t$path),
    desc = vapply(t$key, table_desc, character(1), lang = lang, USE.NAMES = FALSE),
    rows = t$rows,
    cols = t$cols,
    # Relative to the document, not to the route: the app is one page and the
    # language lives in a hash fragment, which takes no part in resolving a URL.
    # So this is read against the directory index.html sits in, and data/ is
    # copied there beside it (publish.yml, "Stage the site").
    href = file.path("data", lang, t$path),
    stringsAsFactors = FALSE
  )
}

# ---- filter option lists (the donations grid on the donors page) ------------
# Each option is {key, label}: the key travels in the URL and survives a
# language switch, the label is what the user sees.
#
# The labels are sorted on a folded key rather than on themselves. Sorting free
# text directly hands the order to the machine's collation -- "Zürich" lands
# before or after "Zug" depending on the locale -- and index.html is a committed
# artefact built both on a laptop and on a Linux runner, so a list that sorts
# differently on the two is a diff every week for no reason. donor_norm() already
# folds case and accents to ASCII for grouping; reusing it here gives one order
# everywhere, and it is the order a reader expects because that is what the fold
# was designed to produce. `method = "radix"` is what makes the last step
# byte-wise rather than locale-wise.
opts <- function(keys, dict, missing_label = NULL) {
  present <- unique(keys)
  has_na <- any(is.na(present))
  present <- sort(present[!is.na(present)], method = "radix")
  out <- lapply(present, function(k) {
    list(key = k, label = if (is.null(dict[[k]])) k else dict[[k]])
  })
  labels <- vapply(out, function(o) o$label, character(1))
  out <- out[order(donor_norm(labels), labels, method = "radix")]
  if (has_na && !is.null(missing_label)) {
    out <- c(out, list(list(key = "-", label = missing_label)))
  }
  out
}

# Known categories first, in the order the pages are laid out; anything new
# follows, and is announced once so it does not go unnoticed for a week.
donation_categories <- function(D) {
  found <- sort(unique(D$donations$category[!is.na(D$donations$category)]))
  known <- c("elections", "votes", "party")
  new   <- setdiff(found, known)
  if (length(new)) {
    message("! new donation category/ies: ", paste(new, collapse = ", "),
            " -- add cat.* to i18n and decide whether they need a page")
  }
  c(intersect(known, found), new)
}

donation_meta <- function(D, lang) {
  d <- D$dict[[lang]]
  don <- D$donations
  years <- sort(unique(don$year[!is.na(don$year)]), decreasing = TRUE)
  list(
    parties  = opts(don$party_key, d$party, tr("no_party", lang)),
    cantons  = opts(don$canton_key, d$canton, tr("no_canton", lang)),
    # Read off the data: a category the EFK adds becomes a working filter on
    # the next build, named by its raw key until it is translated.
    categories = lapply(donation_categories(D), function(c) {
      list(key = c, label = cat_label(c, lang))
    }),
    positions = lapply(c("yes", "no"), function(k) {
      list(key = k, label = if (is.null(d$position[[k]])) k else d$position[[k]])
    }),
    years = lapply(as.character(years), function(y) list(key = y, label = y)),
    # Ordered by date rather than alphabetically: the list is a timeline.
    events = lapply(unique(c(event_ids_for(D, "votes"), event_ids_for(D, "elections"),
                             D$events$financing_id)), function(id) {
      list(key = id, label = ellipsis(lookup(id, d$event, tr("unknown", lang)), 70))
    }),
    # The pickers the three subject pages open with.
    voteEvents     = event_options(D, lang, "votes"),
    electionEvents = event_options(D, lang, "elections"),
    partyYears     = party_year_options(D, lang),
    donorYears     = donor_year_options(D, lang)
  )
}
