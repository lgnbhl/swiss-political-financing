# write_out.R -- deterministic table writing and form-file archiving.

suppressMessages({
  library(readr)
  library(dplyr)
})

file_size_or0 <- function(path) if (file.exists(path)) as.integer(file.info(path)$size) else 0L

# Write a data frame as CSV with deterministic row ordering so that git diffs
# reflect real data changes only. Sorts by whichever of `sort_cols` exist.
#
# Format: semicolon-delimited, UTF-8 with a byte-order mark, `.` as the decimal
# mark. The files are meant to be opened in Excel by people who do not program,
# and Excel on a Swiss/European locale gets both halves of a plain UTF-8 comma
# CSV wrong: it splits on the locale list separator (`;` in de-CH, fr-CH and
# it-CH), so a comma file lands entirely in column A, and without a BOM it
# decodes the file as Windows-1252, so every accented name in the French and
# Italian datasets ("Élections", "Nicolò", "Zürich") arrives as mojibake. The
# BOM is what makes Excel commit to UTF-8; readr, pandas and R's utils all strip
# it on read. The decimal mark stays `.` -- that is the Swiss convention and it
# keeps the numbers parseable without a locale argument.
#
# This is the same format the app's own grid export already produced (see
# `csv_slot_props()` in app/components.R), so a table saved from the browser and
# the bulk file behind the download button now open the same way.
#
# Any reader of these files must therefore pass `delim = ";"` (see `read_tbl()`
# in R/checks.R and `read_lang()` in app/prepare_data.R).
write_table <- function(df, path, sort_cols = NULL) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (nrow(df) > 0 && !is.null(sort_cols)) {
    keys <- intersect(sort_cols, names(df))
    if (length(keys)) df <- arrange(df, across(all_of(keys)))
  }
  # quote = "needed" rather than write_excel_csv()'s "all": quoting every cell
  # inflates the files by a third and buys nothing in Excel.
  readr::write_excel_csv(df, path, delim = ";", na = "", quote = "needed")
  .log("wrote", path, sprintf("(%d rows, %d cols)", nrow(df), ncol(df)))
}

# Write one CSV per language under data/<lang>/<relpath>.
#
# Language is a property of the dataset, not of an observation: the portal
# publishes the same facts in de, fr and it, so a single consolidated file makes
# every total three times too large unless the reader remembers to filter. The
# language therefore lives in the path, and each folder is a complete, internally
# consistent dataset that can be summed as-is. The `language` column is kept so a
# file still identifies itself once copied out of its folder.
#
# Iterates CONFIG$languages rather than the values present in `df` so every
# language folder gets the full file set even when a table is empty for one.
write_by_language <- function(df, data_root, relpath, sort_cols = NULL,
                              languages = CONFIG$languages) {
  has_lang <- nrow(df) > 0 && "language" %in% names(df)
  for (lg in languages) {
    sub <- if (has_lang) filter(df, language == lg) else df[0, , drop = FALSE]
    write_table(sub, file.path(data_root, lg, relpath), sort_cols)
  }
}

# Download and archive every individual filed form (.xlsx). Form files are
# essentially immutable once filed, so we skip any already on disk (unless
# EFK_REFRESH_FORMS is set) to keep steady-state runs fast. Returns a manifest.
archive_forms <- function(forms, files_dir) {
  refresh <- env_flag("EFK_REFRESH_FORMS", FALSE)
  # unique (language, campaign_id, form_id) with a download path, only in the
  # configured archive languages.
  cand <- forms |>
    filter(language %in% CONFIG$archive_form_langs,
           !is.na(download_path), !is.na(form_id), !is.na(campaign_id)) |>
    distinct(language, campaign_id, form_id, download_path)
  manifest <- vector("list", nrow(cand))
  n_ok <- 0L; n_cached <- 0L
  for (i in seq_len(nrow(cand))) {
    row <- cand[i, ]
    dest <- file.path(files_dir, row$language,
                      sprintf("%s_%s.xlsx", row$campaign_id, row$form_id))
    cached <- !refresh && file.exists(dest) && file.info(dest)$size > 0
    if (cached) {
      n_cached <- n_cached + 1L
    } else {
      dl <- api_download(row$download_path, dest)
      if (dl$ok) n_ok <- n_ok + 1L
    }
    # stable content hash regardless of whether we just downloaded or reused it
    manifest[[i]] <- tibble(kind = "form", language = row$language,
      campaign_id = row$campaign_id, form_id = row$form_id,
      url = paste0(BASE_HOST, row$download_path),
      sha256 = sha256_file(dest), size = file_size_or0(dest))
  }
  .log("archive_forms:", nrow(cand), "candidates,", n_ok, "downloaded,", n_cached, "cached")
  if (length(manifest)) bind_rows(manifest) else tibble()
}
