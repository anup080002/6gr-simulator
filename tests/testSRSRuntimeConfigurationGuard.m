function ok=testSRSRuntimeConfigurationGuard()
% Prove full-band configuration reaches the prepared native waveform, and
% invalid partial-band claims cannot proceed to physical execution.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_short.yaml');
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,5);
args={'SlotIndex',5,'TimingAdvanceSamples',0};
strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
assert(strict.StrictValidation.StrictValid && strict.ToolboxSRS.CSRS==61 && ...
    strict.ToolboxSRS.BSRS==0 && strict.ToolboxSRS.NRBPerTransmission==272 && ...
    strict.ExpectedNumRB==273 && strict.FullCarrierCoverageToleranceRB==1);
out=sixgr.link.runSRSChannelEstimation(cfg,args{:},'PrepareOnly',true);
assert(out.SRSOccupiedPRBCount==272 && out.SRSCarrierPRBCount==273 && ...
    string(out.SRSBandwidthCoverageStatus)=="within_configured_carrier_edge_tolerance" && ...
    ~out.SRSLiteralFullCarrierCoverage && out.SRSCoverageGapRB==1 && ...
    out.PreparedTransmission.Tx.SRS.CSRS==61, ...
    'The advertised span must come from actual generated indices.');
bad=cfg; bad.phy.srs.CSRS=6;
invalid=sixgr.phy.srs.buildSRSConfigFromScenario(bad);
assert(~invalid.StrictValidation.StrictValid && ...
    any(invalid.StrictValidation.FailureReasons== ...
    "full_carrier_sounding_required_but_coverage_incomplete"));
try
    sixgr.link.runSRSChannelEstimation(bad,args{:},'PrepareOnly',true);
    error('test:MissingSRSRuntimeRejection','Invalid SRS was prepared for transmission.');
catch failure
    assert(string(failure.identifier)=="sixgr:link:SRS:InvalidRuntimeConfiguration");
end
% The standalone API retains a failed result instead of throwing; no TX/RX
% capture or fake measured rows may be substituted for the invalid case.
[failed,capture]=sixgr.link.runSRSChannelEstimation(bad,args{:});
assert(~failed.Ok && isempty(fieldnames(capture)) && ...
    isempty(failed.ObservedREAllocationTable) && ...
    string(failed.FailureReason)=="sixgr:link:SRS:InvalidRuntimeConfiguration");
fprintf('SRS_RUNTIME_CONFIGURATION_GUARD_PASS actual_srs_prb=272 requested=273 rejected_legacy_prb=24\n');
ok=true;
end
