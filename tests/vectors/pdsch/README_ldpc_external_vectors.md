# External LDPC parity fixtures

`expected_pdsch_ldpc_external_vectors.csv` was generated independently of
MATLAB and this repository with `py3gpp` 0.6.0 using its `sionna` encoder
algorithm. The pinned wheel is:

- source: `https://pypi.org/project/py3gpp/0.6.0/`
- wheel: `py3gpp-0.6.0-py3-none-any.whl`
- SHA-256: `1182b03eed6aa44e1af49df827d2712206189a620fd85985e7b795bef11c9aa9`

Generation command:

```text
python -m pip install --target <isolated-dir> py3gpp==0.6.0
python generate_external_ldpc_fixture.py
```

For each row, the generator:

1. creates the recorded `InputBits`;
2. calls `py3gpp.nrDLSCHInfo(A,R)`;
3. calls `py3gpp.nrCRCEncode`;
4. calls `py3gpp.nrCodeBlockSegmentLDPC`;
5. calls `py3gpp.nrLDPCEncode(...,algo="sionna")`;
6. calls `py3gpp.nrRateMatchLDPC`;
7. hashes each signed `int8` array in column-major order.

The two fixtures independently cover BG1/Zc=15 and BG2/Zc=104, include
filler bits, and freeze both encoded mother-code and rate-matched digests.
