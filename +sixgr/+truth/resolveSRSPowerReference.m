function reference=resolveSRSPowerReference(state,cfg,ue,consumerSlot)
% SRS resource-set DL pathloss reference, selected causally, not geometry.
configured=sixgr.phy.refsig.resolveConfiguredPathlossReference(cfg,"SRS");
reference=struct('Usable',false,'Pathloss_dB',NaN,'Source',"", ...
    'ReferenceRS',"",'MeasurementId',"",'ProducerSlot',NaN, ...
    'AvailableSlot',NaN,'ConsumerSlot',double(consumerSlot), ...
    'ReferenceSignalId',NaN,'ConfiguredReference',configured, ...
    'Status',"no_dedicated_srs_pathloss_reference");
if ~configured.Available, return; end
reference.ReferenceRS=configured.ReferenceIdentity;
reference.ReferenceSignalId=configured.ReferenceSignalId;
if configured.SignalType~="SSB"
    reference.Status="srs_csirs_signalled_reference_power_binding_not_implemented";
    return;
end
% Reuse the UE owner: decoded SIB1 power minus UE-filtered SSB RSRP.
% A physical TX-EPRE-minus-RSRP diagnostic is NOT signalled UE knowledge.
if ~isstruct(sixgr.util.structGet(cfg,'lls6g.userContext',[]))
    cfg=sixgr.util.structSet(cfg,'lls6g.userContext',struct());
end
[~,decision]=sixgr.truth.bindSharedSSBPowerReference( ...
    cfg,state,ue,consumerSlot,configured.ReferenceSignalId,"SRS");
reference.Status=string(decision.Status);
reference.MaximumAgeSlots=double(decision.MaximumAgeSlots);
reference.PathlossReferenceLifetime=string(decision.PathlossReferenceLifetime);
reference.ReferenceLifecycleStatus=string(decision.ReferenceLifecycleStatus);
if ~decision.ReferenceUsable, return; end
reference.Pathloss_dB=double(decision.Pathloss_dB);
reference.Source=string(decision.Source);
reference.MeasurementId=string(decision.MeasurementId);
reference.ProducerSlot=double(decision.ProducerSlot);
reference.AvailableSlot=double(decision.AvailableSlot);
reference.SignalledReferencePower_dBm=double(decision.SignalledSSPBCHBlockPower_dBm);
reference.FilteredRSRP_dBm=double(decision.FilteredRSRP_dBm);
reference.SIB1RxTreeHash=string(decision.SIB1RxTreeHash);
assert( ...
    isfinite(reference.Pathloss_dB) && reference.Pathloss_dB>=0 && ...
    ~any(contains(lower(reference.Source), ...
    ["configured_snr","proxy","fallback","synthetic","geometry","oracle"])), ...
    'sixgr:srs:InvalidPathlossReferenceEvidence', ...
    'SRS requires the configured received RS, not modeled propagation or another beam.');
reference.Usable=true;
end
