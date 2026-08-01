# main.R -- orchestrates the full EFK political-financing scrape.
#
#   1. discover  : walk every theme tree (all languages) -> relationship tables
#   2. exports   : download the bulk .xlsx and parse -> financial tables
#   3. archive   : download every individual filed form (.xlsx)
#   4. write      : deterministic CSVs + manifest + run info
#
# Run:  Rscript R/main.R      (from the repository root)

t0 <- Sys.time()
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a
# Resolve repo root robustly whether run via Rscript or sourced.
args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grep("^--file=", args)])
script_dir <- if (length(file_arg)) dirname(normalizePath(file_arg)) else getwd()
root <- normalizePath(file.path(script_dir, ".."), mustWork = FALSE)

source(file.path(script_dir, "config.R"))
source(file.path(script_dir, "api.R"))
source(file.path(script_dir, "discover.R"))
source(file.path(script_dir, "exports.R"))
source(file.path(script_dir, "write_out.R"))

suppressMessages({ library(dplyr); library(jsonlite) })

DATA  <- file.path(root, "data")
RAW   <- file.path(root, "raw", "trees")
FILES <- file.path(root, "files")
STATE <- file.path(root, "state")

.log("EFK scrape start | languages:", paste(CONFIG$languages, collapse = ","),
     "| archive_forms:", CONFIG$archive_form_files)

first_non_na <- function(x) { x <- x[!is.na(x)]; if (length(x)) x[[1]] else NA }
# Zero-row frame with a usable header, so an unpopulated table still writes a
# readable CSV rather than an empty file.
empty_tbl <- function(...) {
  cols <- c(...)
  as_tibble(setNames(rep(list(character(0)), length(cols)), cols))
}

## 1. Discover theme trees ----------------------------------------------------
disc <- discover_all(CONFIG$languages, RAW)

## 2. Bulk exports -> financial tables ----------------------------------------
exp <- process_exports(CONFIG$languages, RAW, file.path(FILES, "exports"))

## 3. Derive relationship / inventory tables ----------------------------------
forms_app <- disc$forms
forms_inv <- if (nrow(forms_app)) {
  forms_app |>
    group_by(language, campaign_id, form_id) |>
    summarise(across(everything(), first_non_na), .groups = "drop")
} else forms_app

# One row per event. `year` is populated in some theme trees and blank in others,
# so it must be coalesced rather than included in the distinct key -- otherwise
# the same event is emitted twice.
events <- if (nrow(disc$events)) {
  disc$events |>
    group_by(language, financing_id, financing_type) |>
    summarise(label = first_non_na(label),
              year  = first_non_na(year),
              date  = first_non_na(date), .groups = "drop")
} else disc$events

actors <- if (nrow(forms_app) && "actor_id" %in% names(forms_app)) {
  forms_app |>
    filter(!is.na(actor_id)) |>
    group_by(language, actor_id) |>
    summarise(actor_label = first_non_na(actor_label),
              actor_category = first_non_na(actor_category),
              canton = if ("canton" %in% names(forms_app)) first_non_na(canton) else NA,
              party  = if ("party"  %in% names(forms_app)) first_non_na(party)  else NA,
              .groups = "drop")
} else empty_tbl("language", "actor_id", "actor_label", "actor_category", "canton", "party")

candidates <- if (nrow(forms_app) && any(forms_app$theme == "campaign_candidates")) {
  forms_app |>
    filter(theme == "campaign_candidates", !is.na(campaign_tree_id)) |>
    group_by(language, campaign_tree_id) |>
    summarise(candidate_label = first_non_na(campaign_label),
              party = if ("party" %in% names(forms_app)) first_non_na(party) else NA,
              canton = if ("canton" %in% names(forms_app)) first_non_na(canton) else NA,
              campaign_for = if ("campaign_for" %in% names(forms_app)) first_non_na(campaign_for) else NA,
              financing_id = first_non_na(financing_id),
              financing_label = first_non_na(financing_label),
              .groups = "drop")
} else empty_tbl("language", "campaign_tree_id", "candidate_label", "party", "canton",
                 "campaign_for", "financing_id", "financing_label")

allow_app <- disc$allowances
allow_inv <- if (nrow(allow_app)) {
  allow_app |> group_by(language, allowance_id) |>
    summarise(across(everything(), first_non_na), .groups = "drop")
} else allow_app

## 4. Archive individual form files -------------------------------------------
form_manifest <- tibble()
if (CONFIG$archive_form_files && nrow(forms_app)) {
  form_manifest <- archive_forms(forms_app, file.path(FILES, "forms"))
}

## 5. Write everything --------------------------------------------------------
# Everything is partitioned by language: data/<lang>/... . Sort keys no longer
# include `language`, which is now constant within each file.
write_by_language(exp$declarations, DATA, file.path("exports", "declarations.csv"),
                  c("category", "financing_id", "with_budget", "declaration_id"))
write_by_language(exp$declaration_candidates, DATA, file.path("exports", "declaration_candidates.csv"),
                  c("declaration_id", "candidate_seq"))
write_by_language(exp$contributions, DATA, file.path("exports", "contributions.csv"),
                  c("category", "financing_id", "with_budget", "contribution_id"))
write_by_language(exp$mandate_contributions, DATA, file.path("exports", "mandate_contributions.csv"),
                  c("category", "financing_id", "with_budget", "mandate_id"))

write_by_language(forms_inv, DATA, file.path("forms", "forms.csv"),
                  c("campaign_id", "form_id"))
write_by_language(forms_app, DATA, file.path("forms", "form_appearances.csv"),
                  c("theme", "group_by", "financing_id", "actor_id", "campaign_id", "form_id"))

write_by_language(allow_inv, DATA, file.path("allowances", "allowances.csv"),
                  c("allowance_id"))
write_by_language(allow_app, DATA, file.path("allowances", "allowance_appearances.csv"),
                  c("group_by", "financing_id", "allowance_id"))

write_by_language(disc$people, DATA, file.path("people", "people.csv"),
                  c("person_id"))

write_by_language(events, DATA, file.path("relationships", "financing_events.csv"),
                  c("financing_type", "financing_id"))
write_by_language(actors, DATA, file.path("relationships", "actors.csv"),
                  c("actor_id"))
write_by_language(candidates, DATA, file.path("relationships", "candidates.csv"),
                  c("financing_id", "campaign_tree_id"))

manifest <- bind_rows(exp$manifest, form_manifest)
write_by_language(manifest, DATA, "manifest.csv",
                  c("kind", "category", "financing_id", "campaign_id", "form_id"))

## 6. Run info ----------------------------------------------------------------
dir.create(STATE, recursive = TRUE, showWarnings = FALSE)
run_info <- list(
  finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  duration_sec = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1),
  languages = CONFIG$languages,
  # Counts are across all languages; divide by length(languages) for one dataset.
  counts = list(
    declarations = nrow(exp$declarations),
    declaration_candidates = nrow(exp$declaration_candidates),
    contributions = nrow(exp$contributions),
    mandate_contributions = nrow(exp$mandate_contributions),
    forms = nrow(forms_inv), form_appearances = nrow(forms_app),
    allowances = nrow(allow_inv), events = nrow(events),
    actors = nrow(actors), candidates = nrow(candidates),
    people = nrow(disc$people), manifest = nrow(manifest)
  )
)
writeLines(toJSON(run_info, auto_unbox = TRUE, pretty = TRUE),
           file.path(STATE, "run_info.json"))

.log("DONE in", run_info$duration_sec, "s |",
     "declarations", run_info$counts$declarations,
     "contrib", run_info$counts$contributions,
     "forms", run_info$counts$forms, "allowances", run_info$counts$allowances)
