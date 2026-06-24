from __future__ import annotations

import datetime as _dt

from sqlalchemy import JSON, Boolean, Column, DateTime, Float, Integer, String

from models.database import Base


class Run(Base):
    __tablename__ = "runs"

    id = Column(String(64), primary_key=True)
    run_tag = Column(String(128), index=True)
    scenario_id = Column(String(128), nullable=True)
    scenario_yaml = Column(String(512), nullable=True)
    config_hash = Column(String(64), nullable=True)
    snr_db = Column(Float, nullable=True)
    slot_steps = Column(Integer, nullable=True)
    status = Column(String(32), default="queued", index=True)
    result_ok = Column(Boolean, nullable=True)
    run_start = Column(DateTime, default=_dt.datetime.utcnow)
    run_end = Column(DateTime, nullable=True)
    wall_clock_s = Column(Float, nullable=True)
    dut_blocks = Column(JSON, nullable=True)
    config_json = Column(JSON, nullable=True)
    git_commit = Column(String(40), nullable=True)
    grade_estimate = Column(Float, nullable=True)
    notes = Column(String(512), nullable=True)
    parent_run_id = Column(String(64), nullable=True)

