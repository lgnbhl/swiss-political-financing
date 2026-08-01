# i18n.R
# ---------------------------------------------------------------------------
# Every string the app shows, in German, French and Italian.
#
# The strings themselves live in i18n.csv -- one row per key, one column per
# language -- and this file is only the way in. That is a deliberate split:
# adding a string is one row rather than three edits in three places 450 lines
# apart, a missing translation is a visibly empty cell, and the three languages
# cannot drift out of structure because they share a row.
#
# Keys are dotted paths naming the section they belong to ("votes.kpi_yes"). The
# nesting is a naming convention here, not a data structure; tr_group() and
# tr_pick() rebuild a list where a caller needs one.
#
# Translation is entirely a build-time concern: the component tree is built once
# per language, so every string is an ordinary R value by the time it reaches a
# page. Only the handful of strings the browser loaders need travel to the client
# (i18n_for_js in build_site.R).
# ---------------------------------------------------------------------------

I18N <- local({
  path <- "i18n.csv"
  if (!file.exists(path)) stop("missing ", path, call. = FALSE)
  t <- readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()),
                       progress = FALSE,
                       locale = readr::locale(encoding = "UTF-8"))

  langs <- setdiff(names(t), "key")
  out <- lapply(langs, function(l) stats::setNames(as.list(t[[l]]), t$key))
  names(out) <- langs
  out$keys <- t$key
  out
})

# The languages i18n.csv actually carries. prepare_data.R checks its own LANGS
# against this, so a column added here and nowhere else is caught.
I18N_LANGS <- setdiff(names(I18N), "keys")

# Every key, in file order. The order matters only for tr_group(), which uses it
# to keep a group's members in the order they were written.
i18n_keys <- function(lang = NULL) I18N$keys

# tr("donors.title", "fr") -> the French string, or the German one if the French
# cell is empty. Fails loudly if the key does not exist at all, so a typo
# surfaces at build time rather than rendering "NULL" in the browser.
tr <- function(path, lang) {
  v <- I18N[[lang]][[path]]
  if (is.null(v) || is.na(v) || !nzchar(v)) v <- I18N$de[[path]]
  if (is.null(v) || is.na(v)) stop("i18n: unknown key '", path, "'", call. = FALSE)
  v
}

# ---- rebuilding a group -----------------------------------------------------
# Two callers want a list rather than one string: the payload sent to the
# browser loaders, which read T.cols.date and the like, and anything indexing by
# a key it computes. Both go through these, so "the CSV is the source of truth"
# stays true and the shape is rebuilt only where it is needed.

# Direct children of a prefix: tr_group("cols", "fr") -> list(date = …, donor = …)
tr_group <- function(prefix, lang) {
  pat <- paste0("^", gsub(".", "\\.", prefix, fixed = TRUE), "\\.")
  k <- grep(pat, I18N$keys, value = TRUE)
  leaf <- sub(pat, "", k)
  k <- k[!grepl(".", leaf, fixed = TRUE)]   # direct children only
  stats::setNames(lapply(k, tr, lang = lang), sub(pat, "", k))
}

# A named subset, for the payload: what travels to the browser is chosen key by
# key on purpose, so it does not grow every time a string is added to a section.
tr_pick <- function(prefix, lang, names) {
  stats::setNames(lapply(paste0(prefix, ".", names), tr, lang = lang), names)
}

# ---- the check --------------------------------------------------------------
# Called by build_site.R, so any of these stops the build.
check_i18n <- function() {
  keys <- I18N$keys

  if (any(duplicated(keys))) {
    stop("i18n.csv: duplicate key(s): ",
         paste(unique(keys[duplicated(keys)]), collapse = ", "), call. = FALSE)
  }
  bad <- keys[!grepl("^[a-z0-9_]+(\\.[a-z0-9_]+)*$", keys)]
  if (length(bad)) {
    stop("i18n.csv: malformed key(s): ", paste(bad, collapse = ", "),
         ". Keys are dotted lowercase paths.", call. = FALSE)
  }

  # An empty cell in *any* language is a missing translation. The old nested
  # lists could only compare key structure, so an empty string passed; here it
  # does not, which is the point of the move.
  for (l in I18N_LANGS) {
    v <- unlist(I18N[[l]], use.names = FALSE)
    empty <- keys[is.na(v) | !nzchar(trimws(v))]
    if (length(empty)) {
      stop(sprintf("i18n.csv: %s is empty for: %s", l,
                   paste(empty, collapse = ", ")), call. = FALSE)
    }
  }

  # The file is read as UTF-8; if it were not, this is the first thing that
  # would break, and it would break as mojibake on the page rather than loudly.
  if (!identical(Encoding(tr("lang_name", "fr")), "UTF-8") &&
      !grepl("^Fran", tr("lang_name", "fr"))) {
    stop("i18n.csv: does not appear to have been read as UTF-8", call. = FALSE)
  }

  invisible(TRUE)
}
