# build_checks.R
# ---------------------------------------------------------------------------
# The build is the only gate this app has.
#
# There is no test suite, and index.html is a committed artefact that an
# unattended weekly job rebuilds and pushes. So anything that would ship a
# broken page has to stop `Rscript app/build_site.R` -- the workflow fails the
# run on a non-zero exit, and nothing reaches the site.
#
# The checks, all cheap, all called from build_site.R, in the order they are
# defined below (a count here only goes stale, so there isn't one):
#
#   check_js()          the browser JS parses at all
#   check_i18n_usage()  every key the R code asks for exists
#   check_loaders()     every loader returns what its page reads, in every language
#   check_palette()     the palette can still give every series its own colour
#   check_html_shell()  the document has one <html> and one <body>
#   build_report()      the page did not silently double in size
# ---------------------------------------------------------------------------

# ---- 1. the browser JS parses ----------------------------------------------
# The JS in js/ is never executed at build time, so a stray comma used to reach
# the browser and fail there. `node --check` is a parse, not a run: fast, and it
# needs nothing installed. Skipped with a warning where node is absent (a
# contributor's laptop); CI installs node, so there it always runs.
check_js <- function(paths) {
  if (!nzchar(Sys.which("node"))) {
    message("! node not found -- skipping the JS syntax check")
    return(invisible(FALSE))
  }
  for (p in paths) {
    if (system2("node", c("--check", shQuote(p)), stdout = "", stderr = "") != 0L) {
      stop("syntax error in ", p, " (see the node output above)", call. = FALSE)
    }
  }
  invisible(TRUE)
}

# ---- 2. every i18n key the R code asks for exists ---------------------------
# The accessor already fails on an unknown key, but only when that line runs --
# and a page function only runs for the language and the branch being built. A
# key used in an `if` that is false today would surface months later. This walks
# the source instead, so every reachable key is checked on every build.
#
# Note for anyone extending this: the scan reads *this file too*, so a dotted
# key written inside a tr() call in a comment here would be demanded for real.
#
# Two families are built rather than written out, and are constructed here the
# same way the app constructs them.
i18n_dynamic_keys <- function(D) {
  list(
    # Required: a nav section with no label renders a blank link.
    required = paste0("nav.", NAV_SECTIONS),            # components.R::nav_links
    # Optional: catalogue_tables() scans the data folder, so a new table can
    # appear before anyone has described it. table_rows() leaves the sentence
    # blank and says so; the download itself still works.
    optional = paste0("data.tables.", D$tables$key)     # aggregate.R::table_rows
  )
}

check_i18n_usage <- function(D, exported, files = list.files(".", "\\.R$")) {
  src <- unlist(lapply(files, readLines, warn = FALSE, encoding = "UTF-8"))

  # Keys asked for by name -- a literal first argument to tr() or to t_().
  called <- unlist(regmatches(src, gregexpr('\\b(tr|t_)\\("[^"]+"', src)))
  called <- sub('^\\w+\\("', "", sub('"$', "", called))

  # Keys that reach tr() indirectly -- as a default argument, or handed down a
  # call like drill_error(lang, "votes", "nav.votes"). Recognised by shape, so
  # they are reported but not required: a dotted lowercase string is a strong
  # hint and a weak promise.
  shaped <- unlist(regmatches(src, gregexpr('"[a-z0-9_]+(\\.[a-z0-9_]+)+"', src)))
  shaped <- gsub('"', "", shaped, fixed = TRUE)

  defined <- i18n_keys("de")
  dynamic <- i18n_dynamic_keys(D)

  # Keys the loaders read in the browser as T.cols.date and the like. They never
  # pass through tr(), so without this every one of them would be reported
  # unused -- 68 of 241 keys, which is enough noise to make the report worthless.
  # What is embedded is used, by construction: build_site.R picks this bundle
  # key by key precisely so nothing travels that is not needed.
  shipped <- names(unlist(exported[["de"]]))

  missing <- setdiff(unique(c(called, dynamic$required)), defined)
  if (length(missing)) {
    stop("i18n: key(s) used in the R source but not defined: ",
         paste(sort(missing), collapse = ", "), call. = FALSE)
  }

  unused <- setdiff(defined, unique(c(called, shaped, unlist(dynamic), shipped)))
  if (length(unused)) {
    message("i18n: ", length(unused), " key(s) look unused: ",
            paste(sort(unused), collapse = ", "))
  }
  invisible(TRUE)
}

# ---- 3. every route loader runs and returns what its page reads --------------
# The one seam nothing else covers. A page reading `sumFmt` while its loader
# returns `totalFmt` builds cleanly, ships, and is broken only in a browser --
# the R side and the JavaScript side agree by convention and nothing checks it.
#
# js/smoke.js runs each loader against the data that was just embedded. What
# each page *reads* is not written out here: it is collected from the page
# itself, so adding a figure to a page automatically requires its loader to
# provide it.

# Every `selector = "..."` in a built page tree. Selectors reach the browser
# inside the `reactData` attribute htmltools carries on each tag, so both the
# tag structure and those attributes are walked. `loader_chart()` addresses
# chart props as "camps.margin"; the loader field is the part before the dot.
page_selectors <- function(x) {
  found <- character(0)
  walk <- function(name, v) {
    if (identical(name, "selector")) {
      if (is.character(v)) found <<- c(found, v)
      else if (is.list(v) && is.character(v$value)) found <<- c(found, v$value)
    }
    rd <- attr(v, "reactData")
    if (!is.null(rd)) walk("", rd)
    if (is.list(v)) {
      nm <- names(v)
      if (is.null(nm)) nm <- rep("", length(v))
      for (i in seq_along(v)) walk(nm[i], v[[i]])
    }
  }
  walk("", x)
  sort(unique(sub("\\..*$", "", found)))
}

check_loaders <- function(pages, html = "index.html") {
  if (!nzchar(Sys.which("node"))) {
    message("! node not found -- skipping the loader smoke test")
    return(invisible(FALSE))
  }
  expected <- lapply(pages, page_selectors)
  f <- tempfile(fileext = ".json")
  on.exit(unlink(f), add = TRUE)
  jsonlite::write_json(expected, f, auto_unbox = FALSE)

  if (system2("node", c("js/smoke.js", shQuote(html), shQuote(f))) != 0L) {
    stop("loader smoke test failed (see above)", call. = FALSE)
  }
  invisible(TRUE)
}

# ---- 4. the palette can still name every series -----------------------------
# The income components are the one series set whose length the data decides.
# income_parts() is built to absorb a component the EFK adds -- it says so and
# appends it -- and the party page then draws one series per component, taking
# colours from SERIES in order.
#
# SERIES has exactly as many slots as INCOME_ORDER has components, so there is no
# room for that eighth one. slot() in js/spf-charts.js keeps the chart from
# handing MUI X an undefined colour and letting it choose its own, but what it
# does instead is repeat the last slot -- and two income components in the same
# colour is a chart that misstates where a party's money came from.
#
# So the overflow stops the build here instead. The fix is a new validated slot in
# SERIES (see the header of components.R for the checker invocation), not a wider
# cap and not a fold: every component a party reports is worth naming.
check_palette <- function(parts, series) {
  if (length(parts) <= length(series)) return(invisible(TRUE))
  stop("palette: ", length(parts), " income components but SERIES has only ",
       length(series), " slots -- ",
       paste(utils::tail(parts, length(parts) - length(series)), collapse = ", "),
       " would have no colour of its own. Add a slot to SERIES in components.R ",
       "(validate it with scripts/validate_palette.js first).", call. = FALSE)
}

# ---- 5. the document is one document ----------------------------------------
# The page is assembled from three writers that do not know about each other:
# save_html() opens the document, muiMaterialPage() emits the app shell, and
# finish_head() patches the head afterwards. None of them can see what the others
# wrote, so a wrapper version that starts emitting its own <html><body> produces a
# page with two <html> tags and nothing notices -- which is exactly what a
# muiMaterial upgrade did, and the malformed page shipped, because browsers
# recover from it silently.
#
# The tags checked here are always written on lines of their own; the ~1.7 MB
# payload line is left alone, so `<html` inside a JSON string is not a tag.
check_html_shell <- function(file = "index.html") {
  html  <- trimws(readLines(file, warn = FALSE, encoding = "UTF-8"))
  where <- function(re) which(grepl(re, html))

  counts <- list(
    "<html>"   = where("^<html[ >]"),
    "</html>"  = where("^</html>$"),
    "<head>"   = where("^<head[ >]"),
    "</head>"  = where("^</head>$"),
    "<body>"   = where("^<body[ >]"),
    "</body>"  = where("^</body>$")
  )
  wrong <- names(counts)[lengths(counts) != 1L]
  # <body> is optional in HTML5 and htmltools has shipped pages without one;
  # what is never right is more than one, or a close without an open.
  optional <- c("<body>", "</body>")
  wrong <- wrong[!(wrong %in% optional & lengths(counts[wrong]) == 0L)]
  if (length(counts[["<body>"]]) != length(counts[["</body>"]])) {
    wrong <- union(wrong, optional)
  }
  if (length(wrong)) {
    stop(file, " is not a well-formed document -- ",
         paste(sprintf("%d x %s", lengths(counts[wrong]), wrong), collapse = ", "),
         ". Each of these belongs exactly once (<body> zero or once). This is ",
         "usually a wrapper package that changed what it emits; see the ",
         "DOCUMENT HEAD section of build_site.R.", call. = FALSE)
  }

  if (counts[["</head>"]] < counts[["<head>"]] ||
      (length(counts[["<body>"]]) && counts[["<body>"]] < counts[["</head>"]])) {
    stop(file, ": <head>, </head> and <body> are out of order -- the shell is ",
         "being written into the head.", call. = FALSE)
  }
  invisible(TRUE)
}

# ---- 6. the page did not silently grow --------------------------------------
# Everything ships in one document, so a regression that duplicates the data or
# the loaders shows up as bytes and nowhere else. The report is written next to
# the page and committed, so the size delta is visible in the diff of any
# commit rather than having to be measured by hand.
SIZE_LIMIT_KB <- 4096

build_report <- function(file, out = "build-report.json") {
  html <- readLines(file, warn = FALSE, encoding = "UTF-8")
  bytes <- nchar(html, type = "bytes")

  # Line-based rather than a regex over the whole document on purpose: the
  # payload is a single line of ~1.7 MB, and a lazy `.*?` across it overflows
  # PCRE's stack and takes R down with it.
  #
  # These tags never nest, so an opening tag seen while already inside one is
  # text -- a comment in the stylesheet, a string in the payload -- and not a
  # tag. Reading it as one made the block appear to run to the end of the file.
  inner <- function(tag) {
    inside <- FALSE; total <- 0L
    for (i in seq_along(html)) {
      opens  <- grepl(paste0("<", tag), html[i], fixed = TRUE)
      closes <- grepl(paste0("</", tag), html[i], fixed = TRUE)
      if (inside || opens) total <- total + bytes[i]
      if (!inside && opens && !closes) inside <- TRUE
      else if (inside && closes)       inside <- FALSE
    }
    total
  }
  kb <- function(b) round(b / 1024)

  report <- list(
    total_kb  = kb(file.size(file)),
    script_kb = kb(inner("script")),
    style_kb  = kb(inner("style"))
  )
  jsonlite::write_json(report, out, auto_unbox = TRUE, pretty = TRUE)

  cat(sprintf("Size: %s KB total (script %s KB, style %s KB)\n",
              format(report$total_kb, big.mark = "'"),
              format(report$script_kb, big.mark = "'"),
              format(report$style_kb, big.mark = "'")))

  if (report$total_kb > SIZE_LIMIT_KB) {
    stop(sprintf(paste("index.html is %s KB, over the %s KB limit.",
                       "Something is being embedded more than once."),
                 report$total_kb, SIZE_LIMIT_KB), call. = FALSE)
  }
  invisible(report)
}
