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
end
