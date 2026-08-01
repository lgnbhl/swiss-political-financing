# checks.R -- structural invariants of the published data/<lang>/ datasets.
#
# These are the guarantees the layout is meant to provide, and the reason the
# data is split by language and de-fanned in the first place:
#
#   * each data/<lang>/ folder is one complete dataset, so summing an amount
#     column needs no filtering and no de-duplication;
#   * declaration_id / contribution_id identify one real-world event and are
#     unique within a language;
#   * the same ids and the same amounts appear in every language, so figures
#     are comparable across de / fr / it.
#
# Deliberately asserts no absolute row counts or totals -- those change with
# every weekly refresh. Run: Rscript R/checks.R   (exits 1 on failure)

suppressMessages({ library(readr); library(dplyr) })

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grep("^--file=", args)])
script_dir <- if (length(file_arg)) dirname(normalizePath(file_arg)) else getwd()
root <- normalizePath(file.path(script_dir, ".."), mustWork = FALSE)
source(file.path(script_dir, "config.R"))
source(file.path(script_dir, "disclosures.R"))

failures <- 0L
check <- function(label, ok, detail = "") {
  if (!isTRUE(ok)) failures <<- failures + 1L
  cat(sprintf("%-62s %s%s\n", label, if (isTRUE(ok)) "OK" else "FAIL",
              if (nzchar(detail)) paste0("  ", detail) else ""))
}

# `delim = ";"`: the published files are Excel-readable CSVs (see write_table()
# in R/write_out.R). readr strips the UTF-8 BOM itself.
read_tbl <- function(lang, ...) {
  p <- file.path(root, "data", lang, ...)
  if (!file.exists(p)) return(NULL)
  suppressWarnings(read_delim(p, delim = ";", col_types = cols(.default = col_character()),
                              progress = FALSE))
}
total <- function(x) if (is.null(x)) NA_real_ else sum(as.numeric(x), na.rm = TRUE)

langs <- CONFIG$languages
snap <- list()

for (lg in langs) {
  cat("\n== ", lg, " ==\n", sep = "")
  decl <- read_tbl(lg, "exports", "declarations.csv")
  cont <- read_tbl(lg, "exports", "contributions.csv")
  mand <- read_tbl(lg, "exports", "mandate_contributions.csv")
  cand <- read_tbl(lg, "exports", "declaration_candidates.csv")

  check("declarations.csv present", !is.null(decl))
  check("contributions.csv present", !is.null(cont))
  if (is.null(decl) || is.null(cont)) next

  check("declaration_id is unique",
        n_distinct(decl$declaration_id) == nrow(decl),
        sprintf("%d ids / %d rows", n_distinct(decl$declaration_id), nrow(decl)))
  check("contribution_id is unique",
        n_distinct(cont$contribution_id) == nrow(cont),
        sprintf("%d ids / %d rows", n_distinct(cont$contribution_id), nrow(cont)))
  check("single language per folder",
        all(decl$language == lg) && all(cont$language == lg))

  orphan <- setdiff(cont$declaration_id, decl$declaration_id)
  check("every contribution resolves to a declaration", length(orphan) == 0,
        if (length(orphan)) sprintf("%d orphans, e.g. %s", length(orphan), orphan[1]) else "")
  if (!is.null(mand)) {
    o2 <- setdiff(mand$declaration_id, decl$declaration_id)
    check("every mandate contribution resolves to a declaration", length(o2) == 0,
          if (length(o2)) sprintf("%d orphans", length(o2)) else "")
  }
  if (!is.null(cand)) {
    o3 <- setdiff(cand$declaration_id, decl$declaration_id)
    check("every candidate row resolves to a declaration", length(o3) == 0,
          if (length(o3)) sprintf("%d orphans", length(o3)) else "")
    check("declaration_candidates carries no amount column",
          !any(grepl("_chf$", names(cand))))
  }
  check("candidate_party set only when the candidate list agrees",
        !("candidate_party" %in% names(decl)) ||
          all(is.na(decl$candidate_party[!is.na(decl$candidate_count) &
                                           decl$candidate_count == "0"])))

  # Counted-once totals: the same figures restricted to each actor's latest
  # disclosure, which is what a headline number has to use. See R/disclosures.R.
  latest <- latest_disclosure(decl)
  latest_ids <- decl$declaration_id[latest]
  check("both budget and final disclosures are present",
        any(as.logical(decl$with_budget)) && any(!as.logical(decl$with_budget)),
        sprintf("%d of %d rows count once", sum(latest), nrow(decl)))

  snap[[lg]] <- list(
    decl_ids = sort(decl$declaration_id),
    cont_ids = sort(cont$contribution_id),
    income   = total(decl$total_income_chf),
    value    = total(cont$value_chf),
    mandate  = total(mand$amount_chf),
    income_once  = sum_where(decl$total_income_chf, latest),
    value_once   = sum_where(cont$value_chf, cont$declaration_id %in% latest_ids),
    mandate_once = if (is.null(mand)) NA_real_ else
      sum_where(mand$amount_chf, mand$declaration_id %in% latest_ids),
    n_latest = sum(latest)
  )
}

if (length(snap) > 1) {
  cat("\n== cross-language ==\n")
  ref <- names(snap)[1]
  for (lg in names(snap)[-1]) {
    check(sprintf("declaration_id set %s == %s", ref, lg),
          identical(snap[[ref]]$decl_ids, snap[[lg]]$decl_ids))
    check(sprintf("contribution_id set %s == %s", ref, lg),
          identical(snap[[ref]]$cont_ids, snap[[lg]]$cont_ids))
    for (m in c("income", "value", "mandate",
                "income_once", "value_once", "mandate_once")) {
      check(sprintf("sum of %s equal in %s and %s", m, ref, lg),
            isTRUE(all.equal(snap[[ref]][[m]], snap[[lg]][[m]], tolerance = 1e-6)),
            sprintf("%s vs %s", format(snap[[ref]][[m]], big.mark = ","),
                    format(snap[[lg]][[m]], big.mark = ",")))
    }
    check(sprintf("same disclosures count once in %s and %s", ref, lg),
          identical(snap[[ref]]$n_latest, snap[[lg]]$n_latest),
          sprintf("%d vs %d", snap[[ref]]$n_latest, snap[[lg]]$n_latest))
  }

  s <- snap[[ref]]
  chf <- function(x) format(round(x), big.mark = "'")

  # Two sets of totals, because there are two honest answers and picking the
  # wrong one is the easiest mistake to make with this dataset.
  cat("\nreference totals (one language)\n")
  cat("  counted once -- each actor's latest disclosure, use these for headline figures:\n")
  cat(sprintf("    declared income        CHF %s\n", chf(s$income_once)))
  cat(sprintf("    donations > 15k CHF    CHF %s\n", chf(s$value_once)))
  cat(sprintf("    mandate contributions  CHF %s\n", chf(s$mandate_once)))
  cat(sprintf("    disclosures            %d of %d rows\n", s$n_latest, length(s$decl_ids)))
  cat("  sum as-is -- budget plus final accounts, so the same francs twice:\n")
  cat(sprintf("    declared income        CHF %s\n", chf(s$income)))
  cat(sprintf("    donations > 15k CHF    CHF %s\n", chf(s$value)))
  cat(sprintf("    mandate contributions  CHF %s\n", chf(s$mandate)))
  cat("  See R/disclosures.R. Use the as-is sums only to compare budget against final.\n")
}

cat("\n", if (failures == 0L) "ALL CHECKS PASSED" else paste(failures, "CHECK(S) FAILED"), "\n", sep = "")
if (failures > 0L) quit(status = 1L)
