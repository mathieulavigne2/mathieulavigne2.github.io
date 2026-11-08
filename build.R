# Build the bilingual site.
#
# Quarto supports only one navbar per render, so the site is rendered twice
# under two profiles and the results are assembled into docs/:
#
#   _site-en/*     -> docs/         (English, served at the site root)
#   _site-fr/fr/*  -> docs/fr/      (French)
#
# Rendering both profiles straight into docs/ is deliberately avoided: the
# second render can clean up outputs it does not recognise from the first.
# Staging then assembling is slower but deterministic.
#
# Usage:  Rscript build.R
#
# Quarto is not on PATH on this machine; the only install ships with RStudio.
# Override with the QUARTO_PATH environment variable if yours lives elsewhere.

quarto_bin <- Sys.getenv(
  "QUARTO_PATH",
  "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe"
)

if (!file.exists(quarto_bin) && Sys.which("quarto") != "") {
  quarto_bin <- unname(Sys.which("quarto"))
}
if (!file.exists(quarto_bin)) {
  stop("Quarto not found. Set QUARTO_PATH to your quarto executable.\n",
       "  Tried: ", quarto_bin)
}

render_profile <- function(profile) {
  message("\n=== Rendering profile: ", profile, " ===")
  status <- system2(quarto_bin, c("render", "--profile", profile))
  if (status != 0) {
    stop("quarto render --profile ", profile, " failed (exit ", status, ")")
  }
}

# Copy the *contents* of `from` into `to`, creating `to` if needed.
copy_into <- function(from, to) {
  if (!dir.exists(from)) stop("Missing build output: ", from)
  dir.create(to, recursive = TRUE, showWarnings = FALSE)
  entries <- list.files(from, all.files = TRUE, no.. = TRUE, full.names = TRUE)
  ok <- file.copy(entries, to, recursive = TRUE, overwrite = TRUE)
  if (!all(ok)) stop("Failed copying some files from ", from, " to ", to)
}

# --- 1. Clean -------------------------------------------------------------
for (d in c("_site-en", "_site-fr", "docs")) {
  if (dir.exists(d)) unlink(d, recursive = TRUE)
}

# --- 2. Generate listing data ---------------------------------------------
# Turns data/publications.yml into the per-language listing inputs. Run in a
# child environment so its helpers do not leak into this script.
message("=== Generating publication listings ===")
source(file.path("R", "build-listings.R"), local = new.env())

# --- 3. Render both languages ---------------------------------------------
render_profile("en")
render_profile("fr")

# --- 4. Assemble ----------------------------------------------------------
message("\n=== Assembling docs/ ===")

# English sits at the site root.
copy_into("_site-en", "docs")

# French output keeps its fr/ prefix inside _site-fr, which is exactly the
# depth it needs in docs/ — so relative links like ../assets/ still resolve.
copy_into(file.path("_site-fr", "fr"), file.path("docs", "fr"))

# --- 5. Prune ------------------------------------------------------------
# Quarto still writes a search index even with `search: false`, and it would
# be the English one only. Nothing references it; drop it so the published
# site does not carry a stale half-index.
unlink(file.path("docs", "search.json"))

# Quarto also copies the webfonts next to the compiled stylesheet, because it
# spots them in the CSS. Nothing points there - the @font-face URLs are
# absolute (/assets/fonts/...) - so it is ~260 KB of dead weight per language.
for (d in c(
  file.path("docs", "site_libs", "bootstrap", "assets"),
  file.path("docs", "fr", "site_libs", "bootstrap", "assets")
)) {
  if (dir.exists(d)) unlink(d, recursive = TRUE)
}

# Each render writes its own sitemap.xml, and only the English one lands at
# the root (robots.txt points there). Merge the French <url> entries into it,
# and drop the legacy /Français/ page, which is only a redirect.
sm_path <- file.path("docs", "sitemap.xml")
sm_fr_path <- file.path("_site-fr", "sitemap.xml")
if (file.exists(sm_path) && file.exists(sm_fr_path)) {
  url_blocks <- function(x) {
    regmatches(x, gregexpr("(?s)<url>.*?</url>", x, perl = TRUE))[[1]]
  }
  sm <- paste(readLines(sm_path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  sm_fr <- paste(readLines(sm_fr_path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  urls <- c(url_blocks(sm), url_blocks(sm_fr))
  urls <- urls[!grepl("Fran(ç|%C3%A7)ais", urls, perl = TRUE)]
  out <- c(
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    paste0("  ", urls),
    "</urlset>"
  )
  con <- file(sm_path, open = "w", encoding = "UTF-8")
  writeLines(out, con)
  close(con)
}

# --- 6. Report ------------------------------------------------------------
files <- list.files("docs", recursive = TRUE, all.files = TRUE, no.. = TRUE)
pages <- grep("\\.html$", files, value = TRUE)
total_mb <- sum(file.size(file.path("docs", files)), na.rm = TRUE) / 1024^2

message(sprintf(
  "\nBuilt %d HTML pages, %d files, %.1f MB in docs/",
  length(pages), length(files), total_mb
))

big <- files[file.size(file.path("docs", files)) > 1024^2]
if (length(big)) {
  message("\nWARNING - files over 1 MB in the published site:")
  for (f in big) message("  ", f)
}

# A plain `file://` open will NOT work: the language toggle, the fonts and the
# CV links are all root-relative, so the site must be served from docs/ as the
# document root.
message("\nPreview with:  python -m http.server 22222 --directory docs")
message("then open      http://localhost:22222/")
