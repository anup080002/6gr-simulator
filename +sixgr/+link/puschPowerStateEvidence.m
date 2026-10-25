function row=puschPowerStateEvidence(pc)
% Recorded TX control state; defaults describe missing evidence, not zero TPC.
row=struct();
for name=["StateOwner","StateResetReason","ReceivedAssignmentDigest","TPCSource","AdjustmentMode"]
    row.("PUSCH"+name)=string(sixgr.util.structGet(pc,name,""));
end
for name=["TPCCommandBits","TPCDelta_dB","AppliedTPCDelta_dB","PreviousF_dB", ...
        "UpdatedF_dB","TPCAvailableAtSample","TPCAppliedAtSample", ...
        "TPCMinimumProcessingSamples","StateUpdateCount"]
    row.("PUSCH"+name)=double(sixgr.util.structGet(pc,name,NaN));
end
row.PUSCHTPCAdjustmentHeldAtPowerLimit=double(sixgr.util.structGet( ...
    pc,'TPCAdjustmentHeldAtPowerLimit',NaN));
for name=["P0Nominal_dBm","P0UE_dB","Alpha","DeltaTF_dB","MRB","Mu","BandwidthTerm_dB"]
    raw=sixgr.util.structGet(pc,name,NaN);
    assert(isnumeric(raw)&&isreal(raw)&&isscalar(raw)&&(isfinite(raw)||isnan(raw)), ...
        'sixgr:link:PUSCHPowerOperandEvidence','Retain original scalar power operands; do not cast text or infer missing values.');
    row.("PUSCH"+name)=raw;
end
end
