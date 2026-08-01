# exports.R -- the "exports" theme provides authoritative BULK Excel files that
# contain every actor, campaign, form, donation and mandate contribution with
# full detail. These are the primary source for the consolidated financial
# tables. We discover the download nodes, fetch each .xlsx, and parse the sheets
# into income / contributions / mandate_contributions using positional schemas.

suppressMessages({
  library(readxl)
  library(dplyr)
  library(stringr)
})

# Discover every bulk export download node across languages.
# Returns a tibble: language, category, financing_id, event_label, event_year,
# event_date, with_budget, download_path, download_label.
discover_exports <- function(languages, raw_dir) {
  rows <- list()
  for (lang in languages) {
    for (gb in names(EXPORT_CATEGORIES)) {
      category <- EXPORT_CATEGORIES[[gb]]
      body <- api_get_json(lang, "exports", list(group_by = gb))
      .log("exports", lang, gb, if (is.null(body)) "-> (none)" else "ok")
      if (is.null(body)) next
      writeLines(jsonlite::toJSON(body, auto_unbox = TRUE, pretty = TRUE),
                 file.path(raw_dir, sprintf("%s__exports__%s.json", lang, gb)))
      roots <- body$data$tree_roots
      if (is.null(roots)) next
      for (ev in roots) {
        for (dl in (ev[["children"]] %||% list())) {
          if (!identical(dl[["type"]], "download")) next
          dp <- dl[["download_path"]]
          rows[[length(rows) + 1L]] <- tibble(
            language      = lang,
            category      = category,
            financing_id  = as.character(ev[["id"]]),
            event_label   = as.character(ev[["label"]]),
            event_year    = as.character(ev[["header_text"]] %||% NA),
            event_date    = .parse_date(as.character(ev[["label"]])),
            with_budget   = str_detect(dp %||% "", "with_budget=true"),
            download_path = dp,
            download_label = as.character(dl[["label"]])
          )
        }
      }
    }
  }
  if (length(rows)) bind_rows(rows) else tibble()
}

# Map localized headers to canonical names via the trilingual dictionary.
# Unknown headers are kept with a sanitized name so no column is ever dropped.
.name_sheet <- function(df) {
  orig <- names(df)
  canon <- unname(HEADER_MAP[norm_header(orig)])
  unknown <- is.na(canon)
  if (any(unknown)) {
    fallback <- gsub("[^a-z0-9]+", "_", norm_header(orig[unknown]))
    fallback <- gsub("^_|_$", "", fallback)
    canon[unknown] <- fallback
    .log("NOTE unmapped export headers:", paste(unique(orig[unknown]), collapse = " | "))
  }
  names(df) <- make.unique(canon, sep = "_")
  df
}

# --- date columns -------------------------------------------------------------
# Sheets are read with col_types = "text" so the three category schemas can be
# unioned without readxl guessing a type per file. That is deliberate, but it
# loses the one distinction that matters for dates: whether the EFK typed the
# cell as text or as a date.
#
# Both happen, in the same column. `Gewährungsdatum der Zuwendung` arrives as the
# string "18.07.2023" in 41 of the 47 archived export files and as a *date-typed*
# cell in the six most recent ones (financings 24-29), where col_types = "text"
# renders the underlying serial: "46002.0". Left alone those rows carry no usable
# date at all -- 136 gifts worth CHF 18.1M at the 2026-07-25 snapshot -- so any
# per-year view silently drops them.
#
# Excel serials are counted from 1899-12-30 (the 1900 system, including its
# phantom leap day). Only a bare number in a plausible range is converted; a
# value that already looks like a date is left exactly as filed.
DATE_COLS <- c("date", "event_date", "donation_date")

# Serials are accepted between 1990-01-01 and 2100-01-01. A franc amount that
# strayed into a date column would sit far outside that window rather than being
# silently reinterpreted as a date.
.SERIAL_MIN <- 32874   # 1990-01-01
.SERIAL_MAX <- 73051   # 2100-01-01

excel_serial_to_date <- function(x) {
  x <- as.character(x)
  serial <- grepl("^\\s*[0-9]+(\\.0+)?\\s*$", x)
  if (!any(serial, na.rm = TRUE)) return(x)
  n <- suppressWarnings(as.numeric(x[which(serial)]))
  ok <- !is.na(n) & n >= .SERIAL_MIN & n <= .SERIAL_MAX
  idx <- which(serial)[ok]
  if (!length(idx)) return(x)
  x[idx] <- format(as.Date(n[ok], origin = "1899-12-30"), "%d.%m.%Y")
  x
}

.fix_date_columns <- function(df, path) {
  for (cn in intersect(DATE_COLS, names(df))) {
    before <- df[[cn]]
    df[[cn]] <- excel_serial_to_date(before)
    n <- sum(before != df[[cn]], na.rm = TRUE)
    if (n) .log("NOTE", basename(path), cn, "--", n,
                "date-typed cells converted from Excel serials")
  }
  df
}

# --- de-fanning ---------------------------------------------------------------
# The EFK bulk export repeats every declaration once per supported candidate, so
# a raw row is a (declaration x candidate) pair, not a real-world event. Summing
# any amount column over the raw rows overstates it (measured: 4x for income,
# 2x for contributions). We therefore split the candidate axis out into its own
# link table and reduce the financial tables to their true grain.
#
# Within one export file the rows for a declaration are contiguous and the
# contributions sheet is donation-major: n_donations consecutive blocks of
# n_candidates rows, the candidate list repeating identically in each block
# (verified across de/fr/it on the full snapshot). De-fanning is therefore done
# positionally -- keeping every n_candidates-th row -- and NOT by de-duplicating
# rows, because a declaration may legitimately contain two identical donations
# (same donor, amount and date) that de-duplication would silently merge.

# Columns describing the supported candidate rather than the declaration.
.CANDIDATE_COLS <- c("last_name", "first_name", "canton",
                     "party_affiliation", "candidate_group")

# Columns identifying one filed declaration. Deliberately excludes
# `disclosure_report`, whose wording differs between the income and the
# contributions sheet of the same declaration.
.DECLARATION_KEY <- c("category", "financing_id", "with_budget",
                      "actor", "campaign", "disclosure_run")

# Paste columns into one comparable string; absent columns count as NA so keys
# stay aligned across sheets that carry different column sets.
.row_key <- function(df, cols) {
  parts <- lapply(cols, function(cn) {
    if (cn %in% names(df)) as.character(df[[cn]]) else rep(NA_character_, nrow(df))
  })
  do.call(paste, c(parts, list(sep = "\r")))
}

# 1..n within each run of consecutive identical values.
.seq_within_run <- function(x) sequence(rle(x)$lengths)

# Smallest p dividing length(x) such that x is x[1:p] repeated. Recovers the
# candidate-block size straight from the data when the income sheet cannot.
.block_period <- function(x) {
  n <- length(x)
  if (n <= 1) return(n)
  for (p in seq_len(n)) {
    if (n %% p != 0) next
    if (identical(x, rep(x[seq_len(p)], n / p))) return(p)
  }
  n
}

# Declaration ids are numbered in order of first appearance within an export
# file, income sheet first. Row order inside a file is identical across
# languages, so the same declaration gets the same id in de, fr and it.
.declaration_ids <- function(tabs, meta) {
  index <- unique(unlist(lapply(SHEET_TABLE, function(nm) {
    df <- tabs[[nm]]
    if (is.null(df) || !nrow(df)) NULL else .row_key(df, .DECLARATION_KEY)
  }), use.names = FALSE))
  prefix <- sprintf("%s-%s-%s", meta$category, meta$financing_id,
                    if (isTRUE(as.logical(meta$with_budget))) "B" else "F")
  function(df) sprintf("%s-%03d", prefix,
                       match(.row_key(df, .DECLARATION_KEY), index))
}

# Split one parsed export file into declarations / candidates / contributions /
# mandate_contributions. `tabs` is the output of .parse_export_file.
.defan_export_file <- function(tabs, meta) {
  decl_id <- .declaration_ids(tabs, meta)
  out <- list(declarations = NULL, declaration_candidates = NULL,
              contributions = NULL, mandate_contributions = NULL)
  cand_rows <- list()
  n_cand <- integer(0)  # declaration_id -> number of supported candidates

  # -- income sheet: one row per (declaration x candidate) -----------------
  inc <- tabs$income
  if (!is.null(inc) && nrow(inc)) {
    inc$declaration_id <- decl_id(inc)
    cand_rows[[length(cand_rows) + 1L]] <- bind_cols(
      inc[intersect(c("language", "declaration_id"), names(inc))],
      tibble(candidate_seq = .seq_within_run(inc$declaration_id)),
      inc[intersect(.CANDIDATE_COLS, names(inc))]
    )
    runs <- rle(inc$declaration_id)
    n_cand <- setNames(runs$lengths, runs$values)
    out$declarations <- inc[!duplicated(inc$declaration_id),
                            setdiff(names(inc), .CANDIDATE_COLS)]
  }

  # -- contributions sheet: donation-major blocks of n_cand rows -----------
  con <- tabs$contributions
  if (!is.null(con) && nrow(con)) {
    con$declaration_id <- decl_id(con)
    runs <- rle(con$declaration_id)
    keep <- logical(nrow(con))
    seq_no <- integer(nrow(con))
    at <- 1L
    for (b in seq_along(runs$lengths)) {
      n  <- runs$lengths[b]
      id <- runs$values[b]
      ix <- seq.int(at, length.out = n)
      period <- .block_period(.row_key(con[ix, , drop = FALSE], .CANDIDATE_COLS))
      expected <- if (id %in% names(n_cand)) n_cand[[id]] else NA_integer_
      if (!is.na(expected) && expected != period) {
        if (n %% expected == 0) {
          period <- expected
        } else {
          .log("WARN de-fan:", id, "has", n, "contribution rows for",
               expected, "candidates; falling back to observed period", period)
        }
      }
      picked <- ix[seq.int(1L, n, by = period)]
      keep[picked] <- TRUE
      seq_no[picked] <- seq_along(picked)
      # Declarations absent from the income sheet get their candidate list here.
      if (is.na(expected)) {
        blk <- con[ix[seq_len(period)], , drop = FALSE]
        cand_rows[[length(cand_rows) + 1L]] <- bind_cols(
          blk[intersect("language", names(blk))],
          tibble(declaration_id = id, candidate_seq = seq_len(period)),
          blk[intersect(.CANDIDATE_COLS, names(blk))]
        )
      }
      at <- at + n
    }
    kept <- con[keep, setdiff(names(con), .CANDIDATE_COLS)]
    kept$contribution_id <- sprintf("%s-d%03d", kept$declaration_id, seq_no[keep])
    out$contributions <- kept
  }

  # -- mandate contributions: already one row per mandate ------------------
  man <- tabs$mandate_contributions
  if (!is.null(man) && nrow(man)) {
    man$declaration_id <- decl_id(man)
    out$mandate_contributions <- man
  }

  # A declaration can report donations or mandate contributions without filing
  # an income statement (e.g. a final-accounts donation report with no matching
  # final income sheet). List it anyway, with the income columns empty, so
  # declarations.csv is the complete set every other table can be joined to.
  if (!is.null(out$declarations)) {
    for (extra in list(out$contributions, out$mandate_contributions)) {
      if (is.null(extra) || !nrow(extra)) next
      missing <- setdiff(extra$declaration_id, out$declarations$declaration_id)
      if (!length(missing)) next
      src <- extra[match(missing, extra$declaration_id), , drop = FALSE]
      out$declarations <- bind_rows(
        out$declarations,
        src[intersect(names(out$declarations), names(src))]
      )
    }
  }

  if (length(cand_rows)) {
    cd <- distinct(bind_rows(cand_rows))
    out$declaration_candidates <- cd
    # Party and canton belong to the candidate, not the declaration, and 5% of
    # declarations back candidates from several parties (one backs 11 across 23
    # cantons). Surface a value only when the candidate list agrees on one;
    # otherwise NA, with candidate_count telling the reader why. Splitting a
    # donation by candidate party instead would double count it.
    if (!is.null(out$declarations)) {
      only <- function(x) { u <- unique(x[!is.na(x)]); if (length(u) == 1L) u else NA_character_ }
      summ <- cd |>
        group_by(declaration_id) |>
        summarise(candidate_count  = n(),
                  candidate_party  = if ("party_affiliation" %in% names(cd)) only(party_affiliation) else NA_character_,
                  candidate_canton = if ("canton" %in% names(cd)) only(canton) else NA_character_,
                  .groups = "drop")
      out$declarations <- left_join(out$declarations, summ, by = "declaration_id")
    }
  }
  # keys first, so the grain of each table is obvious in the CSV header, and the
  # derived candidate summary next to the key rather than among the amounts
  if (!is.null(out$declarations))
    out$declarations <- relocate(out$declarations, declaration_id,
                                 any_of(c("candidate_count", "candidate_party",
                                          "candidate_canton")))
  if (!is.null(out$contributions))
    out$contributions <- relocate(out$contributions, contribution_id, declaration_id)
  if (!is.null(out$mandate_contributions))
    out$mandate_contributions <- relocate(out$mandate_contributions, declaration_id)
  out
}

# Parse one downloaded export file into a list of tables keyed by SHEET_TABLE.
.parse_export_file <- function(path, meta) {
  out <- list()
  sheets <- readxl::excel_sheets(path)
  for (i in seq_along(sheets)) {
    if (i > length(SHEET_TABLE)) break
    df <- suppressMessages(readxl::read_excel(path, sheet = i, col_names = TRUE,
                                              col_types = "text"))
    if (nrow(df) == 0) next
    df <- .name_sheet(df)
    df <- .fix_date_columns(df, path)
    # prepend metadata (identical for every row of this file)
    df <- bind_cols(
      tibble(
        language     = meta$language,
        category     = meta$category,
        financing_id = meta$financing_id,
        with_budget  = meta$with_budget,
        event_label  = meta$event_label,
        event_year   = meta$event_year,
        event_date   = meta$event_date,
        source_path  = meta$download_path,
        file_sha256  = meta$file_sha256
      )[rep(1, nrow(df)), ],
      df
    )
    out[[SHEET_TABLE[i]]] <- df
  }
  out
}

# Warn if a table's declaration ids are not identical across languages. They are
# derived from row order within an export file, which the portal keeps identical
# across de/fr/it -- if that ever stops being true the ids would silently stop
# lining up, so check rather than assume.
.check_language_alignment <- function(df, table_name, id_col) {
  if (!nrow(df) || !all(c("language", id_col) %in% names(df))) return(invisible(NULL))
  by_lang <- split(df[[id_col]], df$language)
  if (length(by_lang) < 2) return(invisible(NULL))
  ref <- sort(unique(by_lang[[1]]))
  for (lg in names(by_lang)[-1]) {
    if (!identical(sort(unique(by_lang[[lg]])), ref)) {
      .log("WARN", table_name, id_col, "differs between", names(by_lang)[1],
           "and", lg, "-- cross-language joins on this id are unreliable")
    }
  }
  invisible(NULL)
}

# Full export pipeline: discover -> download -> parse -> de-fan.
# files_dir: where to archive the bulk .xlsx. Returns list with the four
# consolidated tables plus a manifest tibble.
process_exports <- function(languages, raw_dir, files_dir) {
  catalog <- discover_exports(languages, raw_dir)
  income <- list(); contrib <- list(); mandate <- list()
  cands <- list(); manifest <- list()
  if (nrow(catalog) == 0) {
    return(list(declarations = tibble(), declaration_candidates = tibble(),
                contributions = tibble(), mandate_contributions = tibble(),
                manifest = tibble()))
  }
  for (r in seq_len(nrow(catalog))) {
    row <- catalog[r, ]
    dest <- file.path(files_dir, row$language,
                      sprintf("financings_%s_budget%s.xlsx",
                              row$financing_id, ifelse(row$with_budget, "T", "F")))
    dl <- api_download(row$download_path, dest)
    manifest[[length(manifest) + 1L]] <- tibble(
      kind = "export", language = row$language, category = row$category,
      financing_id = row$financing_id, with_budget = row$with_budget,
      url = paste0(BASE_HOST, row$download_path), sha256 = dl$sha256,
      size = dl$size)
    if (!dl$ok) next
    meta <- as.list(row)
    meta$file_sha256 <- dl$sha256
    tabs <- tryCatch(.parse_export_file(dest, meta),
                     error = function(e) { .log("WARN parse failed", dest, conditionMessage(e)); list() })
    split <- tryCatch(.defan_export_file(tabs, meta),
                      error = function(e) { .log("WARN de-fan failed", dest, conditionMessage(e)); list() })
    if (!is.null(split$declarations))           income[[length(income) + 1L]]   <- split$declarations
    if (!is.null(split$declaration_candidates)) cands[[length(cands) + 1L]]     <- split$declaration_candidates
    if (!is.null(split$contributions))          contrib[[length(contrib) + 1L]] <- split$contributions
    if (!is.null(split$mandate_contributions))  mandate[[length(mandate) + 1L]] <- split$mandate_contributions
  }
  bind <- function(x) if (length(x)) bind_rows(x) else tibble()
  out <- list(
    declarations = bind(income),
    declaration_candidates = bind(cands),
    contributions = bind(contrib),
    mandate_contributions = bind(mandate),
    manifest = bind(manifest)
  )
  .check_language_alignment(out$declarations, "declarations", "declaration_id")
  .check_language_alignment(out$contributions, "contributions", "contribution_id")
  out
}
