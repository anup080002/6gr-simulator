import csv
import io
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'apps'))
import lls_contract_materializer as m


def render(name, rows):
    path='reports/csv/live_link_adaptation_input_table.csv'
    payload=m._encode_dict_rows(list(rows[0]),rows)
    return m._specialized_chart_materialization(name,{path:dict(artifact_id=1)},lambda _:payload,1)


@pytest.mark.parametrize('name', ['CQI-to-MCS mapping plot','selected MCS distribution',
    'selected vs derived MCS confusion matrix','quality-vs-selected-MCS mismatch plot'])
def test_constant_observations_remain_visible_not_a_fitted_sweep(name):
    rows=[dict(MCSIndex=1,CQIDerivedMCS=0,WidebandCQI=1,PostEqSINR_dB=-10)]*19
    chart=render(name,rows)
    assert b'visual_gate=' not in chart['img_bytes']
    assert chart['source_row_count']==19
    assert chart['img_bytes'].startswith(b'<svg')


def test_mcs_histogram_uses_counts_not_mean_of_ones(monkeypatch):
    captured={}
    def plot(title,subtitle,dataset,summary):
        captured.update(dataset)
        return b'<svg/>'
    monkeypatch.setattr(m,'_render_svg_plot',plot)
    chart=render('selected MCS distribution',[
        dict(MCSIndex=v,CQIDerivedMCS=28) for v in [1,1,1,2,None]])
    assert captured['points']==[[1,3],[2,1]]
    assert captured['sample_count']==4
    rows=list(csv.DictReader(io.StringIO(chart['csv_bytes'].decode())))
    assert [float(row['mcs_index']) for row in rows]==[1,1,1,2]
    assert chart['source_row_count']==4


def test_derived_mcs_cannot_replace_missing_selected_mcs():
    chart=render('selected MCS distribution',[dict(MCSIndex='',CQIDerivedMCS=28)])
    assert chart is None


def test_fractional_selected_mcs_is_not_rounded_into_a_real_index():
    with pytest.raises(ValueError,match='nonnegative integers'):
        render('selected MCS distribution',[dict(MCSIndex=1.5,CQIDerivedMCS=1)])
