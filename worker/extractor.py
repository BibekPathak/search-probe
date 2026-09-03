"""Playwright extraction for the SearchProbe browser worker.

The worker owns a full (headless) Chromium instance per request and returns
normalized organic results -- or a structured error the Rails planner maps onto
the shared failure taxonomy (timeout, rate_limited, blocked, captcha,
parse_error, network_error, unknown). Deliberately dumb: it navigates to a URL
and extracts whatever the page rendered, which is exactly the "browser can see
what curl cannot" story the planner exploits.
"""

from __future__ import annotations

import os
import re
import time

from playwright.sync_api import (
    TimeoutError as PlaywrightTimeoutError,
    sync_playwright,
)

CAPTCHA_SELECTOR = '[data-challenge="captcha"]'
RESULT_SELECTOR = ".result"
LINK_SELECTOR = "h3.result-title a"
SNIPPET_SELECTOR = "p.result-snippet"

DEFAULT_NAV_TIMEOUT_MS = int(os.environ.get("WORKER_NAV_TIMEOUT_MS", "15000"))
HEADLESS = os.environ.get("BROWSER_HEADLESS", "true").lower() != "false"


class ExtractionError(Exception):
    """Structured failure understood by the Rails planner."""

    def __init__(self, error_type: str, message: str, http_status: int | None = None):
        super().__init__(message)
        self.error_type = error_type
        self.http_status = http_status


def _extract_cards(page) -> list[dict]:
    results: list[dict] = []
    cards = page.locator(RESULT_SELECTOR)
    for index in range(cards.count()):
        card = cards.nth(index)
        link = card.locator(LINK_SELECTOR)
        if link.count() == 0:
            continue
        url = (link.first.get_attribute("href") or "").strip()
        if not url:
            continue
        title = re.sub(r"\s+", " ", link.first.inner_text()).strip()
        snippet_el = card.locator(SNIPPET_SELECTOR)
        snippet = ""
        if snippet_el.count() > 0:
            snippet = re.sub(r"\s+", " ", snippet_el.first.inner_text()).strip()
        position = int(card.get_attribute("data-position") or index + 1)
        results.append(
            {
                "position": position,
                "title": title or "(untitled)",
                "url": url,
                "snippet": snippet,
                "result_type": "organic",
            }
        )
    return results


def _status_to_error(http_status: int) -> str:
    if http_status in (401, 403):
        return "blocked"
    if http_status == 429:
        return "rate_limited"
    if http_status == 408:
        return "timeout"
    if http_status >= 500:
        return "unknown"
    return "parse_error"


def run_extraction(
    url: str,
    query: str,
    engine: str,
    timeout_ms: int = DEFAULT_NAV_TIMEOUT_MS,
) -> dict:
    started = time.monotonic()
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=HEADLESS)
            try:
                page = browser.new_page()
                try:
                    response = page.goto(url, wait_until="domcontentloaded", timeout=timeout_ms)
                    page.wait_for_selector(
                        f"{RESULT_SELECTOR}, {CAPTCHA_SELECTOR}",
                        timeout=timeout_ms,
                    )
                except PlaywrightTimeoutError as exc:
                    raise ExtractionError(
                        "timeout", f"page did not become ready within {timeout_ms}ms"
                    ) from exc

                http_status = response.status if response is not None else None

                if page.locator(CAPTCHA_SELECTOR).count() > 0:
                    raise ExtractionError(
                        "captcha", "browser was presented a CAPTCHA challenge", http_status
                    )

                results = _extract_cards(page)
                if not results:
                    raise ExtractionError(
                        _status_to_error(http_status) if http_status else "parse_error",
                        "no organic results rendered in the page",
                        http_status,
                    )

                latency_ms = int((time.monotonic() - started) * 1000)
                return {
                    "success": True,
                    "results": results,
                    "latency_ms": latency_ms,
                    "metadata": {"http_status": http_status},
                }
            finally:
                browser.close()
    except ExtractionError as exc:
        latency_ms = int((time.monotonic() - started) * 1000)
        return {
            "success": False,
            "error": {
                "type": exc.error_type,
                "message": str(exc),
                "http_status": exc.http_status,
            },
            "latency_ms": latency_ms,
        }
    except Exception as exc:  # pragma: no cover - defensive
        latency_ms = int((time.monotonic() - started) * 1000)
        return {
            "success": False,
            "error": {
                "type": "network_error",
                "message": f"{type(exc).__name__}: {exc}",
            },
            "latency_ms": latency_ms,
        }
