# Operator NSCID surface and live full-suite failures

Both unchanged full-suite runs reproduced an operator-master failure:
`master_sinr_sweep.yaml` omitted catalog parameter `pdsch.dmrs_nscid`.
A read-only scan of the exact catalog overlays listed by
`loadParameterCatalog.m` found this same sole section-level omission in both
`master_sinr_sweep.yaml` and `master_geometry_based.yaml`.

Both self-contained masters now explicitly select `pdsch.dmrs_nscid: 0`.
The existing contract test still requires every catalog parameter. It now
also checks the built `cfg.phy.pdsch.dmrs.NSCID` against the authored value,
and its existing mutation test selects NSCID 1 to verify propagation.
No catalog rule or assertion was removed. The independent catalog-surface
scan reports no missing parameters after the patch.

The new runtime-worktree batch is running in
`%TEMP%/sixgr_type2_master_guards_20260913.log`:

```matlab
setup6GRSimToolkit('Verbose',false);
runFocusedTests({'testOperatorMasterConfigurationContract', ...
    'test6GParameterCatalog','testConfig','testLLS_DL','testLLS_UL', ...
    'testLLS_ReferencePoints'});
```

At this checkpoint its final result is pending. The full suite and E2E guards
on this new revision remain required; older running tests do not qualify it.

## Other failures discovered, not closed by this patch

Original main full-suite log: `%TEMP%/sixgr_consolidation_full_20260913.log`.
Receiver-revision full-suite log: `%TEMP%/sixgr_receiver_revision_full_20260913.log`.

- `testGeometryMasterRuntimeAuthority`: the assertion that unavailable
  configured TDRA must not be shifted into the TDD partition failed in both
  full-suite runs. Compare the fixture's intended authority with the newly
  supported selection among explicitly configured TDRA rows before changing
  implementation or test inputs; do not simply relax the assertion.
- `testSharedPUSCHLateUCIDelivery` and `testSharedPUSCHLateCSIDelivery` failed
  in the original main run at `buildExecutedDataPrecoderEvidence`: the exported
  matrix does not address the actual physical transmitter columns. Trace the
  executed logical-to-physical port projection and export orientation.

The expected negative `regressionHarnessProbeTest` failures are part of the
passing `testRegressionExecutionAuthority` harness check; they are not extra
simulator failures. The independent Phase-05 evidence quarantine and the
two-bit noise false-ACK reference exceedance remain open as previously recorded.

The config-driven and NR-validation skills guided explicit operator authority
and the retained propagation checks. This checkpoint does not claim a clean
full-suite result or final main-branch integration.
