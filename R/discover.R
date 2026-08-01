# discover.R -- walk every theme tree in every language, snapshot the raw JSON,
# and flatten the nested nodes into tidy inventory / relationship tables.
#
# The six themes are alternate GROUPINGS of the same underlying entities
# (forms, allowances, people). We walk each grouping carrying the ancestor
# context, and emit one row per leaf of interest. This captures every
# relationship (actor <-> canton <-> party <-> event <-> form) without loss.

suppressMessages({
  library(dplyr)
  library(stringr)
})

# Pull a scalar field from a node (NULL -> NA).
.f <- function(node, key) {
  v <- node[[key]]
  if (is.null(v)) NA_character_ else as.character(v)
}

# Parse a leading "dd.mm.yyyy" date out of an event label.
.parse_date <- function(label) {
  m <- str_match(label, "^(\\d{2}\\.\\d{2}\\.\\d{4})")[, 2]
  m
}

# Recursive walker. `ctx` is a named character list of accumulated context;
# `sink` is an environment holding growing lists of row-lists.
.walk <- function(nodes, ctx, sink, meta) {
  for (node in nodes) {
    type <- .f(node, "type")
    nctx <- ctx

    if (type %in% c("campaign_financing", "party_financing")) {
      nctx$financing_id    <- .f(node, "id")
      nctx$financing_label <- .f(node, "label")
      nctx$financing_year  <- .f(node, "header_text")
      nctx$financing_type  <- type
      sink$events[[length(sink$events) + 1L]] <- c(meta, list(
        financing_id = nctx$financing_id, financing_type = type,
        label = nctx$financing_label, year = nctx$financing_year,
        date = .parse_date(nctx$financing_label %||% "")))
    } else if (type == "actor_category")  { nctx$actor_category <- .f(node, "label")
    } else if (type == "actor")           { nctx$actor_id <- .f(node, "id"); nctx$actor_label <- .f(node, "label")
    } else if (type == "canton")          { nctx$canton <- .f(node, "label")
    } else if (type == "political_party") { nctx$party <- .f(node, "label")
    } else if (type == "financing_category") { nctx$financing_category <- .f(node, "label")
    } else if (type == "campaign")        { nctx$campaign_tree_id <- .f(node, "id"); nctx$campaign_label <- .f(node, "label")
    } else if (type == "campaign_for")    { nctx$campaign_for <- .f(node, "label")
    } else if (type == "budget")          { nctx$budget_or_final <- .f(node, "label")
    } else if (type == "donor")           { nctx$donor_type <- .f(node, "label")
    }

    if (type == "form") {
      sink$forms[[length(sink$forms) + 1L]] <- c(meta, nctx, list(
        form_id = .f(node, "id"), campaign_id = .f(node, "campaign_id"),
        form_label = .f(node, "label"), download_path = .f(node, "download_path")))
    } else if (type == "allowance") {
      sink$allowances[[length(sink$allowances) + 1L]] <- c(meta, nctx, list(
        allowance_id = .f(node, "id"), allowance_label = .f(node, "label")))
    } else if (type == "person") {
      sink$people[[length(sink$people) + 1L]] <- c(meta, nctx, list(
        person_id = .f(node, "id"), person_label = .f(node, "label")))
    }

    kids <- node[["children"]]
    if (!is.null(kids) && length(kids)) .walk(kids, nctx, sink, meta)
  }
}

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# Walk all themes/groupings/languages. Writes raw tree JSON to raw_dir.
# Returns a named list of data frames.
discover_all <- function(languages, raw_dir) {
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  sink <- new.env()
  sink$forms <- list(); sink$allowances <- list(); sink$people <- list(); sink$events <- list()

  for (lang in languages) {
    for (theme in names(TREE_THEMES)) {
      groups <- TREE_THEMES[[theme]]
      group_vals <- if (length(groups) == 1 && is.na(groups)) list(NULL) else as.list(groups)
      for (gb in group_vals) {
        query <- if (is.null(gb)) NULL else list(group_by = gb)
        body <- api_get_json(lang, theme, query)
        gtag <- if (is.null(gb)) "all" else gb
        .log("discover", lang, theme, gtag,
             if (is.null(body)) "-> (none)" else "ok")
        if (is.null(body)) next
        # snapshot raw tree
        writeLines(toJSON(body, auto_unbox = TRUE, pretty = TRUE),
                   file.path(raw_dir, sprintf("%s__%s__%s.json", lang, theme, gtag)))
        roots <- body$data$tree_roots
        if (is.null(roots) || !length(roots)) next
        meta <- list(language = lang, theme = theme, group_by = gtag)
        .walk(roots, list(), sink, meta)
      }
    }
  }

  # A theme the portal has not populated yet still gets a header row, so the
  # resulting CSV is readable instead of a zero-byte file. Context columns are
  # added on top of these once the portal publishes any rows.
  bind <- function(rows, cols) {
    if (length(rows)) return(bind_rows(lapply(rows, as_tibble)))
    as_tibble(setNames(rep(list(character(0)), length(cols)), cols))
  }
  base_cols <- c("language", "theme", "group_by")
  list(
    forms      = bind(sink$forms, c(base_cols, "financing_id", "campaign_id", "form_id")),
    allowances = bind(sink$allowances, c(base_cols, "allowance_id", "allowance_label")),
    people     = bind(sink$people, c(base_cols, "person_id", "person_label")),
    events     = bind(sink$events, c("language", "financing_id", "financing_type", "label", "year", "date"))
  )
}
