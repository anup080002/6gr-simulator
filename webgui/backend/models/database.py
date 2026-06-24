from __future__ import annotations

from typing import Optional

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import declarative_base, sessionmaker

from config import settings

Base = declarative_base()
_engine: Optional[Engine] = None
_engine_checked = False
Session = None


def get_engine() -> Optional[Engine]:
    global _engine, _engine_checked, Session
    if _engine_checked:
        return _engine
    _engine_checked = True
    try:
        connect_args = {"connect_timeout": 3} if settings.DATABASE_URL.startswith("mysql") else {}
        engine = create_engine(settings.DATABASE_URL, pool_pre_ping=True, connect_args=connect_args)
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        _engine = engine
        Session = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    except Exception:
        _engine = None
        Session = None
    return _engine


def test_db_connection() -> bool:
    return get_engine() is not None


def create_tables() -> None:
    engine = get_engine()
    if engine is None:
        return
    from models import function_model, profile_model, run_model, trial_models  # noqa: F401

    Base.metadata.create_all(engine)

