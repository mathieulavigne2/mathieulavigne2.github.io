"""Check every link in the built site.

Internal links are resolved against docs/ on disk; external links get a real
network request. Run after build.R and before publishing:

    python tools/check-links.py

Exit status is non-zero if anything is broken, so it can gate a release.

Note on false positives: some publishers (Elgar, Sage) sit behind bot
protection and answer 403 to anything that is not a browser. Those are
reported separately as SUSPECT rather than BROKEN — check them by hand.
"""

import concurrent.futures
import html as htmllib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"

# A real browser UA. Several publishers and broadcasters refuse anything else,
# and a link that only a bot cannot fetch is not a broken link.
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
TIMEOUT = 25

# The site's own origin. Absolute links to it are really internal links, and
# must be resolved against docs/ - checking them over the network would just
# test whatever is currently published, which is exactly what we are changing.
SELF_ORIGIN = "https://mathieulavigne2.github.io"

# Publishers and broadcasters that block non-browser clients. A 4xx/5xx or a
# dropped connection from these is reported as SUSPECT, not BROKEN.
BOT_WALLED = ("elgaronline.com", "sagepub.com", "tandfonline.com",
              "cambridge.org", "academic.oup.com", "springer.com",
              "link.springer.com", "cbc.ca", "ledevoir.com", "lapresse.ca",
              "thestar.com", "theglobeandmail.com", "meo.ca",
              "saltwire.com", "qub.ca")

SKIP_SCHEMES = ("mailto:", "javascript:", "tel:", "data:", "#")

# Network failures that say more about this machine or a bot wall than about
# the link: corporate TLS interception, missing root certs, RST on a bot UA.
ENV_ERRORS = ("CERTIFICATE_VERIFY_FAILED", "ConnectionResetError",
              "IncompleteRead", "RemoteDisconnected")


def collect():
    """Return {url_or_path: {source files}} for every href/src in docs/."""
    found = {}
    for page in DOCS.rglob("*.html"):
        html = page.read_text(encoding="utf-8", errors="replace")
        for attr in re.findall(r'(?:href|src)="([^"]+)"', html):
            # Attribute values are HTML-escaped in the source, so a URL with
            # a query string arrives as ...&amp;binId=... Requesting that
            # verbatim 404s on a link that is in fact fine.
            attr = htmllib.unescape(attr)
            if attr.startswith(SKIP_SCHEMES):
                continue
            if attr.startswith(SELF_ORIGIN):
                attr = attr[len(SELF_ORIGIN):] or "/"
            found.setdefault(attr, set()).add(page.relative_to(DOCS).as_posix())
    return found


def check_internal(link, sources):
    target = link.split("#")[0].split("?")[0]
    if not target:
        return None

    if target.startswith("/"):
        candidate = DOCS / target.lstrip("/")
    else:
        # Relative: resolve against each referring page's directory.
        for src in sources:
            candidate = (DOCS / src).parent / target
            if candidate.exists() or _index_of(candidate).exists():
                return None
        candidate = (DOCS / sorted(sources)[0]).parent / target

    if candidate.exists() or _index_of(candidate).exists():
        return None
    return f"missing file: {target}"


def _index_of(path):
    return path / "index.html"


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_args):
        return None


def check_doi(url):
    """A DOI is healthy when doi.org issues a redirect for it.

    Following that redirect only tests whether the publisher happens to like
    our user agent today, which is a different question and not one this
    site can do anything about.
    """
    opener = urllib.request.build_opener(_NoRedirect)
    req = urllib.request.Request(url, headers={"User-Agent": UA}, method="HEAD")
    try:
        with opener.open(req, timeout=TIMEOUT) as resp:
            return resp.status, None
    except urllib.error.HTTPError as exc:
        if exc.code in (301, 302, 303, 307, 308):
            return 200, None  # resolved
        return exc.code, None
    except Exception as exc:  # noqa: BLE001
        return None, f"{type(exc).__name__}: {exc}"


def check_external(url):
    if url.startswith("https://doi.org/"):
        return check_doi(url)

    req = urllib.request.Request(url, headers={"User-Agent": UA})
    last = None
    for _ in range(2):  # one retry; transient 5xx and RSTs are common
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return resp.status, None
        except urllib.error.HTTPError as exc:
            if exc.code < 500:
                return exc.code, None
            last = (exc.code, None)
        except Exception as exc:  # noqa: BLE001
            last = (None, f"{type(exc).__name__}: {exc}")
    return last


def main():
    if not DOCS.exists():
        sys.exit("docs/ not found - run build.R first.")

    links = collect()
    internal = {k: v for k, v in links.items()
                if not urllib.parse.urlparse(k).scheme}
    external = {k: v for k, v in links.items()
                if urllib.parse.urlparse(k).scheme in ("http", "https")}

    print(f"Checking {len(internal)} internal and {len(external)} external "
          f"links across {len(list(DOCS.rglob('*.html')))} pages.\n")

    broken, suspect = [], []

    for link, sources in sorted(internal.items()):
        problem = check_internal(link, sources)
        if problem:
            broken.append((link, problem, sorted(sources)))

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(check_external, u): u for u in external}
        for future in concurrent.futures.as_completed(futures):
            url = futures[future]
            status, error = future.result()
            sources = sorted(external[url])
            walled = any(host in url for host in BOT_WALLED)
            if error:
                environmental = any(e in error for e in ENV_ERRORS)
                (suspect if (walled or environmental) else broken).append(
                    (url, error, sources))
            elif status >= 400:
                (suspect if walled else broken).append(
                    (url, f"HTTP {status}", sources))

    for label, rows in (("BROKEN", broken),
                        ("SUSPECT - bot wall or local TLS, check by hand",
                         suspect)):
        if rows:
            print(f"--- {label} ({len(rows)}) ---")
            for url, why, sources in sorted(rows):
                print(f"  {why}\n    {url}\n    on: {', '.join(sources[:4])}")
            print()

    if not broken and not suspect:
        print("All links OK.")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
