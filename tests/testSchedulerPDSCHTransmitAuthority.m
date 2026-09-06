function ok = testSchedulerPDSCHTransmitAuthority()
% Coded TDD waveform boundary: gNB scheduling must not wait for a UE decode.
setup6GRSimToolkit('Verbose', false);
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(s, tempname);
grant = sixgr.link.resolveWaveformGrant(cfg, 'DL', 0);
assert(grant.Valid && grant.PHYGrant.IsFrozen && grant.DCI.BitExactPDCCHPayload);
cfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg, double(grant.ScheduledAbsoluteSlot)+1);
% Intentionally no successful PDCCH reception has occurred.
grant.ControlDecodeOk = false;
grant.PDCCHGrantBindingOk = false;
[tx, info] = sixgr.phy.dl.PDSCH_Tx(cfg, 'PHYGrant',grant.PHYGrant, ...
    'SchedulerGrantContext',grant,'CompactOutput',false);
assignment = tx.Assignment;
assert(~isempty(tx.Waveform) && all(isfinite(tx.Waveform(:))) && any(abs(tx.Waveform(:)) > 0));
assert(assignment.Profile == "scheduler_truth" && ...
    assignment.Source == "scheduled_scheduler_grant+authored_dci" && ...
    assignment.get('ControlAuthority') == "transmitter_scheduled_dci" && ...
    ~assignment.get('DCICRCPass') && ~assignment.get('DCIRNTIMatch') && ...
    isnan(assignment.get('DecodedRNTI')) && assignment.get('DecodedDCIId') == "");
assert(assignment.get('ScheduledDCIId') == string(grant.DCI.PayloadHash));
assert(assignment.get('PDCCHAbsoluteSlot') + assignment.get('K0') == ...
    double(grant.ScheduledAbsoluteSlot));
assert(info.CanonicalDelegation);
assert(string(tx.SchedulingOwnership) == "authored_scheduler_dci_transmitter_assignment");
localReject(@() sixgr.phy.dl.PDSCH_Rx(tx.Waveform,cfg, ...
    'PHYGrant',grant.PHYGrant,'SchedulerGrantContext',grant), ...
    'sixgr:pdsch:MissingSchedulerTruthPDCCHBinding');
localReject(@() sixgr.pdsch.PDSCHReceiver(tx.Waveform,assignment,tx.ResourcePlan), ...
    'sixgr:pdsch:PDSCHReceiver:TransmitterAssignmentAtReceiver');

% Only an actual decoded PDCCH can authorize reception. This unit-channel
% codec check makes no RF/noise/fading or complete-scheduler qualification claim.
controlCfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg, ...
    assignment.get('PDCCHAbsoluteSlot')+1);
pdcch = sixgr.link.preparePDCCHTransmission(controlCfg, 'Grant',grant, ...
    'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits));
[controlRX,~] = sixgr.phy.dl.PDCCH_Rx(pdcch.TransmitSamples,controlCfg, ...
    'Carrier',pdcch.Tx.Carrier,'PDCCH',pdcch.Tx.PDCCH, ...
    'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits),'ExpectedDCIBits',grant.DCI.Bits, ...
    'SampleRate_Hz',pdcch.SampleRateHz);
assert(controlRX.Ok && controlRX.CausalGrantDecodeOk);
observed = sixgr.phy.pdcch.decodeDCIPayload(controlRX.DCIBits,grant.DCI.Format,grant.DCI.ContextData);
receivedGrant = grant;
receivedGrant.ControlDecodeOk = logical(controlRX.CausalGrantDecodeOk);
receivedGrant.PDCCHGrantBindingOk = logical(controlRX.CausalGrantDecodeOk && ...
    observed.PayloadHash == string(grant.DCI.PayloadHash));
receivedGrant.PDCCHGrantDCIId = observed.PayloadHash;
receivedGrant.PDCCHGrantDCIFormat = observed.Format;
[rx,~] = sixgr.phy.dl.PDSCH_Rx(tx.Waveform,cfg, ...
    'PHYGrant',grant.PHYGrant,'SchedulerGrantContext',receivedGrant, ...
    'Carrier',tx.Carrier,'PDSCH',tx.PDSCH,'CodingPlan',tx.CodingPlans, ...
    'TransportBlockSize',tx.TransportBlockSize,'TargetCodeRate',tx.TargetCodeRate, ...
    'RV',tx.RV);
assert(all(~rx.CRCError) && isequal(int8(rx.TransportBlock(:)),int8(tx.TransportBlock(:))), ...
    'The actual PDCCH decode must enable bit-exact recovery of the same prepared PDSCH.');

request = assignment.toStruct();
dataSlot = double(grant.ScheduledAbsoluteSlot);
frozenCfg = sixgr.phy.grant.applyPHYGrantToConfig(cfg, grant.PHYGrant);
bind = @(candidate) sixgr.pdsch.bindSchedulerPDSCHTransmitContext( ...
    request,frozenCfg,candidate,dataSlot,grant.PHYGrant);
bad = grant;
bad.DCI = struct('BitExactPDCCHPayload',true);
bad.ControlDecodeOk = true; bad.PDCCHGrantBindingOk = true;
localReject(@()bind(bad),'sixgr:pdsch:MissingAuthoredSchedulerDCI');
bad = grant; bad.DCI.Bits = double(bad.DCI.Bits); bad.DCI.Bits(1) = 0.4;
localReject(@()bind(bad),'sixgr:pdsch:MissingAuthoredSchedulerDCI');
bad = grant; bad.DCI.PayloadHash = 'stale';
localReject(@()bind(bad),'sixgr:pdsch:AuthoredSchedulerDCIPayloadMismatch');
bad = grant; bad.DCI.ContextData.ConfigurationEpoch = bad.DCI.ContextData.ConfigurationEpoch+1;
localReject(@()bind(bad),'sixgr:pdsch:StaleAuthoredSchedulerDCIContext');
bad = grant; bad.HARQ.NDI = ~logical(bad.HARQ.NDI);
localReject(@()bind(bad),'sixgr:pdsch:AuthoredSchedulerDCIAllocationMismatch');
for field = ["PRBSetBWPRelative","SymbolAllocation","MCSIndexPerCodeword","RVPerCodeword"]
    badRequest = request; badRequest.(field)(end) = badRequest.(field)(end)+1;
    localReject(@()sixgr.pdsch.bindSchedulerPDSCHTransmitContext( ...
        badRequest,frozenCfg,grant,dataSlot,grant.PHYGrant), ...
        'sixgr:pdsch:AuthoredSchedulerDCIAllocationMismatch');
end
for field = ["HARQProcess","NDI","RNTI"]
    wrongPHY = grant.PHYGrant;
    wrongPHY.HARQProcessKey.(field) = double(wrongPHY.HARQProcessKey.(field))+1;
    localReject(@()sixgr.pdsch.bindSchedulerPDSCHTransmitContext( ...
        request,frozenCfg,grant,dataSlot,wrongPHY), ...
        'sixgr:pdsch:AuthoredSchedulerDCIAllocationMismatch');
end
bad = grant; bad.ControlAbsoluteSlot = dataSlot+1;
localReject(@()bind(bad),'sixgr:pdsch:SchedulerTimingMismatch');
ok = true;
disp('PASS testSchedulerPDSCHTransmitAuthority: authored DCI and real coded TX; no invented reception.');
end

function localReject(call, identifier)
try
    call();
catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s', ...
        identifier,cause.identifier,cause.message);
    return;
end
error('TEST:MissingRejection','Expected %s.',identifier);
end
