# External PDSCH receiver vector

`expected_pdsch_receiver_external_vectors.csv` is generated outside MATLAB
with the pinned `py3gpp==0.6.0` wheel. It freezes the raw DL-SCH
rate-matched bits, PDSCH scrambling result, 16QAM symbols, DM-RS, complete
resource grid, OFDM waveform, transport block, CRC expectation, and receiver
stage lengths for one deterministic SISO no-noise case.

The case uses A=293, target code rate 0.8, BG1, RV=2, G=800, two PRBs,
200 data RE, 12 type-1 DM-RS RE, and 124 explicitly reserved RE. The
production transmitter is not called when this vector is consumed.

Pinned generation:

```text
python -m pip install --no-deps --target <temporary-target> py3gpp==0.6.0
PYTHONPATH=<temporary-target> python generate_external_pdsch_receiver_fixture.py --output expected_pdsch_receiver_external_vectors.csv
```

The manifest and vector-pack verifier bind the generator, this README, the
py3gpp wheel hash, fixture hash, raw vector lengths, and frozen digests.
