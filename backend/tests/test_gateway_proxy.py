import pytest

from scripts.smoke_gateway_proxy import ROOT, fixture_config, server_block


@pytest.mark.parametrize("template", ["unipath-https.conf", "unipath-http.conf"])
def test_gateway_fixture_keeps_staging_limits_for_both_templates(template):
    source = (ROOT / "deploy/gateway" / template).read_text()
    fixture = fixture_config(source)
    assert fixture.count("server {") == 1
    assert "server_name staging-unipath.duckdns.org;" in fixture
    assert "client_max_body_size 2m;" in fixture
    assert "error_page 413 = @staging_payload_too_large;" in fixture
    assert '"code":"HTTP_ERROR"' in fixture
    assert "ssl_certificate" not in fixture
    assert "listen 443" not in fixture
    assert "unipath-product-web" not in fixture


def test_product_gateway_limits_and_upstream_are_preserved():
    source = (ROOT / "deploy/gateway/unipath-https.conf").read_text()
    product = server_block(source, "unipath.duckdns.org")
    assert "client_max_body_size 16k;" in product
    assert "set $unipath_upstream unipath-product-web;" in product
    assert "staging_payload_too_large" not in product
    with pytest.raises(ValueError):
        server_block(source, "missing.example.invalid")
