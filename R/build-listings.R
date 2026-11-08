# Generate the per-language Quarto listing inputs for the Research page.
#
#   data/publications.yml  +  data/themes.yml
#        -> research/publications.yml       (English)
#        -> fr/research/publications.yml    (French)
#
# Those two outputs are build artefacts. Never edit them; edit the canonical
# files in data/ instead. build.R calls this before rendering.
#
# Usage:  Rscript R/build-listings.R

suppressPackageStartupMessages(library(yaml))

KINDS <- c("article", "chapter", "report", "working-paper")

`%||%` <- function(a, b) if (is.null(a) || !nzchar(a)) b else a

# --- Load ------------------------------------------------------------------

pubs <- yaml::read_yaml("data/publications.yml")
themes <- yaml::read_yaml("data/themes.yml")

theme_ids <- vapply(themes, function(t) t$id, character(1))
theme_label <- list(
  en = setNames(vapply(themes, function(t) t$en, character(1)), theme_ids),
  fr = setNames(vapply(themes, function(t) t$fr, character(1)), theme_ids)
)

# --- Validate --------------------------------------------------------------
# Fail loudly here rather than shipping a listing with a silently missing
# facet or a duplicate entry.

problems <- character(0)

ids <- vapply(pubs, function(p) p$id %||% "", character(1))

dupes <- unique(ids[duplicated(ids)])
if (length(dupes)) {
  problems <- c(problems, paste("Duplicate id:", paste(dupes, collapse = ", ")))
}

for (p in pubs) {
  if (!isTRUE(p$kind %in% KINDS)) {
    problems <- c(problems, sprintf(
      "%s: unknown kind '%s' (expected one of %s)",
      p$id, p$kind, paste(KINDS, collapse = ", ")
    ))
  }
  unknown <- setdiff(unlist(p$themes), theme_ids)
  if (length(unknown)) {
    problems <- c(problems, sprintf(
      "%s: theme(s) not in data/themes.yml: %s",
      p$id, paste(unknown, collapse = ", ")
    ))
  }
  if (is.null(p$title) || !nzchar(p$title)) {
    problems <- c(problems, sprintf("%s: missing title", p$id))
  }
}

if (length(problems)) {
  stop("data/publications.yml has problems:\n  - ",
       paste(problems, collapse = "\n  - "), call. = FALSE)
}

# --- Report outstanding checks --------------------------------------------

needs_doi_check <- Filter(function(p) isTRUE(p$verify_doi), pubs)
missing_link <- Filter(function(p) {
  is.null(p$doi) && (is.null(p$url) || !nzchar(p$url)) && p$kind != "working-paper"
}, pubs)

if (length(needs_doi_check)) {
  message(sprintf(
    "NOTE: %d DOI(s) still flagged verify_doi -- test these resolve before publishing:",
    length(needs_doi_check)
  ))
  for (p in needs_doi_check) message("        https://doi.org/", p$doi)
}
if (length(missing_link)) {
  message(sprintf("NOTE: %d published item(s) have no DOI and no URL:",
                  length(missing_link)))
  for (p in missing_link) message("        ", p$id)
}

# --- Emit ------------------------------------------------------------------

pick <- function(p, field, lang) {
  localized <- p[[paste0(field, "_", lang)]]
  if (!is.null(localized) && nzchar(localized)) return(localized)
  p[[field]]
}

# The template writes venue out raw, so convert the *markdown* emphasis
# authors naturally use in data/publications.yml into real <em> tags, and
# neutralise any stray angle brackets first.
markdown_em <- function(s) {
  if (is.null(s) || !nzchar(s)) return(s)
  s <- gsub("&", "&amp;", s, fixed = TRUE)
  s <- gsub("<", "&lt;", s, fixed = TRUE)
  s <- gsub(">", "&gt;", s, fixed = TRUE)
  gsub("\\*([^*]+)\\*", "<em>\\1</em>", s)
}

# --- Co-authors ------------------------------------------------------------
# This is Mathieu's own publication list, so printing his name on all 27
# entries is noise. Entries read "with <co-authors>" instead, and solo-authored
# work carries no author line at all.
#
# `authors` in data/publications.yml stays a single display string: it is what
# a human wants to read and edit, and it still feeds search (the template
# emits it hidden, so looking up a dropped name keeps working). Splitting it
# back into names is this function's job.
#
# NOTE: dropping his name also drops his POSITION in the list. First-authored
# and fifth-authored work now look alike. That is the intended trade — say so
# if you ever want an "authors" line back for peer-reviewed work.

SELF <- "Mathieu Lavigne"

split_authors <- function(s) {
  # "... and 32 others (including Mathieu Lavigne)" — the parenthetical is a
  # note about authorship rather than a name, so drop it whole. Leaving it
  # would strip the name and emit a stray "(including )".
  s <- gsub("\\s*\\(including [^)]*\\)", "", s)
  s <- gsub(",\\s+and\\s+", ", ", s)  # Oxford comma before the final name
  s <- gsub("\\s+and\\s+", ", ", s)   # two-author case, which has no comma
  parts <- trimws(strsplit(s, ",\\s*")[[1]])
  parts[nzchar(parts)]
}

join_names <- function(names, lang) {
  n <- length(names)
  if (n <= 1) return(paste(names, collapse = ""))
  conj <- if (lang == "fr") "et" else "and"
  # French takes no comma before the final conjunction; English keeps the
  # Oxford comma, but only from three names up.
  if (lang == "fr" || n == 2) {
    paste(paste(names[-n], collapse = ", "), conj, names[n])
  } else {
    paste0(paste(names[-n], collapse = ", "), ", ", conj, " ", names[n])
  }
}

coauthors_of <- function(s, lang) {
  if (is.null(s) || !nzchar(s)) return("")
  names <- setdiff(split_authors(s), SELF)
  if (!length(names)) return("")
  # "and 9 others" is a generic phrase, not a name, so it does get localized.
  if (lang == "fr") names <- sub("^([0-9]+) others$", "\\1 autres", names)
  join_names(names, lang)
}

build_items <- function(lang) {
  lapply(pubs, function(p) {
    link <- if (!is.null(p$doi)) paste0("https://doi.org/", p$doi) else p$url

    item <- list(
      title      = pick(p, "title", lang),
      authors    = p$authors,
      venue      = markdown_em(pick(p, "venue", lang) %||% ""),
      year       = as.character(p$year),
      date       = as.character(p$date),
      kind       = p$kind,
      # as.list() matters: a length-1 character vector would be written as a
      # YAML scalar, and Quarto's metadataAttrs() calls .join() on it.
      categories = as.list(unname(theme_label[[lang]][unlist(p$themes)]))
    )

    # Optional fields: omit rather than emit empty strings, so the template
    # can test for presence.
    if (!is.null(link) && nzchar(link)) {
      item$path <- link
      item$link <- link
    }
    if (!is.null(p$doi)) item$doi <- p$doi
    if (!is.null(p$replication) && nzchar(p$replication)) {
      item$replication <- p$replication
    }
    note <- pick(p, "note", lang)
    if (!is.null(note) && nzchar(note)) item$note <- note

    # Institutionally-authored work (the GDI report) names the same body as
    # author and as publisher, which rendered as "with Global Disinformation
    # Index" sitting directly above "Global Disinformation Index". Drop the
    # byline when it would only repeat the source line.
    coauthors <- coauthors_of(p$authors, lang)
    if (nzchar(coauthors) && !identical(coauthors, pick(p, "venue", lang))) {
      item$coauthors <- coauthors
    }

    item
  })
}

write_yaml_utf8 <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  header <- paste(
    "# GENERATED FILE - do not edit.",
    "# Produced by R/build-listings.R from data/publications.yml.",
    "# Edit the canonical file in data/ instead.",
    "", sep = "\n"
  )
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeLines(enc2utf8(paste0(header, yaml::as.yaml(x))), con, useBytes = TRUE)
}

write_yaml_utf8(build_items("en"), file.path("research", "publications.yml"))
write_yaml_utf8(build_items("fr"), file.path("fr", "research", "publications.yml"))

by_kind <- table(factor(vapply(pubs, function(p) p$kind, character(1)),
                        levels = KINDS))
message(sprintf("\nWrote %d publications to both language listings:", length(pubs)))
for (k in KINDS) message(sprintf("  %-14s %d", k, by_kind[[k]]))
