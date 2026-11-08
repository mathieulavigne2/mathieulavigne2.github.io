<%
// Custom listing template: publications as a scannable stack, not a card grid
// and not a dense bibliographic run-on.
//
// Each entry is four stacked bands, in the order people actually read them:
//
//     Title                     bold, own line, the only thing you scan for
//     with A, B, and C          co-authors only; see R/build-listings.R
//     Venue · Year · Note       muted source line
//     [Read more] [Replication] actions
//
// The previous version packed authors, year, title and venue into one
// hanging-indent paragraph. It was correct as a citation and awful to scan:
// every entry opened with the same nine characters ("Mathieu L...") and the
// title — the only distinguishing part — sat mid-sentence.
//
// EJS context for a CUSTOM template (i.e. one supplied via `template:`) is
// NOT the same as for Quarto's built-in types. Quarto passes exactly:
//
//     items           the (already reshaped) array of listing items
//     metadataAttrs   function(item) -> the data-* attribute string
//     templateParams  whatever you put under `template-params:`
//     utils           { b64encode, b64decode }
//
// There is no `listing` object here — referencing it throws. That is why the
// localized labels arrive via template-params.
//
// Entries deliberately do NOT carry Quarto's `quarto-post` class, even though
// its own listing templates do. Two of its rules wreck this layout:
//
//   .quarto-post           { display: flex; gap: 2em }
//   div.quarto-post .listing-categories { display: flex }
//
// The first turns the four stacked bands into four side-by-side columns. The
// second outranks .pub-hidden on specificity and forces the theme labels —
// which are emitted for search only — back into view beside every entry.
// quarto-listing.js never looks for the class, so dropping it is free.
//
// Contract with quarto-listing.js, all three parts required:
//   * container MUST carry class `list` — List.js binds to `#listing-<id> .list`;
//   * each item MUST carry metadataAttrs(item), which emits data-index,
//     data-categories and the sort keys. Category filtering and sorting
//     silently break without it;
//   * searchable text MUST sit in an element classed `listing-<field>` for
//     each field named in the listing's `fields:`, because that is where
//     List.js `searchColumns` reads. The single search box in
//     html/research-search.html drives every listing through that.
//
// That last rule is why `authors` and `categories` are still emitted even
// though neither is displayed: they go out inside .pub-hidden. Search over a
// co-author's name therefore still works, and so does search over a theme,
// even though the theme chips themselves are gone from the entries (the
// margin facet remains the way to filter by theme). Deleting those two spans
// would silently narrow the search box to title + venue + year.
//
// Two delimiter gotchas, both of which cost real debugging time:
//
//  1. NEVER write a percent-greater-than sequence inside this comment. EJS
//     scans for the closing delimiter without understanding JS comments, so
//     it would terminate the block right here and the template would fail to
//     compile with a bare "Unexpected token ')'".
//
//  2. Quarto uses lodash-style delimiters, so the "equals" form interpolates
//     RAW and the "hyphen" form ESCAPES. That is the opposite of what people
//     expect from classic EJS. Quarto's own listing-default.ejs.md relies on
//     it: metadataAttrs goes through the equals form, and escaping it yields
//     data-index="'0'" and dead category filtering.
//
// So: equals form for pre-built HTML (metadataAttrs, venue), hyphen form for
// plain text and URLs.

const params = typeof templateParams !== "undefined" ? templateParams : {};
const labelRead = params.label_read || "Read more";
const labelReplication = params.label_replication || "Replication materials";
const labelWith = params.label_with || "with";
%>

```{=html}
<div class="list pub-list">
<% for (const item of items) { %>
  <div class="pub-entry" <%= metadataAttrs(item) %>>

    <div class="pub-title-row">
      <% if (item.link) { %><a class="listing-title pub-title" href="<%- item.link %>"><%- item.title %></a><% } else { %><span class="listing-title pub-title"><%- item.title %></span><% } %>
    </div>

    <% if (item.coauthors) { %>
    <div class="pub-byline"><%- labelWith %> <%- item.coauthors %></div>
    <% } %>

    <div class="pub-source">
      <% if (item.venue) { %><span class="listing-venue pub-venue"><%= item.venue %></span><span class="pub-sep">·</span><% } %>
      <span class="listing-year pub-year"><%- item.year %></span>
      <% if (item.note) { %><span class="pub-sep">·</span><span class="pub-note"><%- item.note %></span><% } %>
    </div>

    <% if (item.link || item.replication) { %>
    <div class="pub-actions">
      <% if (item.link) { %><a class="pub-btn pub-btn-primary" href="<%- item.link %>"><%- labelRead %></a><% } %>
      <% if (item.replication) { %><a class="pub-btn" href="<%- item.replication %>"><%- labelReplication %></a><% } %>
    </div>
    <% } %>

    <span class="listing-authors pub-hidden"><%- item.authors %></span>
    <% if (item.categories) { %><span class="listing-categories pub-hidden"><%- item.categories.join(", ") %></span><% } %>
  </div>
<% } %>
</div>
```
