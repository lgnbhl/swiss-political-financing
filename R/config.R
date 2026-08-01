# config.R -- constants, schemas and run configuration for the EFK scraper.
# All values can be overridden via environment variables so the GitHub Action
# can tune behaviour without editing code.

BASE_HOST <- "https://politikfinanzierung.efk.admin.ch"
API_V1    <- paste0(BASE_HOST, "/api/frontend/v1")      # JSON tree / detail API
API_DL    <- paste0(BASE_HOST, "/api/frontend/latest")  # file download API
USER_AGENT <- "swiss-political-financing-scraper (github action; contact via repo)"

# --- run configuration -------------------------------------------------------
env_flag <- function(name, default) {
  v <- Sys.getenv(name, unset = NA)
  if (is.na(v) || v == "") return(default)
  tolower(v) %in% c("1", "true", "yes", "on")
}
env_chr <- function(name, default) {
  v <- Sys.getenv(name, unset = NA)
  if (is.na(v) || v == "") return(default)
  trimws(strsplit(v, ",")[[1]])
}

CONFIG <- list(
  # Languages to capture. Amounts are identical across languages; only labels differ.
  languages = env_chr("EFK_LANGUAGES", c("de", "fr", "it")),
  # Download and archive every individual filed form (.xlsx). Files are small (~5 KB).
  archive_form_files = env_flag("EFK_ARCHIVE_FORMS", TRUE),
  # Languages for which to archive the individual form files.
  archive_form_langs = env_chr("EFK_ARCHIVE_FORM_LANGS", c("de", "fr", "it")),
  # Polite pause (seconds) between HTTP requests.
  throttle = as.numeric(Sys.getenv("EFK_THROTTLE", "0.15")),
  # Max retries per request (transient errors).
  max_tries = as.integer(Sys.getenv("EFK_MAX_TRIES", "4"))
)

# --- API surface -------------------------------------------------------------
# Tree endpoints: name -> required group_by values (NA = no group_by param).
# Each theme is a different grouping of the same underlying entities.
TREE_THEMES <- list(
  campaign_financings = NA,
  party_financings    = NA,
  campaign_candidates = c("alphabetical", "by_canton", "by_political_party"),
  actors              = c("alphabetical", "by_canton"),
  allowances          = c("alphabetical", "by_amount"),
  people              = c("office", "election")
)

# Bulk export categories (exports theme group_by -> canonical category key).
EXPORT_CATEGORIES <- c(elections = "elections",
                       votes = "votes",
                       party_financings = "party")

# --- bulk export column mapping ----------------------------------------------
# Export layouts differ BETWEEN categories and have also drifted over time
# (e.g. votes exports gained ID columns in 2026), so positional mapping is
# unsafe. Instead we map each localized HEADER to a canonical snake_case name
# via a trilingual (de/fr/it) dictionary. Unknown headers are kept with a
# sanitized name so no data is ever dropped. Missing columns simply stay absent
# and are filled with NA when the per-category tables are row-bound.

norm_header <- function(x) {
  x <- tolower(trimws(x))
  # strip common Latin diacritics so matching is encoding-robust
  x <- chartr("àâäéèêëîïôöòóùûüç",
              "aaaeeeeiioooouuuc", x)
  gsub("\\s+", " ", x)
}

# canonical -> all known localized header variants
.HEADER_VARIANTS <- list(
  disclosure_run   = c("Offenlegungslauf", "Periode de declaration", "Période de déclaration", "Periodo di comunicazione"),
  data_status      = c("Datenstand", "Base de donnees", "Base de données", "Database"),
  date             = c("Datum", "Date", "Data"),
  actor            = c("Akteur", "Akteur/in", "Acteur", "Acteur/trice", "Attore", "Attore/trice"),
  actor_id         = c("ID Akteur", "ID Akteur/in", "ID acteur", "ID attore", "ID attore/trice"),
  actor_type       = c("Art des Akteurs", "Type d'acteur", "Tipo di attore"),
  campaign         = c("Kampagne", "Campagne", "Campagna"),
  campaign_id      = c("ID Kampagne", "ID campagne", "ID campagna"),
  campaign_for     = c("Kampagne fur", "Kampagne für", "Campagne pour", "Campagna per"),
  last_name        = c("Name", "Nom", "Cognome"),
  first_name       = c("Vorname", "Prenom", "Prénom", "Nome"),
  candidate_group  = c("kandidierende Gruppierung", "Groupement politique candidat", "Gruppo candidato"),
  canton           = c("Kanton", "Canton", "Cantone"),
  party_affiliation = c("Parteizugehorigkeit (Mutterpartei)", "Parteizugehörigkeit (Mutterpartei)",
                        "Affiliation au parti politique national (parti-mere)",
                        "Affiliation au parti politique national (parti-mère)",
                        "Appartenenza al partito nazionale"),
  disclosure_report = c("Offenlegungsmeldung", "Declaration", "Déclaration", "Comunicazioni"),
  form_id          = c("ID Offenlegungsmeldung", "ID declaration", "ID déclaration", "ID comunicazione"),
  total_income_chf = c("Gesamtbetrag der Einnahmen (in CHF)", "Montant total des recettes (en CHF)",
                       "Importo totale delle entrate (in CHF)"),
  monetary_donations_chf = c("Einnahmen durch monetare Zuwendungen (in CHF)",
                             "Einnahmen durch monetäre Zuwendungen (in CHF)",
                             "Recettes provenant de liberalites monetaires (en CHF)",
                             "Recettes provenant de libéralités monétaires (en CHF)",
                             "Entrate provenienti da liberalita monetarie (in CHF)",
                             "Entrate provenienti da liberalità monetarie (in CHF)"),
  nonmonetary_donations_value_chf = c("Wert der Einnahmen durch nichtmonetare Zuwendungen (in CHF)",
                                      "Wert der Einnahmen durch nichtmonetäre Zuwendungen (in CHF)",
                                      "Valeur des recettes provenant de liberalites non-monetaires (en CHF)",
                                      "Valeur des recettes provenant de libéralités non-monétaires (en CHF)",
                                      "Valore delle entrate provenienti da liberalita non monetarie (in CHF)",
                                      "Valore delle entrate provenienti da liberalità non monetarie (in CHF)"),
  event_income_chf = c("Einnahmen durch Veranstaltungen (in CHF)", "Recettes generees par des evenements (en CHF)",
                       "Recettes générées par des événements (en CHF)", "Entrate da manifestazioni (in CHF)"),
  goods_services_income_chf = c("Einnahmen durch den Verkauf von Gutern und Dienstleistungen (in CHF)",
                                "Einnahmen durch den Verkauf von Gütern und Dienstleistungen (in CHF)",
                                "Recettes provenant de la vente de biens et de services (en CHF)",
                                "Entrate dalla vendita di beni e servizi (in CHF)"),
  monetary_own_funds_chf = c("Monetare Eigenmittel (in CHF)", "Monetäre Eigenmittel (in CHF)",
                             "Fonds propres monetaires (en CHF)", "Fonds propres monétaires (en CHF)",
                             "Fondi propri monetari (in CHF)"),
  membership_fees_chf = c("Einnahmen durch Mitgliederbeitrage (in CHF)", "Einnahmen durch Mitgliederbeiträge (in CHF)",
                          "Recettes provenant de cotisations de membres (en CHF)",
                          "Entrate risultanti dai contributi dei membri (in CHF)"),
  mandate_contributions_income_chf = c("Einnahmen durch Mandatsbeitrage (in CHF)",
                                       "Einnahmen durch Mandatsbeiträge (in CHF)",
                                       "Recettes provenant de contributions liees a un mandat (en CHF)",
                                       "Recettes provenant de contributions liées à un mandat (en CHF)",
                                       "Entrate da contributi legati a un mandato (in CHF)"),
  anonymous_donation = c("anonyme Zuwendung", "Liberalite anonyme", "Libéralité anonyme", "Liberalita anonima", "Liberalità anonima"),
  donation_id      = c("ID Zuwendung", "ID liberalite", "ID libéralité", "ID liberalita", "ID liberalità"),
  donor_last_name  = c("Name des Urhebers der Zuwendung", "Nom de l'auteur de la liberalite",
                       "Nom de l'auteur de la libéralité", "Nom de l'auteur/e de la libéralité",
                       "Cognome del donatore della liberalita", "Cognome del donatore della liberalità"),
  donor_first_name = c("Vorname des Urhebers der Zuwendung", "Prenom de l'auteur de la liberalite",
                       "Prénom de l'auteur de la libéralité", "Prénom de l'auteur/e de la libéralité",
                       "Nome del donatore della liberalita", "Nome del donatore della liberalità"),
  donor_residence  = c("Wohnsitzgemeinde", "Commune de residence", "Commune de résidence", "Comune di residenza"),
  donor_country    = c("Land", "Pays", "Paese"),
  swiss_abroad     = c("Auslandschweizer/in", "Suisse/esse de l'etranger", "Suisse/esse de l'étranger",
                       "Suisse de l'etranger", "Suisse de l'étranger", "Svizzeri all'estero"),
  donor_company    = c("Firma des Urhebers der Zuwendung", "Societe de l'auteur de la liberalite",
                       "Société de l'auteur de la libéralité", "Société de l'auteur/e de la libéralité",
                       "Azienda donatrice della liberalita", "Azienda donatrice della liberalità"),
  donor_company_domicile = c("Gemeinde des Geschaftssitzes", "Gemeinde des Geschäftssitzes",
                             "Commune du siege social", "Commune du siège social", "Comune della sede sociale"),
  donation_type    = c("Art der Zuwendung", "Nature de la liberalite", "Nature de la libéralité",
                       "Natura della liberalita", "Natura della liberalità"),
  service_type     = c("Art der Leistung", "Type de prestation", "Tipo di prestazione"),
  service_description = c("Beschreibung der Leistung", "Description de la prestation", "Descrizione della prestazione"),
  value_chf        = c("Wert (in CHF)", "Valeur (en CHF)", "Valore (in CHF)"),
  donation_date    = c("Gewahrungsdatum der Zuwendung", "Gewährungsdatum der Zuwendung",
                       "Date d'octroi de la liberalite", "Date d'octroi de la libéralité",
                       "Data di concessione della liberalita", "Data di concessione della liberalità"),
  mandate_id       = c("ID Mandatsbeitrag", "ID contribution liee au mandat", "ID contribution liée au mandat",
                       "ID contributo legato a un mandato"),
  institution      = c("Institution", "Istituzione"),
  amount_chf       = c("Betrag (in CHF)", "Montant (en CHF)", "Importo (in CHF)")
)

# Flat lookup: normalized header -> canonical name.
HEADER_MAP <- local({
  keys <- character(0); vals <- character(0)
  for (cn in names(.HEADER_VARIANTS)) {
    v <- .HEADER_VARIANTS[[cn]]
    keys <- c(keys, norm_header(v)); vals <- c(vals, rep(cn, length(v)))
  }
  setNames(vals, keys)
})

# Which output table each sheet index feeds (income=1, contributions=2, mandate=3).
# Sheet order is stable; names are localized so we key by index.
SHEET_TABLE <- c("income", "contributions", "mandate_contributions")
