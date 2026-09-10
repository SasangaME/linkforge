from fastapi.testclient import TestClient

from linkforge.main import LINKS, app

client = TestClient(app)


def test_health_is_ready_for_the_load_balancer() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_known_code_returns_a_302_redirect() -> None:
    response = client.get("/docs", follow_redirects=False)

    assert response.status_code == 302
    assert response.headers["location"] == LINKS["docs"]


def test_unknown_code_returns_not_found() -> None:
    response = client.get("/missing", follow_redirects=False)

    assert response.status_code == 404
    assert response.json() == {"detail": "link not found"}
