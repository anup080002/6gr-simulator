# Failed focused batch, preserved without reclassification

Source: clean unchanged 23690b2642c334ef4c174c99079c4b50e9a542a5.
Original bundle: logs/testall_20260914T054618238Z_b599ab86/.
Six tests: four passed, two failed. Both TDD CSI variants passed; FDD cases
failed in the power-export test helper after actual CSI delivery. YAML authority
failed on obsolete RA-slot expectations. See original extended diagnostics in
test_report.json. Detector smoke and mapper/preflight passes do not qualify
physical detection, normal coordinator integration, all measurements or 12 dB.

The adjacent JSON files are exact copies of the terminal run receipts.
