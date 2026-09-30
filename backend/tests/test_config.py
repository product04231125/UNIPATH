from app.core.config import Settings


def test_database_password_special_characters_are_preserved():
    settings = Settings(_env_file=None, postgres_password="synthetic:p@ss/%word", database_url=None)
    assert settings.sqlalchemy_url.password == "synthetic:p@ss/%word"
    assert "synthetic:p@ss" not in repr(settings)
    assert "synthetic:p@ss" not in str(settings.sqlalchemy_url)


def test_database_url_override():
    settings = Settings(
        _env_file=None,
        postgres_password="synthetic",
        database_url="postgresql+psycopg://synthetic:example@db:5432/unipath",
    )
    assert settings.sqlalchemy_url.endswith("@db:5432/unipath")
    assert "synthetic:example" not in repr(settings)
