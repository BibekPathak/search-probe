# SearchProbe browser-extraction worker.
#
# A deliberately small Playwright service. Rails' BrowserExtractor only needs:
#   POST /extract  {url, query, engine} -> {success, results|error, ...}
#   GET  /health   -> {"status":"ok"}
#
# Phase 0 ships the HTTP surface; the extraction logic lands with the
# BrowserExtractor work (the "browser extractor" phase). See app.py / extractor.py.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# System deps: curl for healthchecks; Playwright --with-deps pulls browser deps.
RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /srv

COPY requirements.txt ./
RUN pip install -r requirements.txt \
  && playwright install --with-deps chromium \
  && rm -rf /root/.cache

COPY . .

EXPOSE 8001

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8001"]
