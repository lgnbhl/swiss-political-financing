# api.R -- polite HTTP client for the EFK frontend API.

suppressMessages({
  library(httr2)
  library(jsonlite)
  library(digest)
})

.log <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "|", ..., "\n")

# Build a request with shared defaults (UA, retry, throttle).
.req <- function(url) {
  request(url) |>
    req_user_agent(USER_AGENT) |>
    req_timeout(120) |>
    req_retry(max_tries = CONFIG$max_tries, backoff = function(i) min(2^i, 30)) |>
    req_throttle(rate = if (CONFIG$throttle > 0) 1 / CONFIG$throttle else 50)
}

# GET a JSON tree/detail endpoint. Returns the parsed body (list) or NULL on 4xx.
# lang: language code; path: e.g. "campaign_financings" or "allowances/4217".
# query: named list of query params (e.g. list(group_by = "elections")).
api_get_json <- function(lang, path, query = NULL) {
  url <- paste0(API_V1, "/", lang, "/", path)
  req <- .req(url) |> req_error(is_error = function(resp) FALSE)
  if (!is.null(query)) req <- req_url_query(req, !!!query)
  resp <- req_perform(req)
  status <- resp_status(resp)
  if (status >= 400) {
    .log("WARN", status, url, if (!is.null(query)) paste(names(query), unlist(query), sep = "=", collapse = "&") else "")
    return(NULL)
  }
  resp_body_json(resp, simplifyVector = FALSE)
}

# Download a binary file (xlsx). `path` is the download_path from the API
# (already includes /api/frontend/latest/...). Returns list(sha256, size, ok).
api_download <- function(download_path, dest) {
  url <- paste0(BASE_HOST, download_path)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  resp <- tryCatch(
    .req(url) |> req_error(is_error = function(resp) resp_status(resp) >= 400) |> req_perform(),
    error = function(e) { .log("WARN download failed:", url, conditionMessage(e)); NULL }
  )
  if (is.null(resp)) return(list(ok = FALSE, sha256 = NA_character_, size = 0L))
  body <- resp_body_raw(resp)
  writeBin(body, dest)
  list(ok = TRUE, sha256 = digest(body, algo = "sha256", serialize = FALSE), size = length(body))
}

# sha256 of a raw/string payload (used for change detection on JSON).
sha256_str <- function(x) digest(x, algo = "sha256", serialize = FALSE)

# sha256 of a file already on disk (stable provenance for cached artifacts).
sha256_file <- function(path) {
  if (file.exists(path)) digest(file = path, algo = "sha256") else NA_character_
}
