"""The deliberately small v2 LinkForge application.

Link storage and click events arrive in later milestones.  This module only
provides the interface that the first ECS service needs: a health check and a
representative redirect.
"""

from fastapi import FastAPI, HTTPException
from fastapi.responses import RedirectResponse

app = FastAPI(title="LinkForge", docs_url=None, redoc_url=None)

# This is intentionally process-local until v4-state introduces DynamoDB.
# Keep the service stateless: every task has the same fixed demonstration data.
LINKS = {
    "docs": "https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html",
    "repo": "https://github.com/SasangaME/linkforge",
}


@app.get("/health")
async def health() -> dict[str, str]:
    """Return the response used by the ALB target-group health check."""
    return {"status": "ok"}


@app.get("/{code}", response_class=RedirectResponse)
async def redirect(code: str) -> RedirectResponse:
    """Redirect a known short code with the product's specified 302 status."""
    destination = LINKS.get(code)
    if destination is None:
        raise HTTPException(status_code=404, detail="link not found")

    return RedirectResponse(url=destination, status_code=302)
