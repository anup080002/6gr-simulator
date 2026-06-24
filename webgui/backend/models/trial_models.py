from __future__ import annotations

from sqlalchemy import Boolean, Column, Float, Integer, String

from models.database import Base


class DLTrial(Base):
    __tablename__ = "dl_pdsch_trials"

    id = Column(Integer, primary_key=True, autoincrement=True)
    run_id = Column(String(64), index=True)
    frame = Column(Integer, nullable=True)
    slot = Column(Integer, nullable=True)
    ue_id = Column(String(64), nullable=True)
    crc_pass = Column(Boolean, nullable=True)
    goodput_mbps = Column(Float, nullable=True)
    post_eq_sinr_db = Column(Float, nullable=True)
    noise_var_source = Column(String(128), nullable=True)
    source_artifact = Column(String(512), nullable=True)


class ULTrial(Base):
    __tablename__ = "ul_pusch_trials"

    id = Column(Integer, primary_key=True, autoincrement=True)
    run_id = Column(String(64), index=True)
    frame = Column(Integer, nullable=True)
    slot = Column(Integer, nullable=True)
    ue_id = Column(String(64), nullable=True)
    crc_pass = Column(Boolean, nullable=True)
    goodput_mbps = Column(Float, nullable=True)
    post_eq_sinr_db = Column(Float, nullable=True)
    noise_var_source = Column(String(128), nullable=True)
    source_artifact = Column(String(512), nullable=True)

