from __future__ import annotations

from pathlib import Path
from typing import Any

try:
    from pydantic_settings import BaseSettings
    from pydantic_settings import SettingsConfigDict
except Exception:  # pragma: no cover - lets lightweight tooling import config
    SettingsConfigDict = dict  # type: ignore

    class BaseSettings:  # type: ignore[override]
        def __init__(self, **values: Any) -> None:
            for name, value in self.__class__.__dict__.items():
                if name.startswith("_") or name == "model_config" or callable(value) or isinstance(value, property):
                    continue
                setattr(self, name, values.get(name, value))


_REPO_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    DATABASE_URL: str = "mysql+pymysql://root:password@localhost:3306/sixgr_lls"
    REPO_ROOT: str = str(_REPO_ROOT)
    MATLAB_EXE: str = "matlab"
    RESULTS_ROOT: str = str(_REPO_ROOT / "results")
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    FRONTEND_ORIGINS: str = "http://localhost:3000,http://localhost:5173"
    RUN_ANALYSIS_AFTER_RUN: bool = True
    ORACLE_ERROR_ON_VIOLATION: bool = True

    @property
    def repo_root_path(self) -> Path:
        return Path(self.REPO_ROOT).resolve()

    @property
    def results_root_path(self) -> Path:
        return Path(self.RESULTS_ROOT).resolve()

    @property
    def frontend_origins(self) -> list[str]:
        return [x.strip() for x in self.FRONTEND_ORIGINS.split(",") if x.strip()]


settings = Settings()
