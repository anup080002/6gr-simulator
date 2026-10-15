function ok=testQCLSchedulingSourceAge()
% Slot-boundary scheduling fixtures, not physical link qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_short.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
fs=122.88e6;
state=struct('CfgMobility',cfg,'CurrentSlot',47,'CurrentServingIdx',1);
policy=cfg.phy.pdsch.qclTCI;
assert(policy.enabled);
reference=struct('UEIndex',1,'ServingCellIndex',1, ...
    'SourceResourceID',policy.source_resource_id, ...
    'ConfigurationEpoch',policy.configuration_epoch, ...
    'SourceSlot0',26,'AvailableAtSample',1720320,'SampleRateHz',fs, ...
    'Source',"received_nzp_csi_rs_trs_timing_estimator");
state.SharedQCLTimingReferences={reference};
assert(sixgr.truth.qclTimingSchedulingEligibility(state,1));
state.CurrentSlot=48;
[usable,status]=sixgr.truth.qclTimingSchedulingEligibility(state,1);
assert(~usable && status=="inactive_or_stale_qcl_timing_reference");
reference.SourceSlot0=46; reference.AvailableAtSample=2949120;
state.SharedQCLTimingReferences={reference};
[usable,status]=sixgr.truth.qclTimingSchedulingEligibility(state,1);
assert(~usable && status=="qcl_timing_reference_not_yet_available");
state.CurrentSlot=49;
assert(sixgr.truth.qclTimingSchedulingEligibility(state,1));
for field=["SourceSlot0","AvailableAtSample","SampleRateHz"]
    for invalid=[NaN Inf -1 .5]
        malformed=reference; malformed.(field)=invalid;
        state.SharedQCLTimingReferences={malformed};
        [usable,status]=sixgr.truth.qclTimingSchedulingEligibility(state,1);
        assert(~usable && status=="invalid_received_qcl_reference");
    end
end
reference.ServingCellIndex=2; state.SharedQCLTimingReferences={reference};
assert(~sixgr.truth.qclTimingSchedulingEligibility(state,1));
state.SharedQCLTimingReferences={};
assert(~sixgr.truth.qclTimingSchedulingEligibility(state,1));
ok=true; fprintf('PASS testQCLSchedulingSourceAge\n');
end
