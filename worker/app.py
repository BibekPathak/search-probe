"""SearchProbe browser-extraction worker (FastAPI + Playwright).

The Rails backend treats this as a dumb remote "browser". Keep the contract
tiny and stable:

    POST /extract
    {
      "url":   "http://backend:3000/simulator/google?q=rust",
      "query": "rust",
      "engine": "google"
    }
    ->
    {
      "success": true,
      "results": [{"position":1,"title":"...","url":"...","snippet":"...","result_type":"organic"}],
      "latency_ms": 812,
      "metadata": {...}
    }

On failure the worker returns a structured error the planner understands,
e.g. {"success":false,"error":{"type":"captcha","message":"..."}}.
"""

from __future__ import annotations

from fastapi import FastAPI
from pydantic import BaseModel, Field

app = FastAPI(title="SearchProbe Browser Worker", version="0.1.0")


class ExtractRequest(BaseModel):
    url: str = Field(min_length=1)
    query: str = Field(default="")
    engine: str = Field(default="google")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/extract")
def extract(payload: ExtractRequest) -> dict:
    # Full Playwright implementation is added in the browser-extractor phase.
    return {
        "success": False,
        "error": {"type": "unknown", "message": "browser extractor not yet initialized"},
    }
