function ok=testPDCCHScheduledAggregationAuthority()
% Actual same-slot PDCCH REs and independent connected blind decoding.
% Synchronized unit-channel component, not a 0 dB BLER/complete-run claim.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(isequal(cfg.phy.pdcch.searchSpace.numCandidates,[4 2 2 1 0]), ...
    'The actual 5 MHz scenario must monitor two AL4 candidates.');
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,31);
cfg.channel.snr_dB=0;
cfg.phy.pdcch.aggregationLevel=8; % Reproduce the conflicting downstream choice.
formats=["1_1","0_1"]; bits=cell(1,2);
for k=1:2
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,formats(k));
    schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
    fields=struct();
    for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
    fields.mcs=10; fields.ndi=1;
    authored=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
    bits{k}=authored.Bits;
end
rnti=context.Data.RNTIValue;
grant=struct('PDCCHAggregationLevel',4,'DCI',struct('Bits',bits{1}));
[a,ia]=sixgr.phy.dl.PDCCH_Tx(cfg,'Grant',grant, ...
    'RNTI',rnti,'ReservedRECoordinates',zeros(0,2),'OFDMModulate',false);
assert(a.PDCCH.AggregationLevel==4 && numel(a.PDCCHInd)==54*4);
other=grant; other.DCI.Bits=bits{2};
% Reproduce the inherited one-candidate defect without relaxing the PHY:
% unused CCE capacity does not authorize an unconfigured candidate.
oneCandidate=cfg;
oneCandidate.phy.pdcch.searchSpace.configuredNumCandidates=[4 2 1 1 0];
oneCandidate.phy.pdcch.searchSpace.numCandidates=[4 2 1 1 0];
[~,oneAllocation]=sixgr.phy.dl.PDCCH_Tx(oneCandidate,'Grant',grant, ...
    'RNTI',rnti,'ReservedRECoordinates',zeros(0,2),'OFDMModulate',false);
reject(@()sixgr.phy.dl.PDCCH_Tx(oneCandidate,'Grant',other, ...
    'RNTI',rnti,'ReservedRECoordinates',oneAllocation.AllocatedRECoordinates), ...
    'sixgr:phy:pdcch:NoFreeCandidate');
[b,ib]=sixgr.phy.dl.PDCCH_Tx(cfg,'Grant',other, ...
    'RNTI',rnti,'ReservedRECoordinates',ia.AllocatedRECoordinates,'OFDMModulate',false);
assert(b.PDCCH.AggregationLevel==4 && ...
    isempty(intersect(ia.AllocatedRECoordinates,ib.AllocatedRECoordinates,'rows')));
waveform=sixgr.phy.waveform.ofdmModulate(a.Carrier,a.Grid+b.Grid);
[scalar,info]=sixgr.phy.dl.PDCCH_Rx(waveform,cfg,'NoiseVar',1e-12);
assert(info.ReceiverConfiguredMonitoring && ~scalar.Ok && ...
    scalar.AmbiguousValidHypotheses && numel(info.ContextValidHypotheses)==2);
directions=["DL","UL"];
for k=1:2
    [rx,~]=sixgr.link.selectConnectedPDCCHDirection(scalar,info,directions(k));
    assert(rx.Ok && isequal(int8(rx.DCIBits),int8(bits{k})) && ...
        rx.CandidateAggregationLevel==4);
end
% No blanket AL4 policy: every scheduled level owns its actual resources,
% independent of configured SNR. A genuine AL8 occupies the whole CORESET.
for snr=[-30 40]
    changed=cfg; changed.channel.snr_dB=snr;
    for level=[1 2 4 8]
        scheduled=grant; scheduled.PDCCHAggregationLevel=level;
        [tx,allocation]=sixgr.phy.dl.PDCCH_Tx(changed,'Grant',scheduled, ...
            'RNTI',rnti,'ReservedRECoordinates',zeros(0,2),'OFDMModulate',false);
        assert(tx.PDCCH.AggregationLevel==level && numel(tx.PDCCHInd)==54*level);
        if level==8
            reject(@()sixgr.phy.dl.PDCCH_Tx(changed,'Grant',other, ...
                'RNTI',rnti,'ReservedRECoordinates',allocation.AllocatedRECoordinates), ...
                'sixgr:phy:pdcch:NoFreeCandidate');
        end
    end
end
[unknownAL,unknownEvidence]=sixgr.phy.pdcch.selectAggregationLevelFromQuality(cfg,NaN);
[outageAL,outageEvidence]=sixgr.phy.pdcch.selectAggregationLevelFromQuality( ...
    cfg,NaN,'ReceivedCQI',0);
[highAL,highEvidence]=sixgr.phy.pdcch.selectAggregationLevelFromQuality(cfg,20);
assert(unknownAL==8 && outageAL==8 && highAL==1 && ...
    string(unknownEvidence.QualitySource)=="missing_control_quality_most_robust" && ...
    string(outageEvidence.QualitySource)=="received_cqi_zero_outage_most_robust" && ...
    string(highEvidence.QualitySource)=="measured_control_sinr", ...
    'PDCCH aggregation must fail robustly without using configured SNR as an oracle.');
for value={NaN,3,0,[],[4 8]}
    bad=grant; bad.PDCCHAggregationLevel=value{1};
    reject(@()sixgr.phy.pdcch.resolveScheduledAggregationLevel(cfg,bad), ...
        'sixgr:phy:pdcch:InvalidScheduledAggregationLevel');
end
bad=grant; bad.PDCCHAggregationLevel=16;
reject(@()sixgr.phy.pdcch.resolveScheduledAggregationLevel(cfg,bad), ...
    'sixgr:phy:pdcch:UnmonitoredScheduledAggregationLevel');
forced=a.PDCCH; forced.AggregationLevel=8;
reject(@()sixgr.phy.dl.PDCCH_Tx(cfg,'Grant',grant,'RNTI',rnti,'PDCCH',forced), ...
    'sixgr:phy:pdcch:ScheduledAggregationMismatch');
fprintf(['PDCCH_SCHEDULED_AGGREGATION_AUTHORITY_PASS two_AL4_same_slot=1 ' ...
    'connected_blind_DL_UL_decoded=1 scheduled_AL8_exhaustion_retained=1\n']);
ok=true;
end

function reject(action,id)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s',id,cause.identifier);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
