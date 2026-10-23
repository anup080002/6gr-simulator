"""Read-only H4 guide integrity/security tests; no MATLAB scenario is executed."""
import importlib.util
import json
from pathlib import Path
import re
import threading
import csv
import hashlib
from urllib.request import urlopen, Request
from urllib.error import HTTPError

import pytest

ROOT = Path(__file__).resolve().parents[1]
GUIDE = ROOT / 'docs/lls/h4_100mhz_guide'
spec = importlib.util.spec_from_file_location('h4_guide', GUIDE / 'serve.py')
guide = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guide)
inventory_spec = importlib.util.spec_from_file_location('h4_evidence_inventory', GUIDE / 'buildEvidenceGuide.py')
inventory = importlib.util.module_from_spec(inventory_spec)
inventory_spec.loader.exec_module(inventory)


def test_evidence_inventory_matches_installed_declarations_without_importing_dashboard():
    with (GUIDE / 'evidence-catalog.csv').open(encoding='utf-8', newline='') as stream:
        retained = list(csv.DictReader(stream))
    expected = inventory.installed_entries()
    actual = [r for r in retained if r['kind'] not in ('inventory', 'observed_file')]
    assert actual == expected
    meta = json.loads(retained[0]['details_json'])
    assert meta['scope'] == 'documentation_inventory_not_measurement_or_acceptance'
    for path, digest in meta['source_sha256'].items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, path
    assert len([r for r in retained if r['kind'] == 'dashboard_panel']) >= 35
    assert len([r for r in retained if r['kind'] == 'live_chart']) >= 35
    assert len({(r['kind'], r['id']) for r in retained}) == len(retained)
    # Generated docs are served as read-only source, not a new results API.
    assert guide.source_payload('docs/lls/h4_100mhz_guide/evidence-catalog.csv')['text']


def test_bounded_inventory_does_not_count_wide_header_as_measurements(tmp_path):
    sample = tmp_path / 'wide.csv'
    header = ['column_' + str(k) for k in range(1000)]
    with sample.open('w', newline='', encoding='utf-8') as stream:
        csv.writer(stream).writerow(header)
    fields, metadata = inventory.inspect_header(sample)
    assert fields == header
    assert sample.stat().st_size > 2303
    assert metadata['first_record_seen'] is False
    assert metadata['first_record_matches_header_width'] is False
    with sample.open('a', newline='', encoding='utf-8') as stream:
        csv.writer(stream).writerow(['one, "quoted"\nvalue'] + [''] * 999)
    _, metadata = inventory.inspect_header(sample)
    assert metadata['first_record_seen'] and metadata['first_record_matches_header_width']
    assert 'not audited' in metadata['inspection']


def test_documentation_literal_reader_never_executes_code():
    import ast
    with pytest.raises(ValueError):
        inventory.literals(ast.parse("__import__('os').system('anything')", mode='eval').body, {})
    with pytest.raises(ValueError):
        inventory.literals(ast.parse("x.__class__", mode='eval').body, {})


def test_observed_file_inventory_contains_no_measurement_payload(tmp_path):
    (tmp_path / 'trial.csv').write_text('Slot,SecretPayload\n1,do-not-copy-this\n')
    (tmp_path / 'plot.png').write_bytes(b'not-even-a-valid-image')
    entries = inventory.observed_entries(tmp_path)
    assert len(entries) == 2
    assert 'do-not-copy-this' not in json.dumps(entries)
    png = next(r for r in entries if r['id'] == 'plot.png')
    assert 'no pixel or lineage audit' in json.loads(png['details_json'])['inspection']


def test_source_atlas_targets_exist():
    text = (GUIDE / 'chapters.js').read_text(encoding='utf-8')
    atlas = text.split('const FILES = {', 1)[1].split('\n};', 1)[0]
    paths = re.findall(r"\w+:'([^']+)'", atlas)
    assert len(paths) >= 65
    missing = [p for p in paths if not (ROOT / p).is_file()]
    assert not missing, missing
    for p in paths:
        assert guide.source_payload(p)['path'] == p


def test_algorithm_source_owners_exist_and_are_allowlisted():
    text = (GUIDE / 'chapters.js').read_text(encoding='utf-8')
    atlas = text.split('Object.assign(FILES,{', 1)[1].split('\n});', 1)[0]
    paths = re.findall(r"\w+:'([^']+)'", atlas)
    assert len(paths) >= 25
    for path in paths:
        assert (ROOT / path).is_file()
        if path.startswith('apps/'):
            # App-source links explicitly open committed GitHub main.
            with pytest.raises(ValueError):
                guide.source_payload(path)
        else:
            assert guide.source_payload(path)['path'] == path


def test_algorithm_script_loaded_before_navigation():
    html = (GUIDE / 'index.html').read_text(encoding='utf-8')
    assert html.index('chapters.js') < html.index('guide.js')
    text = (GUIDE / 'chapters.js').read_text(encoding='utf-8')
    assert text.index('window.H4Guide=') < text.index('G.initMethodChapter=')


def test_absolute_power_definitions_keep_normative_and_unqualified_scopes_separate():
    text = (GUIDE / 'chapters.js').read_text(encoding='utf-8')
    chapter = text.split("CHAPTERS.push({id:'absolute-power-n40'", 1)[1]
    for phrase in ('Complex samples in sqrt(mW)', 'not a universal NR BS power',
                   'PH_Type1   = PCMAX - Prequested',
                   'SRS has its own resource-set reference',
                   'There is no PUSCH DeltaTF term',
                   'Remaining integrated power-control gap'):
        assert phrase in chapter, phrase
    for path in re.findall(r"S\('([^']+)'\)", chapter):
        assert (ROOT / path).is_file(), path
        assert guide.source_payload(path)['path'] == path
    with (ROOT / 'docs/lls/h4_100mhz_20261015_issue_status.csv').open(
            encoding='utf-8-sig', newline='') as stream:
        rows = list(csv.DictReader(stream))
    for issue_id in ('N40-PWR-01', 'N40-PWR-02', 'N40-PWR-03'):
        matches = [row for row in rows if row['ID'] == issue_id]
        assert len(matches) == 1 and None not in matches[0]
        for path in matches[0]['Production files'].split(';'):
            assert (ROOT / path.strip()).is_file(), path
    assert 'CONFIRMED GAP' in next(row for row in rows if row['ID'] == 'N40-PWR-03')['Current status']


def test_detailed_guide_is_read_only_not_a_simulation_launcher():
    text = (GUIDE / 'chapters.js').read_text(encoding='utf-8')
    assert 'G.teachingMath=' in text
    assert 'not a mandated 3GPP formula' in text
    assert 'diagnostic, not frozen-source primary qualification' in text
    assert "fetch(" not in text
    assert 'XMLHttpRequest' not in text
    assert 'localStorage' not in text


def test_resource_efficiency_backlog_is_open_and_has_real_production_owners():
    with (ROOT / 'docs/lls/h4_100mhz_20261015_issue_status.csv').open(
            encoding='utf-8-sig', newline='') as stream:
        rows = list(csv.DictReader(stream))
    text = (GUIDE / 'chapters.js').read_text(encoding='utf-8')
    for issue_id in ('H4-196', 'H4-197', 'H4-198'):
        matches = [row for row in rows if row['ID'] == issue_id]
        assert len(matches) == 1, issue_id
        row = matches[0]
        assert None not in row and len(row) == 8, row
        assert row['Current status'].startswith('OPEN deferred at user request')
        assert row['Remaining acceptance']
        for path in row['Production files'].split(';'):
            assert (ROOT / path.strip()).is_file(), path
        assert issue_id in text
    # Legal configuration choices must not be presented as mandatory violations
    # or as already implemented gains in the running waveform experiment.
    assert 'not mandatory 3GPP symbol exclusions' in text
    assert 'No specific mandatory-procedure violation was established' in text
    assert 'not 5,400 proven recoverable data REs or measured throughput' in text
    assert 'This documentation changes no active YAML, MATLAB code' in text
    assert 'G.resourceEfficiencyFixes=fixes' in text


@pytest.mark.parametrize('path', ['../README.md', 'docs/../README.md', '.git/config',
    'logs/run.csv', 'results/test.csv', 'C:/Windows/win.ini', '/etc/passwd',
    'scripts/run_focused_lls_repairs.m',
    'docs/lls/h4_100mhz_guide/serve.py:stream', 'docs/lls/h4_100mhz_guide/reference.json'])
def test_source_allow_list(path):
    with pytest.raises((ValueError, FileNotFoundError)):
        guide.source_path(path)


def test_snapshot_identity_and_native_ofdm_metadata():
    d = guide.reference_payload()
    assert d['available'] and d['snapshot_matches_yaml']
    assert d['scope'] == 'configuration_snapshot_not_simulation_result'
    assert d['ofdm']['Nfft'] == 4096
    assert d['ofdm']['SampleRate'] == 122880000
    assert sum(d['ofdm']['SymbolLengths'][:14]) == 61440
    assert len(d['ofdm']['CyclicPrefixLengths']) == 28


@pytest.mark.parametrize('kind', ['scenario', 'matrix'])
def test_catalog_has_loader_provenance(kind):
    d = guide.catalog_payload(kind)
    assert d['snapshot_matches_sources']
    assert d['catalog']['sections']
    assert any(p['path'].endswith('loadParameterCatalog.m') for p in d['metadata']['sources'])
    assert d['metadata']['scope'].endswith('not_runtime_qualification')


def test_yaml_inventory_is_complete_not_an_acceptance_receipt():
    d = guide.scenario_payload()
    expected = {p.relative_to(ROOT).as_posix() for p in (ROOT/'simulator/configs').rglob('*')
                if p.is_file() and p.suffix.lower() in {'.yaml', '.yml'}}
    assert {r['path'] for r in d['entries']} == expected
    assert all(r['acceptance'] == 'not_assessed_by_this_inventory' for r in d['entries'])
    json.dumps(d)  # catches non-JSON-safe YAML metadata, without changing evidence


def test_native_catalog_is_exact_current_source_not_resolved_sls():
    d = guide.catalog_payload('core')
    path = ROOT / 'simulator/configs/schema/core_parameter_catalog.yaml'
    assert d['catalog'] == guide.yaml.safe_load(path.read_bytes())
    assert d['read_mode'] == 'live_source_not_resolved_config'
    assert d['metadata']['scope'].endswith('not_runtime_qualification')
    assert d['catalog']['parameters']['scenario']['layout']['nSites']['value_type'] == 'integer'
    for item in d['metadata']['sources']:
        assert guide.hashlib.sha256((ROOT / item['path']).read_bytes()).hexdigest() == item['sha256']


def test_curated_scenario_examples_exist():
    text = (GUIDE / 'chapters.js').read_text(encoding='utf-8')
    names = re.findall(r"Y\('([^']+\.yaml)'", text)
    assert len(names) >= 25
    for name in names:
        assert (ROOT / 'simulator/configs/scenarios' / name).is_file(), name


def test_decision_map_paths_exist_in_installed_catalog():
    """Do not teach plausible but nonexistent configuration keys."""
    text = (GUIDE / 'chapters.js').read_text(encoding='utf-8')
    paths = set(re.findall(r"P\('([^']+)'", text))
    cat = guide.catalog_payload('scenario')['catalog']
    assert len(paths) >= 65
    for path in paths:
        section, _, key = path.partition('.')
        assert section in cat['sections'], path
        if key:
            assert key in cat['sections'][section]['parameters'], path


def test_loopback_http_routes_and_no_launch_api():
    server = guide.ThreadingHTTPServer(('127.0.0.1', 0), guide.Handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    base = f'http://127.0.0.1:{server.server_port}'
    try:
        for path in ['/', '/guide.js', '/chapters.js', '/api/reference',
                     '/api/catalog?kind=matrix', '/api/catalog?kind=core', '/api/scenarios',
                     '/api/source?path=run_sixgr.m', '/api/source?path=run_6g_phy_lls_matrix.m']:
            with urlopen(base+path) as response:
                assert response.status == 200
                assert "default-src 'self'" in response.headers['Content-Security-Policy']
        with pytest.raises(HTTPError) as error:
            urlopen(Request(base+'/', headers={'Host':'example.com'}))
        assert error.value.code == 403
        with pytest.raises(HTTPError) as error:
            urlopen(Request(base+'/api/run', data=b'{}', method='POST'))
        assert error.value.code == 501
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=3)
