from __future__ import annotations

from sqlalchemy import Boolean, Column, Integer, String

from models.database import Base


class FunctionRegistry(Base):
    __tablename__ = "function_registry"

    id = Column(Integer, primary_key=True, autoincrement=True)
    run_id = Column(String(64), index=True)
    output_name = Column(String(256), index=True)
    implementation_status = Column(String(64), nullable=True)
    evidence_status = Column(String(64), nullable=True)
    api_exposed_flag = Column(Boolean, default=False)
    ui_rendered_flag = Column(Boolean, default=False)
    writer_enabled = Column(Boolean, default=False)
    blocker_reason = Column(String(512), nullable=True)
    next_implementation_step = Column(String(512), nullable=True)
    source_artifact_ref = Column(String(512), nullable=True)


class KPISummary(Base):
    __tablename__ = "kpi_summaries"

    id = Column(Integer, primary_key=True, autoincrement=True)
    run_id = Column(String(64), index=True)
    metric_name = Column(String(128), index=True)
    metric_value = Column(String(128), nullable=True)
    source_artifact = Column(String(512), nullable=True)

