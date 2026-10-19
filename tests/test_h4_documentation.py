"""Read-only H4 guide integrity/security tests; no MATLAB scenario is executed."""
import importlib.util
import json
from pathlib import Path
import re
import threading
from urllib.request import urlopen, Request
from urllib.error import HTTPError

import pytest

ROOT = Path(__file__).resolve().parents[1]
GUIDE = ROOT / 'docs/lls/h4_100mhz_guide'
spec = importlib.util.spec_from_file_location('h4_guide', GUIDE / 'serve.py')
guide = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guide)


def test_source_atlas_targets_exist():
    text = (GUIDE / 'chapters.js').read_text(encoding='utf-8')
    atlas = text.split('const FILES = {', 1)[1].split('\n};', 1)[0]
    paths = re.findall(r"\w+:'([^']+)'", atlas)
    assert len(paths) >= 65
    missing = [p for p in paths if not (ROOT / p).is_file()]
    assert not missing, missing
    for p in paths:
        assert guide.source_payload(p)['path'] == p


@pytest.mark.parametrize('path', ['../README.md', 'docs/../README.md', '.git/config',
    'logs/run.csv', 'results/test.csv', 'C:/Windows/win.ini', '/etc/passwd',
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
