#!/usr/bin/env python3
"""Verify the supplied independent PDSCH/DL-SCH vector pack."""
from __future__ import annotations
import csv, hashlib, json, math, struct, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "independent_vector_manifest.json"

def sha256(path: Path) -> str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1<<20), b''): h.update(b)
    return h.hexdigest()

def row_count(path: Path) -> int:
    with path.open(newline='',encoding='utf-8-sig') as f:
        return sum(1 for _ in csv.DictReader(f))

def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline='', encoding='utf-8-sig') as f:
        return list(csv.DictReader(f))

def verify_external_ldpc(manifest: dict, failures: list[str]) -> None:
    contract = manifest.get('external_ldpc')
    required = {
        'fixture', 'generator', 'generator_sha256', 'readme',
        'readme_sha256', 'implementation', 'version',
        'source_artifact_sha256',
    }
    if not isinstance(contract, dict) or not required <= set(contract):
        failures.append('external_ldpc_manifest_missing_or_incomplete')
        return

    listed = {str(item.get('name', '')) for item in manifest.get('files', [])}
    fixture_name = str(contract['fixture'])
    if fixture_name not in listed:
        failures.append(f'external_ldpc_fixture_not_manifested:{fixture_name}')

    for role, name_key, hash_key in (
        ('generator', 'generator', 'generator_sha256'),
        ('readme', 'readme', 'readme_sha256'),
    ):
        path = ROOT / str(contract[name_key])
        if not path.is_file():
            failures.append(f'missing_external_ldpc_{role}:{path.name}')
        elif sha256(path) != str(contract[hash_key]):
            failures.append(f'external_ldpc_{role}_sha256_mismatch')

    fixture = ROOT / fixture_name
    if not fixture.is_file():
        return
    rows = read_rows(fixture)
    required_columns = {
        'CaseID', 'Implementation', 'Version', 'SourceArtifactSHA256',
        'InputBits', 'InputSHA256', 'ExpectedEncodedSHA256',
        'ExpectedRateMatchedSHA256',
    }
    if not rows or not required_columns <= set(rows[0]):
        failures.append('external_ldpc_fixture_schema_or_rows_invalid')
        return

    seen: set[str] = set()
    for line, row in enumerate(rows, 2):
        case_id = str(row.get('CaseID', '')).strip()
        if not case_id or case_id in seen:
            failures.append(f'external_ldpc_case_id_invalid:line={line}')
        seen.add(case_id)
        if str(row.get('Implementation', '')) != str(contract['implementation']):
            failures.append(f'external_ldpc_implementation_mismatch:line={line}')
        if str(row.get('Version', '')) != str(contract['version']):
            failures.append(f'external_ldpc_version_mismatch:line={line}')
        if str(row.get('SourceArtifactSHA256', '')) != str(
                contract['source_artifact_sha256']):
            failures.append(f'external_ldpc_source_hash_mismatch:line={line}')
        bits = str(row.get('InputBits', '')).strip()
        if not bits or any(bit not in '01' for bit in bits):
            failures.append(f'external_ldpc_input_bits_invalid:line={line}')
        else:
            input_hash = hashlib.sha256(
                bytes(int(bit) for bit in bits)).hexdigest()
            if input_hash != str(row.get('InputSHA256', '')):
                failures.append(f'external_ldpc_input_hash_mismatch:line={line}')
        for field in ('ExpectedEncodedSHA256', 'ExpectedRateMatchedSHA256'):
            value = str(row.get(field, '')).strip().lower()
            if len(value) != 64 or any(c not in '0123456789abcdef' for c in value):
                failures.append(
                    f'external_ldpc_digest_invalid:{field}:line={line}')

def pipe_ints(text: str) -> list[int]:
    tokens = str(text).strip().split('|')
    if tokens == ['']:
        return []
    values = [int(token) for token in tokens]
    if any(str(value) != token.strip() for value, token in zip(values, tokens)):
        raise ValueError('noncanonical integer vector')
    return values

def pipe_floats(text: str) -> list[float]:
    tokens = str(text).strip().split('|')
    if tokens == ['']:
        return []
    values = [float(token) for token in tokens]
    if any(not math.isfinite(value) for value in values):
        raise ValueError('nonfinite numeric vector')
    return values

def digest_int8(values: list[int]) -> str:
    if any(value not in (0, 1) for value in values):
        raise ValueError('bit vector contains a nonbinary value')
    return hashlib.sha256(bytes(values)).hexdigest()

def digest_complex(real: list[float], imag: list[float]) -> str:
    if len(real) != len(imag):
        raise ValueError('complex component lengths differ')
    payload = b''.join(
        struct.pack('<dd', real_value, imag_value)
        for real_value, imag_value in zip(real, imag)
    )
    return hashlib.sha256(payload).hexdigest()

def verify_external_receiver(manifest: dict, failures: list[str]) -> None:
    contract = manifest.get('external_receiver')
    required_contract = {
        'fixture', 'generator', 'generator_sha256', 'readme',
        'readme_sha256', 'implementation', 'version',
        'source_artifact_sha256', 'fixture_schema_version',
    }
    if not isinstance(contract, dict) or not required_contract <= set(contract):
        failures.append('external_receiver_manifest_missing_or_incomplete')
        return

    listed = {str(item.get('name', '')) for item in manifest.get('files', [])}
    fixture_name = str(contract['fixture'])
    if fixture_name not in listed:
        failures.append(
            f'external_receiver_fixture_not_manifested:{fixture_name}'
        )
    for role, name_key, hash_key in (
        ('generator', 'generator', 'generator_sha256'),
        ('readme', 'readme', 'readme_sha256'),
    ):
        path = ROOT / str(contract[name_key])
        if not path.is_file():
            failures.append(f'missing_external_receiver_{role}:{path.name}')
        elif sha256(path) != str(contract[hash_key]):
            failures.append(f'external_receiver_{role}_sha256_mismatch')

    fixture = ROOT / fixture_name
    if not fixture.is_file():
        failures.append(f'missing_external_receiver_fixture:{fixture_name}')
        return
    rows = read_rows(fixture)
    required_columns = {
        'CaseID', 'FixtureSchemaVersion', 'Implementation', 'Version',
        'SourceArtifactSHA256', 'Generator', 'GeneratorSHA256',
        'GenerationCommand', 'NSizeGrid', 'SubcarrierSpacingKHz',
        'Nfft', 'SampleRate', 'CyclicPrefixLengths', 'Modulation',
        'NumLayers', 'TransportBlockSize', 'RateMatchedBitCount',
        'ReservedIndices0Based', 'DataIndices0Based', 'DMRSIndices0Based',
        'TransportBlockBits', 'RawRateMatchedBits', 'ScrambledBits',
        'QAMReal', 'QAMImag', 'DMRSReal', 'DMRSImag', 'GridReal',
        'GridImag', 'WaveformReal', 'WaveformImag',
        'ExpectedTransportBlockSHA256', 'ExpectedRateMatchedSHA256',
        'ExpectedScrambledSHA256', 'ExpectedQAMSHA256',
        'ExpectedDMRSSHA256', 'ExpectedGridSHA256',
        'ExpectedWaveformSHA256', 'ExpectedCRCPass',
        'ExpectedStageNames', 'ExpectedStageElementCounts',
    }
    if len(rows) != 1 or not rows or not required_columns <= set(rows[0]):
        failures.append('external_receiver_fixture_schema_or_rows_invalid')
        return

    row = rows[0]
    if row['FixtureSchemaVersion'] != str(contract['fixture_schema_version']):
        failures.append('external_receiver_schema_version_mismatch')
    if row['Implementation'] != str(contract['implementation']):
        failures.append('external_receiver_implementation_mismatch')
    if row['Version'] != str(contract['version']):
        failures.append('external_receiver_version_mismatch')
    if row['SourceArtifactSHA256'] != str(
            contract['source_artifact_sha256']):
        failures.append('external_receiver_source_hash_mismatch')
    if row['Generator'] != str(contract['generator']):
        failures.append('external_receiver_generator_name_mismatch')
    if row['GeneratorSHA256'] != str(contract['generator_sha256']):
        failures.append('external_receiver_generator_hash_mismatch')
    if not row['GenerationCommand'].strip():
        failures.append('external_receiver_generation_command_missing')

    try:
        tb = pipe_ints(row['TransportBlockBits'])
        rate_matched = pipe_ints(row['RawRateMatchedBits'])
        scrambled = pipe_ints(row['ScrambledBits'])
        reserved = pipe_ints(row['ReservedIndices0Based'])
        data = pipe_ints(row['DataIndices0Based'])
        dmrs_indices = pipe_ints(row['DMRSIndices0Based'])
        cp = pipe_ints(row['CyclicPrefixLengths'])
        stage_counts = pipe_ints(row['ExpectedStageElementCounts'])
        qam_real, qam_imag = (
            pipe_floats(row['QAMReal']), pipe_floats(row['QAMImag'])
        )
        dmrs_real, dmrs_imag = (
            pipe_floats(row['DMRSReal']), pipe_floats(row['DMRSImag'])
        )
        grid_real, grid_imag = (
            pipe_floats(row['GridReal']), pipe_floats(row['GridImag'])
        )
        waveform_real, waveform_imag = (
            pipe_floats(row['WaveformReal']),
            pipe_floats(row['WaveformImag']),
        )
        a = int(row['TransportBlockSize'])
        g = int(row['RateMatchedBitCount'])
        nrb = int(row['NSizeGrid'])
        nfft = int(row['Nfft'])
        sample_rate = int(row['SampleRate'])
        scs_hz = int(row['SubcarrierSpacingKHz']) * 1000
    except (TypeError, ValueError) as exc:
        failures.append(f'external_receiver_parse_failure:{exc}')
        return

    expected_stages = [
        'ofdm_demodulation', 'dmrs_extraction',
        'channel_noise_estimation', 'ptrs_correction',
        'data_extraction', 'equalization', 'layer_demap',
        'soft_demodulation', 'llr_descrambling', 'dlsch_decoding',
    ]
    stage_names = row['ExpectedStageNames'].split('|')
    expected_counts = [
        nrb * 12 * 14, len(dmrs_indices), 1, 0, len(data),
        len(data), len(qam_real), g, g, a,
    ]
    allocation = set(range(nrb * 12 * 14))
    if (
        not row['CaseID'].strip()
        or row['Modulation'] != '16QAM'
        or int(row['NumLayers']) != 1
        or len(tb) != a
        or len(rate_matched) != g
        or len(scrambled) != g
        or len(qam_real) * 4 != g
        or len(dmrs_real) != len(dmrs_indices)
        or len(grid_real) != nrb * 12 * 14
        or len(waveform_real) != sum(nfft + value for value in cp)
        or sample_rate != nfft * scs_hz
        or len(cp) != 14
        or set(reserved) & set(data)
        or set(reserved) & set(dmrs_indices)
        or set(data) & set(dmrs_indices)
        or set(reserved) | set(data) | set(dmrs_indices) != allocation
        or stage_names != expected_stages
        or stage_counts != expected_counts
        or row['ExpectedCRCPass'] != '1'
    ):
        failures.append('external_receiver_shape_or_contract_mismatch')

    digest_checks = {
        'ExpectedTransportBlockSHA256': digest_int8(tb),
        'ExpectedRateMatchedSHA256': digest_int8(rate_matched),
        'ExpectedScrambledSHA256': digest_int8(scrambled),
        'ExpectedQAMSHA256': digest_complex(qam_real, qam_imag),
        'ExpectedDMRSSHA256': digest_complex(dmrs_real, dmrs_imag),
        'ExpectedGridSHA256': digest_complex(grid_real, grid_imag),
        'ExpectedWaveformSHA256':
            digest_complex(waveform_real, waveform_imag),
    }
    for field, actual in digest_checks.items():
        if row[field].lower() != actual:
            failures.append(f'external_receiver_digest_mismatch:{field}')

def verify_integrity_audit(
        manifest: dict, audit: Path, failures: list[str]) -> None:
    if not audit.is_file():
        failures.append('missing:expected_output_integrity_audit.csv')
        return
    if sha256(audit) != manifest.get('integrity_audit_sha256'):
        failures.append('integrity_audit_sha256_mismatch')
        return
    rows = read_rows(audit)
    by_name: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_name.setdefault(str(row.get('FileName', '')), []).append(row)
    for item in manifest.get('files', []):
        name = str(item.get('name', ''))
        matches = by_name.get(name, [])
        if len(matches) != 1:
            failures.append(f'integrity_audit_row_count:{name}:{len(matches)}')
            continue
        row = matches[0]
        path = ROOT / name
        if str(row.get('RowCount', '')) != str(item.get('rows', '')):
            failures.append(f'integrity_audit_rows_mismatch:{name}')
        if str(row.get('SHA256', '')).lower() != str(
                item.get('sha256', '')).lower():
            failures.append(f'integrity_audit_hash_mismatch:{name}')
        if path.is_file() and str(row.get('ByteCount', '')) != str(
                path.stat().st_size):
            failures.append(f'integrity_audit_bytes_mismatch:{name}')
        if str(row.get('Status', '')).upper() != 'PASS':
            failures.append(f'integrity_audit_status_not_pass:{name}')

def main() -> int:
    m=json.loads(MANIFEST.read_text(encoding='utf-8'))
    failures=[]
    gen=ROOT/m['generator']
    if not gen.is_file(): failures.append(f"missing_generator:{gen.name}")
    elif sha256(gen)!=m['generator_sha256']: failures.append('generator_sha256_mismatch')
    for item in m['files']:
        p=ROOT/item['name']
        if not p.is_file():
            failures.append(f"missing:{p.name}"); continue
        if sha256(p)!=item['sha256']: failures.append(f"sha256_mismatch:{p.name}")
        if row_count(p)!=int(item['rows']): failures.append(f"row_count_mismatch:{p.name}")
    verify_external_ldpc(m, failures)
    verify_external_receiver(m, failures)
    audit=ROOT/'expected_output_integrity_audit.csv'
    verify_integrity_audit(m, audit, failures)
    print(f"PDSCH vector-pack verification: {len(m['files'])-sum(x.startswith(('missing:','sha256_mismatch:','row_count_mismatch:')) for x in failures)} files checked, {len(failures)} failures")
    for failure in failures: print('FAIL',failure)
    return 0 if not failures else 2

if __name__=='__main__':
    raise SystemExit(main())
