"""Independent feedback denominator checks; CRC alone is not a feedback bit."""
import csv
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import lls_csv_semantics as audit


def evidence():
    rows=[]
    for index, token in enumerate(["ACK", "NACK", "DTX"], 1):
        rows.append(dict(FeedbackForDirection="DL", FeedbackOutcome=token,
            ObservedAck=int(token=="ACK"), ReceiverUsable=int(token!="DTX"),
            ReceiverVectorLengthMatches=int(token!="DTX"), ObservationID=f"obs{index}",
            SweepPointIndex=1, RNTI=1, BitIndex=1, ObservationStartSample=0,
            ObservationEndSampleExclusive=100, AvailableAtSample=100))
    summary=dict(Direction="DL", NumeratorValue=1, DenominatorValue=2, Value=.5,
        FeedbackObservedCount=3, FeedbackDTXCount=1, SourceRowCount=3,
        EligibleRowCount=2, ExcludedRowCount=1)
    return summary,rows


def test_received_populations_not_decoder_crc():
    summary, rows=evidence()
    assert not audit._received_harq_kpi_failures(summary, rows)
    for row in rows:
        row["CombinedDecodeOK"]=0
    assert not audit._received_harq_kpi_failures(summary, rows)
    assert audit._received_harq_kpi_failures(summary,[dict(Direction="DL",CombinedDecodeOK=1)])


@pytest.mark.parametrize("field", ["NumeratorValue","DenominatorValue","FeedbackObservedCount",
    "FeedbackDTXCount","SourceRowCount","EligibleRowCount","ExcludedRowCount","Value"])
def test_tampered_export_counters_rejected(field):
    summary,rows=evidence(); summary[field]=99
    assert audit._received_harq_kpi_failures(summary,rows)


@pytest.mark.parametrize("field,value", [("ObservedAck",0),("ReceiverUsable",0),
    ("ReceiverVectorLengthMatches",0),("ProxyUsed",1),("AvailableAtSample",99),
    ("AvailableAtSample",100.5),("BitIndex",0),("ObservationID",""),
    ("FeedbackForDirection","UNKNOWN"),("FeedbackOutcome","BAD")])
def test_invalid_receiver_evidence_rejected(field,value):
    summary,rows=evidence(); rows[0][field]=value
    assert audit._received_harq_kpi_failures(summary,rows)


def test_duplicate_received_bit_rejected():
    summary,rows=evidence(); rows.append(dict(rows[0]))
    assert "duplicate_received_feedback_bit" in audit._received_harq_kpi_failures(summary,rows)


def test_all_dtx_has_no_nack_rate():
    summary,rows=evidence(); rows=rows[2:]
    summary.update(NumeratorValue=0,DenominatorValue=0,Value="NaN",
        SourceRowCount=1,FeedbackObservedCount=1,EligibleRowCount=0,ExcludedRowCount=1)
    assert not audit._received_harq_kpi_failures(summary,rows)
    summary["Value"]=0
    assert audit._received_harq_kpi_failures(summary,rows)


def test_peer_direction_cannot_change_denominator():
    summary,rows=evidence(); peer=dict(rows[0],FeedbackForDirection="UL")
    assert not audit._received_harq_kpi_failures(summary,rows+[peer])


def test_received_ledger_is_wired_to_manifest_and_reconstruction(tmp_path):
    def write(path, rows):
        target=tmp_path/path; target.parent.mkdir(parents=True,exist_ok=True)
        fields=list(dict.fromkeys(key for row in rows for key in row))
        with target.open("w",newline="",encoding="utf-8") as stream:
            writer=csv.DictWriter(stream,fieldnames=fields)
            writer.writeheader(); writer.writerows(rows)
    summary,rows=evidence()
    rows.append(dict(rows[0],FeedbackForDirection="UL"))
    path="control/csv/gnb_harq_feedback_observations.csv"
    write(path,rows)
    manifest=[]
    for direction in ["UL","DL","PacketSDU","ApplicationPackets","HARQTimeline",
                      "ULGrants","DLGrants","SlotTrace","HARQFeedback"]:
        present=direction=="HARQFeedback"
        manifest.append(dict(RunId="fixture",ScenarioName="fixture",Direction=direction,
            SourceTablePath=path if present else f"absent/{direction}.csv",
            SourceTableName="received_harq_feedback_observations" if present else direction,
            Layer="HARQ",RequiredForObjective=int(present),Exists=int(present),
            RowCount=4 if present else 0,ColumnCount=len(rows[0]) if present else 0,
            FileHash="a"*64 if present else "empty",SchemaHash="fixture",ProducerModule="fixture",
            Status="pass" if present else "not_applicable",FailureReason="" if present else "disabled",
            DLSubsetRowCount=3 if present else 0,ULSubsetRowCount=1 if present else 0,
            DLSubsetRowsHash="b"*64 if present else "empty",ULSubsetRowsHash="c"*64 if present else "empty"))
    write("reports/csv/kpi_source_table_manifest.csv",manifest)
    write("reports/csv/kpi_formula_registry.csv",[dict(KPIName="DL_HARQ_NACK_Rate",Direction="DL",
        Layer="HARQ",Units="ratio",RequiredSourceTables="received_harq_feedback_observations",
        Tolerance=1e-9,StrictAllowed=1,FormulaVersion="v1",FormulaEquation="NACK/(ACK+NACK)",
        ProducerModule="fixture",Status="active")])
    summary.update(KPIName="DL_HARQ_NACK_Rate",FormulaId="DL_HARQ_NACK_Rate",FormulaVersion="v1",
        SourceTablePaths=path,SourceRowsHash="b"*64,MissingRawData=0,SchemaValid=1,
        Applicable=1,ApplicabilityReason="harq_enabled",FormulaExecuted=1,ReconstructionValue=.5,
        ReconciliationTolerance=1e-9,ReconciliationPass=1,StrictOk=1,Status="pass",FailureReason="")
    write("reports/csv/kpi_reconstruction_summary.csv",[summary])
    def checks():
        return [item for item in audit._audit_kpi_reporting_tables(tmp_path) if item.artifact_path in {
            "reports/csv/kpi_source_table_manifest.csv","reports/csv/kpi_reconstruction_summary.csv"}]
    assert all(check.passed for check in checks()), [check.details for check in checks()]
    summary["DenominatorValue"]=19  # data attempts are not decoded feedback decisions
    write("reports/csv/kpi_reconstruction_summary.csv",[summary])
    assert any("DenominatorValue_not_received_feedback_population" in check.details for check in checks())
