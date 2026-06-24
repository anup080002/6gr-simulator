from __future__ import annotations

from sqlalchemy import Column, Float, Integer, String, Text

from models.database import Base


class FunctionProfile(Base):
    __tablename__ = "function_profiles"

    id = Column(Integer, primary_key=True, autoincrement=True)
    run_id = Column(String(64), index=True)
    function_name = Column(String(256), index=True)
    stage = Column(String(128), index=True)
    status = Column(String(32), nullable=True)
    elapsed_s = Column(Float, nullable=True)
    estimated_flops = Column(Float, nullable=True)
    estimated_bytes = Column(Float, nullable=True)
    estimate_note = Column(String(256), nullable=True)
    call_utc = Column(String(64), nullable=True)
    metadata_json = Column(Text, nullable=True)

