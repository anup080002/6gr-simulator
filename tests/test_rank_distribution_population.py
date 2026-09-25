import csv
import io
import sys
from pathlib import Path
import pytest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'apps'))
import lls_contract_materializer as m

def render(tables):
    existing={}; payloads={}
    for index,(path,rows) in enumerate(tables.items(),1):
        existing[path]=dict(artifact_id=index)
        columns=list(dict.fromkeys(k for row in rows for k in row))
        payloads[index]=m._encode_dict_rows(columns,rows)
    return m._beam_mimo_chart_materialization('rank distribution',existing,payloads.__getitem__,1)

def test_only_primary_executions_count_and_reported_ri_is_not_layers(monkeypatch):
    captured={}
    def plot(title,subtitle,data,summary):
        captured.update(data); return b'<svg/>'
    monkeypatch.setattr(m,'_render_svg_plot',plot)
    rows=[dict(Direction='DL',Layers=2,RankIndicator=1,SweepPointIndex=1,ConfiguredSNR_dB=-10)]*16
    rows+= [dict(Direction='DL',Layers=1,RankIndicator=2,SweepPointIndex=1,ConfiguredSNR_dB=-10)]*3
    tables={path:rows for path in ['air_interface/csv/dl_pdsch_trials.csv',
        'beamforming/csv/beam_precoder_table.csv','beamforming/csv/probe_beam_mimo.csv']}
    tables['air_interface/csv/csi_rs_trials.csv']=[dict(RankIndicator=4)]*20
    chart=render(tables)
    exported=list(csv.DictReader(io.StringIO(chart['csv_bytes'].decode())))
    assert [(int(r['rank']),int(r['count'])) for r in exported]==[(1,3),(2,16)]
    assert chart['source_row_count']==captured['sample_count']==19
    assert chart['source_table_path']=='air_interface/csv/dl_pdsch_trials.csv'

def test_direction_and_sweep_are_separate_in_one_csv():
    chart=render({
        'air_interface/csv/dl_pdsch_trials.csv':[dict(Direction='DL',Layers=1,SweepPointIndex=p,ConfiguredSNR_dB=s)
            for p,s in [(1,-10),(2,20)]],
        'air_interface/csv/ul_pusch_trials.csv':[dict(Direction='UL',Layers=2,SweepPointIndex=2,ConfiguredSNR_dB=20)]})
    rows=list(csv.DictReader(io.StringIO(chart['csv_bytes'].decode())))
    assert len(rows)==3 and sum(int(r['count']) for r in rows)==3
    assert {r['direction'] for r in rows}=={'DL','UL'}
    assert {float(r['configured_snr_db']) for r in rows}=={-10,20}

@pytest.mark.parametrize('row',[dict(Direction='DL',RankIndicator=2),dict(Layers=1.5),dict(Layers=0),
    dict(Direction='UL',Layers=1),dict(Layers=2,TBSInputNumLayers=1)])
def test_no_reported_or_inconsistent_rank_substitution(row):
    with pytest.raises(ValueError,match='Rank histogram'):
        render({'air_interface/csv/dl_pdsch_trials.csv':[row]})

def test_one_rank_is_a_valid_distribution_and_proxies_do_not_count():
    chart=render({'air_interface/csv/dl_pdsch_trials.csv':[
        dict(Layers=1,ProxyUsed=0),dict(Layers=2,ProxyUsed=1)]})
    assert chart['source_row_count']==1
    assert b'visual_gate=' not in chart['img_bytes']
    assert render({'beamforming/csv/probe_beam_mimo.csv':[dict(Layers=4)]}) is None
