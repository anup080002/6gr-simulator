function ok=testPDCCHReceivedClockAlignment()
% Deterministic timing/codec fixture, not a measured acquisition result.
% It checks exactly-once application of a supplied received-clock capsule;
% actual SSB acquisition is covered by the shared-broadcast tests.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,3);
cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeSlotStartTime_s',.002);
bits=int8(mod((0:cfg.phy.pdcch.configuredPayloadBits-1).',2));
p=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',bits,'RNTI',1);
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',p.SampleRateHz,'AvailableAtSample',0, ...
    'DLPhaseOffsetSamples',17,'NCellID',p.Tx.Carrier.NCellID, ...
    'ImplementationFilterDelay_samples',0,'SearchGuardSamples',32);
for phase=[-17 0 17]
    reference.DLPhaseOffsetSamples=phase;
    a=sixgr.phy.frame.pdcchReceivedClockAlignment(reference,p.Tx.Carrier, ...
        p.RuntimeStartSample,p.SampleRateHz,0);
    assert(a.ReceiveStartSample==p.RuntimeStartSample+phase);
    prepared=p; prepared.ReceivedTimingAlignment=a;
    % The input contains the actual generated prefix at the explicitly
    % shifted observation origin. No receiver zero padding or fitted gain.
    x=p.TransmitSamples(1:p.MinimumReceiveSamples,:);
    buffer=sixgr.phy.waveform.WaveformObservationBuffer( ...
        a.ReceiveStartSample,a.ReceiveStartSample+size(x,1),p.SampleRateHz,size(x,2));
    buffer.append(sixgr.phy.waveform.WaveformChunk(x,a.ReceiveStartSample),p.SampleRateHz);
    [rx,info]=sixgr.link.completePDCCHReception(prepared,buffer);
    assert(rx.Ok && isequal(rx.DCIBits,bits) && rx.AppliedTimingCorrection_samples==0);
    assert(rx.RawTimingEstimate_samples==phase && ...
        string(rx.TimingEstimateStatus)=="available_applied_at_observation_origin");
    assert(isequaln(info.ReceivedTimingAlignment,a) && ~info.ReceivePaddingApplied);
    bad=prepared; bad.ReceivedTimingAlignment.ReceiveStartSample=a.ReceiveStartSample+1;
    localReject(@()sixgr.link.completePDCCHReception(bad,buffer),'sixgr:link:PDCCHReceivedClockMismatch');
end
bad=reference; bad.AvailableAtSample=p.RuntimeStartSample+1;
localReject(@()sixgr.phy.frame.pdcchReceivedClockAlignment(bad,p.Tx.Carrier, ...
    p.RuntimeStartSample,p.SampleRateHz,0),'sixgr:phy:frame:FuturePDCCHReceivedClock');
bad=reference; bad.NCellID=reference.NCellID+1;
localReject(@()sixgr.phy.frame.pdcchReceivedClockAlignment(bad,p.Tx.Carrier, ...
    p.RuntimeStartSample,p.SampleRateHz,0),'sixgr:phy:frame:PDCCHReceivedClockMismatch');
bad=reference; bad.Source="configured_true_path_delay";
localReject(@()sixgr.phy.frame.pdcchReceivedClockAlignment(bad,p.Tx.Carrier, ...
    p.RuntimeStartSample,p.SampleRateHz,0),'sixgr:phy:frame:PDCCHReceivedClockMismatch');
ok=true; disp('PDCCH_RECEIVED_CLOCK_ALIGNMENT_PASS');
end

function localReject(call,id)
try, call(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingError','Expected %s.',id);
end
