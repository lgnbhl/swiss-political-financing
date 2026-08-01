# prepare_data.R
# ---------------------------------------------------------------------------
# Builds the trilingual payload embedded in the static app.
#
# The scraper publishes three complete, row-aligned datasets (data/de, data/fr,
# data/it) with identical IDs and identical CHF sums -- only label text differs.
# So instead of embedding the same francs three times, this file splits the data
# into:
#
#   * language-free CORE tables, keyed by the scraper's stable IDs
#     (contribution_id, declaration_id, actor_id, financing_id) and carrying
#     every number plus a *key* for each translatable label;
#   * one small DICTIONARY per language, mapping those keys to display labels.
#
# Keys are slugs of the German label ("die-mitte", "st-gallen"). They are what
# travels in the URL, which is why a language switch can keep a user's filters:
# `?party=die-mitte` means the same thing in all three languages.
#
# Donor names, donor locations and amounts are *not* translated by the EFK
# (verified: byte-identical across the three folders), so they stay inline in
# the core and donors are addressed in URLs by their name. `check_language_
# invariants()` asserts this rather than trusting it.
#
# The scraper already de-fans the bulk export's one-row-per-supported-candidate
# repetition, and each language folder holds a single language. One duplication
# is left, and it is the EFK's own data model rather than a scraping artefact:
# every actor discloses a campaign **twice** -- once as a budget
# (`with_budget = TRUE`, declaration ids like `votes-18-B-004`) and once as final
# accounts (`FALSE`, `votes-18-F-004`). 22 of the 31 events carry both. Summing
# all rows therefore counts the same francs twice: CHF 80.6M of final plus CHF
# 69.5M of budgeted donations reads as a CHF 150M total that does not exist.
#
# So every core table carries `is_latest`, from `latest_disclosure()` in
# R/disclosures.R -- shared with R/checks.R so the app's headline figures and the
# pipeline's reference totals cannot drift apart. Headline figures and all default
# views use `is_latest` only; the income page deliberately uses both flags side by
# side, which is the planned-vs-actual comparison.
#
# Party and canton come from declarations.csv, where they are populated only when
# every candidate on a declaration shares one. Actors are keyed by a slug of
# their German label, not by `actor_id`: the EFK leaves `actor_id` empty on
# 739 of 905 declarations and 1119 of 1810 contributions.
#
# Two further properties of the source shape what is built here:
#
#   * `campaign` on a *vote* row is the committee's position -- exactly two
#     values, "Annahme"/"Ablehnung der Abstimmungsvorlage". It is carried on both
#     contributions and declarations, because the Yes-camp / No-camp comparison
#     is a comparison of declared *income*, not only of individual gifts.
#   * donors are free text and the same body appears under several spellings.
#     See `build_donor_dict()`.
# ---------------------------------------------------------------------------

LANGS <- c("de", "fr", "it")

# The data folders and the string table have to speak the same languages. A
# fourth language is a folder under data/, a column in i18n.csv and an entry
# here; getting one of the three is a build failure rather than a page that is
# half translated.
if (exists("I18N_LANGS") && !setequal(LANGS, I18N_LANGS)) {
  stop("LANGS is ", paste(LANGS, collapse = "/"),
       " but i18n.csv has ", paste(I18N_LANGS, collapse = "/"), call. = FALSE)
}

# The income components EFK discloses. There is no expenditure counterpart: the
# disclosure obligation covers income only.
#
# The list below is the *presentation order*, not the definition: it fixes which
# colour slot each component takes so a chart does not recolour itself between
# builds. Which components actually exist is read off the declarations table by
# income_parts(), so a component the EFK adds or renames appears instead of
# being silently dropped -- it lands at the end.
#
# There is no free colour slot for it: SERIES has exactly as many as this list
# has entries. An eighth component therefore stops the build (check_palette() in
# build_checks.R) rather than quietly sharing a colour with the seventh.
INCOME_ORDER <- c(
  "monetary_donations_chf",
  "nonmonetary_donations_value_chf",
  "monetary_own_funds_chf",
  "membership_fees_chf",
  "mandate_contributions_income_chf",
  "goods_services_income_chf",
  "event_income_chf"
)

# `total_income_chf` is the sum of the parts, not a part; it is carried
# separately as `total`.
income_parts <- function(decl_de) {
  found <- setdiff(grep("_chf$", names(decl_de), value = TRUE), "total_income_chf")
  known <- intersect(INCOME_ORDER, found)
  new   <- setdiff(found, INCOME_ORDER)
  if (length(new)) {
    message("! new income component(s) in declarations.csv: ",
            paste(new, collapse = ", "),
            " -- add them to INCOME_ORDER and to income.parts.* in i18n")
  }
  gone <- setdiff(INCOME_ORDER, found)
  if (length(gone)) {
    message("! income component(s) no longer in declarations.csv: ",
            paste(gone, collapse = ", "))
  }
  c(known, new)
}

# ---- key helpers ------------------------------------------------------------
# Slugify a German label into a URL-safe key. Umlauts are expanded the German
# way (ü -> ue) rather than dropped, so "Grüne" and "Grune" cannot collide.
slugify <- function(x) {
  x <- as.character(x)
  x <- gsub("ä", "ae", x); x <- gsub("ö", "oe", x); x <- gsub("ü", "ue", x)
  x <- gsub("Ä", "Ae", x); x <- gsub("Ö", "Oe", x); x <- gsub("Ü", "Ue", x)
  x <- gsub("ß", "ss", x)
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT", sub = "")
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "-", x)
  x <- gsub("^-+|-+$", "", x)
  x[is.na(x) | x == ""] <- "unknown"
  x
}

# Build a key -> label lookup per language from a de/fr/it label triple that is
# already row-aligned. Returns list(keys = <key per row>, dict = list(de=, fr=, it=)).
# Keys are derived from the German label; a collision (two different German
# labels slugging to the same key) is resolved with a numeric suffix so the
# mapping stays injective.
build_dict <- function(labels, key_prefix = NULL) {
  stopifnot(all(LANGS %in% names(labels)))
  de <- labels$de
  uniq <- unique(de[!is.na(de)])
  if (is.null(key_prefix)) {
    key <- slugify(uniq)
    dup <- duplicated(key)
    if (any(dup)) key[dup] <- paste0(key[dup], "-", seq_len(sum(dup)) + 1L)
  } else {
    # Surrogate keys for labels that never appear in a URL and are too long to
    # slug (an election "campaign" is the full candidate list, up to 3040 chars).
    key <- paste0(key_prefix, seq_along(uniq))
  }
  names(key) <- uniq

  dict <- lapply(LANGS, function(l) {
    lab <- labels[[l]]
    # first occurrence of each German label decides that language's wording
    idx <- match(uniq, de)
    stats::setNames(as.list(lab[idx]), key)
  })
  names(dict) <- LANGS

  list(keys = unname(key[match(de, uniq)]), dict = dict)
}

# ---- donor identity ---------------------------------------------------------
# The EFK collects the donor as free text, so one body reaches the export under
# several spellings: "economiesuisse" / "Economiesuisse", "Nestlé S.A." /
# "Nestle SA", "Zürich Versicherungs-Gesellschaft AG (Unterstützungsbeitrag
# 2023)" / "Zürich Versicherungsgesellschaft AG". Ranking donors without
# grouping them splits one funder across several bars and understates it.
#
# The grouping key is deliberately mechanical -- case, accents, punctuation and a
# *trailing* parenthetical are the only things discarded -- so it can never merge
# two differently named bodies. A mid-string parenthetical is kept, which is what
# stops "Hauseigentümerverband (HEV) Schweiz" from losing its acronym.
donor_norm <- function(x) {
  x <- as.character(x)
  x <- sub("\\s*\\([^()]*\\)\\s*$", "", x)   # trailing "(Unterstützungsbeitrag 2024)"
  x <- gsub("ä", "ae", x); x <- gsub("ö", "oe", x); x <- gsub("ü", "ue", x)
  x <- gsub("Ä", "Ae", x); x <- gsub("Ö", "Oe", x); x <- gsub("Ü", "Ue", x)
  x <- gsub("ß", "ss", x)
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT", sub = "")
  tolower(gsub("[^A-Za-z0-9]+", "", x))
}

# Spellings the mechanical key cannot join because the words themselves differ.
# Kept short, exact-match only and listed here rather than inferred: a fuzzy rule
# would merge "Schweizerische Volkspartei" with "Schweizerische Volkspartei des
# Kantons Zürich", which are different bodies. Only cases that are unambiguous
# *and* material are listed; everything else stays split, which understates a
# donor rather than inventing a merger.
DONOR_ALIASES <- c(
  # Hauseigentümerverband: CHF 11.0M + 4.8M + 0.9M under three names
  "HEV Schweiz"                          = "Hauseigentümerverband (HEV) Schweiz",
  "Hauseigentümerverband Schweiz"        = "Hauseigentümerverband (HEV) Schweiz",
  # Gewerbeverband, including the source's own typo ("Scvhweizerischer")
  "Schweizerischer Gewerbeverband sgv"   = "Schweizerischer Gewerbeverband",
  "Scvhweizerischer Gewerbeverband sgv"  = "Schweizerischer Gewerbeverband",
  "Schweizerischer Gewerbeverband - SGV" = "Schweizerischer Gewerbeverband",
  "UNIA"                                 = "Gewerkschaft Unia"
)

# Group donor spellings and pick one label per group: the variant that appears on
# the most rows (the everyday spelling), longest string breaking a tie (the fuller
# official name). Returns a key per row plus a key -> label map. Donor names are
# not translated by the EFK -- `check_language_invariants()` asserts it -- so this
# dictionary is language-free, unlike the others.
#
# The third sort key is not decoration. Rows and characters both tie in real data:
# "auto-schweiz" and "auto schweiz" appear the same number of times and are the
# same length, and with two keys the winner was whatever the machine's collation
# happened to order first -- `table()` names its cells in the locale's order. The
# label then differed between a Windows checkout and the Linux runner, so the
# weekly job rewrote index.html on a machine difference. It survived only because
# slugify() maps both spellings to one key; a tie between spellings with
# different slugs would have moved every donor URL. `method = "radix"` sorts
# characters by byte in the C locale, which is the same everywhere.
build_donor_dict <- function(donor) {
  canon <- ifelse(donor %in% names(DONOR_ALIASES), DONOR_ALIASES[donor], donor)
  grp <- donor_norm(canon)
  grp[is.na(canon) | canon == ""] <- NA_character_

  present <- unique(grp[!is.na(grp)])
  label <- vapply(present, function(g) {
    spellings <- canon[!is.na(grp) & grp == g]
    v <- unique(spellings)
    rows <- tabulate(match(spellings, v), nbins = length(v))
    v[order(-rows, -nchar(v), v, method = "radix")][1]
  }, character(1), USE.NAMES = FALSE)

  key <- slugify(label)
  dup <- duplicated(key)
  if (any(dup)) key[dup] <- paste0(key[dup], "-", seq_len(sum(dup)) + 1L)
  names(key) <- present

  list(
    keys  = unname(key[grp]),
    dict  = stats::setNames(as.list(label), key)
  )
}

# ---- IO ---------------------------------------------------------------------
# `delim = ";"`: the published files are Excel-readable CSVs (see write_table()
# in R/write_out.R). readr strips the UTF-8 BOM itself, so column names here are
# the same as they were when the files were comma-delimited.
read_lang <- function(root, lang, ...) {
  readr::read_delim(
    file.path(root, "data", lang, ...),
    delim = ";", show_col_types = FALSE, progress = FALSE
  )
}

# Read one table in all three languages and confirm the row alignment the whole
# key scheme rests on (R/checks.R enforces this upstream; we refuse to build if
# it ever stops holding).
read_all_langs <- function(root, ..., id_col) {
  out <- lapply(LANGS, function(l) read_lang(root, l, ...))
  names(out) <- LANGS
  for (l in c("fr", "it")) {
    if (!identical(out$de[[id_col]], out[[l]][[id_col]])) {
      stop(sprintf(
        "data/de and data/%s are not row-aligned on %s (%s). Run `Rscript R/checks.R`.",
        l, id_col, paste(..., sep = "/")
      ), call. = FALSE)
    }
  }
  out
}

# ---- main -------------------------------------------------------------------
prepare_app_data <- function(root = NULL) {
  suppressMessages({
    library(readr)
    library(dplyr)
  })

  if (is.null(root)) {
    cand <- c("..", ".")
    root <- cand[dir.exists(file.path(cand, "data", "de"))][1]
    if (is.na(root)) {
      stop("Could not locate data/de/ -- run `Rscript R/main.R` first", call. = FALSE)
    }
  }

  # `latest_disclosure()` defines which rows count once. It is a property of the
  # dataset rather than of this app, so it lives in R/ and R/checks.R uses the
  # same definition -- the app's headline figures and the pipeline's reference
  # totals cannot drift apart.
  source(file.path(root, "R", "disclosures.R"), local = TRUE)

  contrib <- read_all_langs(root, "exports", "contributions.csv", id_col = "contribution_id")
  decl    <- read_all_langs(root, "exports", "declarations.csv",  id_col = "declaration_id")
  mand    <- read_all_langs(root, "exports", "mandate_contributions.csv", id_col = "declaration_id")
  events  <- read_all_langs(root, "relationships", "financing_events.csv", id_col = "financing_id")

  check_language_invariants(contrib)

  # ---- dictionaries --------------------------------------------------------
  # Party and canton live on declarations; everything else on its own table.
  party  <- build_dict(lapply(decl, function(d) blank_to_na(d$candidate_party)))
  canton <- build_dict(lapply(decl, function(d) blank_to_na(d$candidate_canton)))
  cfor   <- build_dict(lapply(decl, function(d) blank_to_na(d$campaign_for)), key_prefix = "cf")
  dtype  <- build_dict(lapply(contrib, function(d) blank_to_na(d$donation_type)))

  # `campaign` means two different things in the source. On a vote it is the
  # committee's position -- exactly two values, "Annahme"/"Ablehnung der
  # Abstimmungsvorlage" -- which is the Yes-camp / No-camp axis and worth
  # filtering on. On an election it is the full list of supported candidates (up
  # to 3040 characters, 146 variants), unreadable in a table and far too heavy to
  # embed; that list stays in exports/declaration_candidates.csv for download.
  # So only the vote position is carried, under stable yes/no keys.
  pos <- build_position_dict(contrib)
  inst   <- build_dict(lapply(mand,    function(d) blank_to_na(d$institution)))

  # Actors appear on all three tables and must share one key space, so the
  # dictionary is built from the union of the labels rather than per table.
  actor_labels <- lapply(LANGS, function(l) c(
    decl[[l]]$actor, contrib[[l]]$actor, mand[[l]]$actor
  ))
  names(actor_labels) <- LANGS
  actor <- build_dict(actor_labels)
  n_decl <- nrow(decl$de); n_contrib <- nrow(contrib$de)
  actor_key_decl    <- actor$keys[seq_len(n_decl)]
  actor_key_contrib <- actor$keys[n_decl + seq_len(n_contrib)]
  actor_key_mand    <- actor$keys[n_decl + n_contrib + seq_len(nrow(mand$de))]

  event_by_id <- lapply(LANGS, function(l) {
    d <- events[[l]]
    stats::setNames(as.list(d$label), as.character(d$financing_id))
  })
  names(event_by_id) <- LANGS

  # Every campaign event carries a polling date; `financing_events.year` is
  # populated on only 4 of 31 rows, so the year comes from the date.
  event_year_by_id <- stats::setNames(
    as.integer(format(as.Date(events$de$date, format = "%d.%m.%Y"), "%Y")),
    as.character(events$de$financing_id)
  )

  # ---- declarations core ---------------------------------------------------
  d0 <- decl$de
  declarations <- tibble(
    declaration_id = d0$declaration_id,
    category       = d0$category,          # raw key: elections | votes | party
    financing_id   = as.character(d0$financing_id),
    with_budget    = as.logical(d0$with_budget),
    year           = suppressWarnings(as.integer(d0$event_year)),
    actor_key      = actor_key_decl,
    position       = position_keys(d0, "declarations.csv"),
    party_key      = party$keys,
    canton_key     = canton$keys,
    cfor_key       = cfor$keys,
    n_candidates   = suppressWarnings(as.integer(d0$candidate_count)),
    total          = d0$total_income_chf
  )
  parts <- income_parts(d0)
  for (p in parts) declarations[[p]] <- d0[[p]]
  declarations$is_latest <- latest_disclosure(declarations)

  # ---- donations core -----------------------------------------------------
  c0 <- contrib$de
  dl <- declarations |> select(declaration_id, party_key, canton_key, is_latest)

  donations <- tibble(
    id            = c0$contribution_id,
    declaration_id = c0$declaration_id,
    category      = c0$category,
    financing_id  = as.character(c0$financing_id),
    actor_key     = actor_key_contrib,
    position      = pos$keys,
    dtype_key     = dtype$keys,
    with_budget   = as.logical(c0$with_budget),
    amount        = c0$value_chf,
    date_raw      = c0$donation_date,
    event_year    = suppressWarnings(as.integer(c0$event_year)),
    donor_last    = c0$donor_last_name,
    donor_first   = c0$donor_first_name,
    donor_company = c0$donor_company,
    donor_residence = c0$donor_residence,
    donor_domicile  = c0$donor_company_domicile,
    anonymous     = is_anonymous_flag(c0$anonymous_donation)
  ) |>
    left_join(dl, by = "declaration_id") |>
    mutate(
      donor_person = trimws(paste0(coalesce(donor_last, ""), " ", coalesce(donor_first, ""))),
      donor_raw = case_when(
        !is.na(donor_company) & donor_company != "" ~ donor_company,
        donor_person != ""                          ~ donor_person,
        TRUE                                        ~ NA_character_
      ),
      is_anonymous = anonymous | is.na(donor_raw),
      # The source splits the donor across a company field and a person's
      # first/last name; which one is filled is the only "who is this" signal it
      # carries, and `actor_type` on the declaration describes the *recipient*.
      donor_is_org = !is.na(donor_company) & donor_company != "",
      donor_place = coalesce(na_if(donor_domicile, ""), na_if(donor_residence, "")),
      date_parsed = as.Date(date_raw, format = "%d.%m.%Y"),
      date = if_else(is.na(date_parsed), NA_character_, format(date_parsed, "%Y-%m-%d")),
      # A safety net, not a routine path. The EFK types the donation date as
      # text in most export files and as a date-typed cell in others; when it
      # does the latter, the scraper used to publish the bare Excel serial and
      # 136 gifts worth CHF 18.1M lost their year entirely. That is fixed at the
      # source now (`excel_serial_to_date()` in R/exports.R), so on the current
      # snapshot every donation resolves from its own date and nothing below
      # fires. It stays because the next file the EFK types differently should
      # degrade to the event's year rather than vanish from the per-year views,
      # and `year_source` says so on the page instead of hiding it.
      year_source = case_when(
        !is.na(date_parsed) ~ "donation",
        !is.na(event_year)  ~ "declaration",
        TRUE                ~ "event"
      ),
      year = coalesce(as.integer(format(date_parsed, "%Y")), event_year,
                      unname(event_year_by_id[financing_id]))
    ) |>
    filter(!is.na(amount), amount > 0)

  # Donor grouping runs on the filtered rows so the label a group takes is the
  # commonest spelling among gifts that actually count.
  dk <- build_donor_dict(donations$donor_raw)
  donor_label <- unlist(dk$dict, use.names = TRUE)
  donations <- donations |>
    mutate(
      donor_key = if_else(is_anonymous, NA_character_, dk$keys),
      donor     = unname(donor_label[donor_key])
    ) |>
    transmute(
      id, date, year, year_source, amount,
      donor, donor_key, donor_raw, donor_place, is_anonymous, donor_is_org,
      actor_key, position, dtype_key,
      party_key, canton_key, category, financing_id, with_budget, is_latest
    ) |>
    arrange(desc(amount))

  # ---- mandate contributions core -----------------------------------------
  m0 <- mand$de
  mandates <- tibble(
    id             = paste0(m0$declaration_id, "-m", m0$mandate_id),
    declaration_id = m0$declaration_id,
    person         = trimws(paste0(coalesce(m0$last_name, ""), " ", coalesce(m0$first_name, ""))),
    inst_key       = inst$keys,
    amount         = m0$amount_chf,
    actor_key      = actor_key_mand,
    financing_id   = as.character(m0$financing_id),
    year           = suppressWarnings(as.integer(m0$event_year)),
    category       = m0$category,
    with_budget    = as.logical(m0$with_budget)
  ) |>
    left_join(declarations |> select(declaration_id, is_latest), by = "declaration_id") |>
    mutate(is_latest = coalesce(is_latest, TRUE)) |>
    filter(!is.na(amount), amount > 0) |>
    arrange(desc(amount))

  # ---- events core --------------------------------------------------------
  # Per-event totals count each actor's latest disclosure once (see `is_latest`).
  e0 <- events$de
  decl_agg <- declarations |>
    filter(is_latest) |>
    group_by(financing_id) |>
    summarise(
      n_decl   = n(),
      n_actors = n_distinct(actor_key),
      income   = sum(total, na.rm = TRUE),
      .groups  = "drop"
    )
  don_agg <- donations |>
    filter(is_latest) |>
    group_by(financing_id) |>
    summarise(donations_chf = sum(amount), n_donations = n(), .groups = "drop")

  # `financing_events.year` is filled on only 4 of 31 rows, so it is derived from
  # the polling date; the two party-financing rows have no date and fall back to
  # their own label, which *is* the year ("2023", "2024").
  events_core <- tibble(
    financing_id = as.character(e0$financing_id),
    type         = e0$financing_type,       # campaign_financing | party_financing
    year         = coalesce(
      unname(event_year_by_id[as.character(e0$financing_id)]),
      suppressWarnings(as.integer(e0$year)),
      suppressWarnings(as.integer(e0$label))
    ),
    date         = e0$date,
    joint        = as.character(e0$financing_id) %in%
      joint_event_ids(declarations, e0)
  ) |>
    left_join(decl_agg, by = "financing_id") |>
    left_join(don_agg, by = "financing_id") |>
    mutate(across(c(n_decl, n_actors, income, donations_chf, n_donations),
                  ~ coalesce(., 0))) |>
    arrange(desc(income))

  # ---- download catalogue -------------------------------------------------
  tables <- catalogue_tables(root)

  dict <- lapply(LANGS, function(l) list(
    party    = party$dict[[l]],
    canton   = canton$dict[[l]],
    cfor     = cfor$dict[[l]],
    position = pos$dict[[l]],
    dtype    = dtype$dict[[l]],
    inst     = inst$dict[[l]],
    actor    = actor$dict[[l]],
    event    = event_by_id[[l]]
  ))
  names(dict) <- LANGS

  list(
    donations    = donations,
    declarations = declarations,
    mandates     = mandates,
    events       = events_core,
    dict         = dict,
    # Donor labels are not translated by the EFK, so this map is language-free
    # and sits beside `dict` rather than inside it.
    donor_dict   = dk$dict,
    tables       = tables,
    # Read off the data rather than declared, so build_site.R and the loaders
    # chart whatever the EFK is publishing this week.
    income_parts = parts,
    as_of        = data_as_of(root)
  )
}

# Which ballots carry a joint disclosure.
#
# Several objects go to the same ballot, and a committee campaigning on two of
# them may file one disclosure for both. The EFK then lists that one filing
# under each object, so the same francs appear on two pages and a reader adding
# the objects together counts the money twice. The votes page says so, above the
# figures -- but only where it is true, which is what this works out.
#
# The signature is an actor filing the identical figure against more than one
# ballot of the same polling day. Same actor and same amount: two committees
# happening to raise the same sum are not affected, and neither is one committee
# active on ballots months apart.
#
# This used to be the literal date 24.11.2024 in the loader. Deriving it also
# fixed a gap -- the joint filing of 09.06.2024 got no note at all.
joint_event_ids <- function(declarations, events_de) {
  date_of <- stats::setNames(events_de$date, as.character(events_de$financing_id))

  v <- declarations[declarations$category == "votes" &
                      !is.na(declarations$total) & declarations$total > 0, ]
  if (!nrow(v)) return(character(0))
  v$date <- unname(date_of[v$financing_id])
  v <- v[!is.na(v$date), ]

  # One row per (polling day, actor, disclosure kind, amount); a group spanning
  # more than one ballot is the same filing counted twice.
  key <- paste(v$date, v$actor_key, v$with_budget, v$total, sep = " | ")
  n_events <- tapply(v$financing_id, key, function(x) length(unique(x)))
  unique(v$financing_id[key %in% names(n_events)[n_events > 1]])
}

# Extract the Yes/No camp from the `campaign` column of a table's vote rows.
#
# Keys are the stable strings "yes"/"no" so a `?position=yes` filter survives a
# language switch; labels come from the source wording in each language. Rows
# that are not vote rows get NA. The German wording is matched on
# "Annahme"/"Ablehnung" rather than assuming a row order.
#
# Both contributions and declarations carry this column, and the camp comparison
# the votations page draws is a comparison of declared *income*, so both tables
# are keyed. `what` only ever reaches the reader in an error message.
position_keys <- function(tab_de, what) {
  de <- blank_to_na(tab_de$campaign)
  is_vote <- tab_de$category == "votes"
  key <- rep(NA_character_, length(de))
  key[is_vote & grepl("^Annahme",   de)] <- "yes"
  key[is_vote & grepl("^Ablehnung", de)] <- "no"

  unmatched <- is_vote & !is.na(de) & is.na(key)
  if (any(unmatched)) {
    stop(sprintf(
      "Unrecognised vote position wording in %s: %s. Update position_keys().",
      what, paste(unique(de[unmatched]), collapse = " / ")
    ), call. = FALSE)
  }
  key
}

build_position_dict <- function(contrib) {
  key <- position_keys(contrib$de, "contributions.csv")

  dict <- lapply(LANGS, function(l) {
    lab <- blank_to_na(contrib[[l]]$campaign)
    stats::setNames(
      lapply(c("yes", "no"), function(k) {
        hit <- which(key == k)
        if (!length(hit)) NULL else lab[hit[1]]
      }),
      c("yes", "no")
    )
  })
  names(dict) <- LANGS

  list(keys = key, dict = dict)
}

# `anonymous_donation` is a yes/no the EFK writes out in words. Reading it
# wrongly is the worst mistake this app can make in either direction: a named
# donor hidden, or an anonymous one given a name and a page. So an unrecognised
# word stops the build instead of quietly counting as "not anonymous" -- which
# is what a bare `%in% c("ja", ...)` did.
#
# All three language folders are read, but only the German column reaches here;
# the others are listed because the EFK has changed which folder it fills.
ANON_YES <- c("ja", "oui", "si", "sì", "yes")
ANON_NO  <- c("nein", "non", "no")

is_anonymous_flag <- function(x) {
  v <- tolower(trimws(as.character(x)))
  v[is.na(v)] <- ""
  unknown <- setdiff(unique(v), c("", ANON_YES, ANON_NO))
  if (length(unknown)) {
    stop("contributions.csv: unrecognised anonymous_donation value(s): ",
         paste(sprintf("'%s'", unknown), collapse = ", "),
         ". Add them to ANON_YES or ANON_NO in prepare_data.R -- guessing here ",
         "either hides a named donor or names an anonymous one.", call. = FALSE)
  }
  v %in% ANON_YES
}

blank_to_na <- function(x) {
  x <- as.character(x)
  x[!is.na(x) & trimws(x) == ""] <- NA_character_
  x
}

# The values the URL keys and the app's arithmetic depend on must be identical
# in all three language folders. Stop the build rather than silently pick German.
check_language_invariants <- function(contrib) {
  shared <- c(
    "contribution_id", "declaration_id", "actor_id", "financing_id", "category",
    "value_chf", "donation_date",
    "donor_last_name", "donor_first_name", "donor_company",
    "donor_residence", "donor_company_domicile"
  )
  # Presence first. Without this a column the EFK renames is NULL in every
  # language, `identical(NULL, NULL)` is TRUE, and the check passes on a column
  # that no longer exists.
  for (l in LANGS) {
    absent <- setdiff(shared, names(contrib[[l]]))
    if (length(absent)) {
      stop(sprintf(
        paste0("contributions.csv (%s) has no column(s) `%s`. They were renamed ",
               "or dropped upstream; update the `shared` list in ",
               "check_language_invariants() and whatever reads them."),
        l, paste(absent, collapse = "`, `")
      ), call. = FALSE)
    }
  }
  for (l in c("fr", "it")) {
    for (col in shared) {
      if (!identical(contrib$de[[col]], contrib[[l]][[col]])) {
        stop(sprintf(
          paste0("contributions.csv column `%s` differs between de and %s. It is ",
                 "assumed language-independent (used as a key or an amount). ",
                 "Move it into a per-language dictionary in prepare_data.R."),
          col, l
        ), call. = FALSE)
      }
    }
  }
  invisible(TRUE)
}

# Catalogue every consolidated CSV so the download page can list them with row
# and column counts. Paths are relative to the repo root and identical in the
# three language folders, so we read the German folder and template the language.
#
# The folder is scanned rather than listed: a table the pipeline starts writing
# should appear here on the next build. TABLE_ORDER puts the tables a reader
# actually wants first; anything not named there follows, alphabetically, and
# falls back to its file name on the page until someone writes a description
# (aggregate.R::table_rows). Missing from the list is a missing sentence, not a
# missing download.
TABLE_ORDER <- c(
  "exports/declarations.csv",
  "exports/contributions.csv",
  "exports/declaration_candidates.csv",
  "exports/mandate_contributions.csv",
  "forms/forms.csv",
  "forms/form_appearances.csv",
  "allowances/allowances.csv",
  "allowances/allowance_appearances.csv",
  "relationships/financing_events.csv",
  "relationships/actors.csv",
  "relationships/candidates.csv",
  "people/people.csv",
  "manifest.csv"
)

catalogue_tables <- function(root) {
  dir <- file.path(root, "data", "de")
  found <- sort(list.files(dir, pattern = "\\.csv$", recursive = TRUE))
  rel <- c(intersect(TABLE_ORDER, found), setdiff(found, TABLE_ORDER))
  if (!length(rel)) stop("no CSVs under ", dir, call. = FALSE)

  rows <- lapply(rel, function(r) {
    p <- file.path(dir, r)
    # count rows without materialising the frame
    n_lines <- length(readr::read_lines(p, progress = FALSE))
    # sub() drops the UTF-8 BOM the files are written with, which would
    # otherwise ride along on the first column name
    hdr <- sub("^\ufeff", "", readr::read_lines(p, n_max = 1, progress = FALSE))
    tibble::tibble(
      path = r,
      key  = gsub("[/.]", "_", sub("\\.csv$", "", r)),
      rows = max(0L, n_lines - 1L),
      cols = length(strsplit(hdr, ";")[[1]]),
      size_kb = round(file.size(p) / 1024)
    )
  })
  dplyr::bind_rows(rows)
}

data_as_of <- function(root) {
  p <- file.path(root, "state", "run_info.json")
  if (!file.exists(p)) return(NA_character_)
  substr(jsonlite::fromJSON(p)$finished_at, 1, 10) # ISO date, locale-independent
}
