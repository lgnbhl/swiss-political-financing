# disclosures.R -- which disclosures represent money that exists, once.
#
# The EFK's data model discloses every campaign twice. An actor files a budget up
# front (`with_budget = TRUE`, declaration ids like `votes-18-B-004`) and final
# accounts afterwards (`FALSE`, `votes-18-F-004`); most events carry both. The two
# rows describe the same francs at two points in time, so adding them up
# double-counts: at the 2026-07-25 snapshot, CHF 80.6M of final donations plus
# CHF 69.5M of budgeted donations reads as a CHF 150M total that never existed.
#
# `latest_disclosure()` marks the rows to use when a figure should count each
# actor's money once: the final accounts where an actor has filed them, the budget
# where it has not yet -- the normal state for a vote that has not happened.
#
# This is a property of the dataset, not of any one consumer, which is why it
# lives here and is shared by R/checks.R and app/prepare_data.R rather than being
# reimplemented in each.
#
# Use the budget and final rows *together* only when the comparison itself is the
# point (planned against actual). Never sum across both for a headline total.

# `decl`: a declarations table, either as read from data/<lang>/exports/
# declarations.csv (all character) or already typed. Returns a logical vector,
# one element per row.
latest_disclosure <- function(decl) {
  need <- c("financing_id", "with_budget")
  missing <- setdiff(need, names(decl))
  if (length(missing)) {
    stop("latest_disclosure(): declarations table lacks ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  budget <- as.logical(decl$with_budget)
  if (anyNA(budget)) {
    stop("latest_disclosure(): with_budget must be TRUE/FALSE, got ",
         paste(unique(decl$with_budget[is.na(budget)]), collapse = ", "),
         call. = FALSE)
  }

  # A disclosure is identified by the event plus who filed it for what. Columns
  # are optional so this works on both the published CSV (actor, campaign_for,
  # candidate_party, candidate_canton) and the app's keyed core table
  # (actor_key, cfor_key, party_key, canton_key); whichever are present are used.
  id_cols <- intersect(
    c("actor", "actor_key", "campaign_for", "cfor_key",
      "candidate_party", "party_key", "candidate_canton", "canton_key"),
    names(decl)
  )
  # U+001F (unit separator) cannot occur in a label, so no value can straddle the
  # boundary between two fields and merge two distinct groups.
  key <- do.call(paste, c(list(decl$financing_id), unname(decl[id_cols]),
                          list(sep = "\x1f")))

  has_final <- tapply(!budget, key, any)
  as.logical(ifelse(as.vector(has_final[key]), !budget, TRUE))
}

# Total an amount column over the rows flagged by `keep`.
sum_where <- function(x, keep) sum(as.numeric(x)[keep], na.rm = TRUE)
