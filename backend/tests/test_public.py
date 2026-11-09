import pytest


@pytest.mark.django_db
def test_privacy_page_is_public(client):
    r = client.get("/privacy")
    assert r.status_code == 200
    assert "Политика конфиденциальности" in r.content.decode()


def test_aasa_hidden_without_team_id(client, settings):
    settings.APPLE_TEAM_ID = ""
    assert client.get("/.well-known/apple-app-site-association").status_code == 404


def test_aasa_lists_challenge_links(client, settings):
    settings.APPLE_TEAM_ID = "ABCDE12345"
    data = client.get("/.well-known/apple-app-site-association").json()
    detail = data["applinks"]["details"][0]
    assert detail["appIDs"] == ["ABCDE12345.kg.speakcheck.app"]
    assert detail["components"] == [{"/": "/c/*"}]
