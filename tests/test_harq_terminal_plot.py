import csv
import io
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"apps"))
import lls_contract_materializer as m
from test_harq_terminal_metrics import events


@pytest.mark.parametrize("name", ["residual BLER after HARQ", "residual BLER by HARQ process"])
@pytest.mark.parametrize("terminal", [True, False])
def test_csv_and_visible_plot_preserve_complete_or_censored_tb_population(name, terminal):
    tx, rx = events([False, False], terminal=terminal)
    paths=["harq/csv/harq_transmitter_lifecycle.csv", "harq/csv/harq_process_timeline.csv"]
    payloads=[m._encode_dict_rows(list(rows[0]),rows) for rows in [tx,rx]]
    existing={path:dict(artifact_id=index,logical_path=path) for index,path in enumerate(paths)}
    result=m._specialized_chart_materialization(name,existing,payloads.__getitem__,1)
    assert result["source_table_path"]=="|".join(paths)
    rows=list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert len(rows)==1 and int(rows[0]["TransmittedTBCount"])==1
    assert float(rows[0]["ResidualBLERUpperBound"])==1
    if terminal:
        assert float(rows[0]["ResidualBLER"])==1
    else:
        assert rows[0]["ResidualBLER"] in {"", "nan", "NaN"}
        assert int(rows[0]["RightCensoredTBCount"])==1
    svg=ET.fromstring(result["img_bytes"])
    markers = [node for node in svg.iter() if (node.tag.endswith("circle") and node.get("fill-opacity")=="0.7") or
        (node.tag.endswith("rect") and node.get("fill")=="none" and
         node.get("width")=="6" and node.get("height")=="6")]
    assert len(markers)== (1 if terminal else 2)


def test_attempt_crc_cannot_substitute_for_terminal_lifecycle():
    _, rx=events([False,False])
    path="harq/csv/harq_process_timeline.csv"
    payload=m._encode_dict_rows(list(rx[0]),rx)
    result=m._specialized_chart_materialization("residual BLER after HARQ",
        {path:dict(artifact_id=1,logical_path=path)},lambda _:payload,1)
    assert result["csv_status"]=="unavailable_exact_reason"


def test_probability_axis_cannot_hide_out_of_range_measurement():
    with pytest.raises(ValueError, match="cannot clip"):
        m._render_multi_series_svg("fixture", "", [dict(name="invalid", points=[[0,-.1]])], [],
            x_label="x", y_label="probability", mode="scatter",
            evidence_shape_policy="operating_point", y_bounds=(0,1))


def test_coincident_dl_ul_are_not_shifted_and_have_distinct_markers():
    tx, rx=events([True])
    tx += [dict(tx[0],Direction="UL")]
    rx += [dict(rx[0],Direction="UL")]
    paths=["harq/csv/harq_transmitter_lifecycle.csv", "harq/csv/harq_process_timeline.csv"]
    payloads=[m._encode_dict_rows(list(rows[0]),rows) for rows in [tx,rx]]
    result=m._specialized_chart_materialization("residual BLER after HARQ",
        {p:dict(artifact_id=i,logical_path=p) for i,p in enumerate(paths)},payloads.__getitem__,1)
    svg=ET.fromstring(result["img_bytes"])
    circles=[node for node in svg.iter() if node.tag.endswith("circle") and node.get("fill-opacity")=="0.7"]
    squares=[node for node in svg.iter() if node.tag.endswith("rect") and node.get("width")=="6"]
    assert len(circles)==len(squares)==1
    assert float(circles[0].get("cx"))==float(squares[0].get("x"))+3
    assert float(circles[0].get("cy"))==float(squares[0].get("y"))+3
