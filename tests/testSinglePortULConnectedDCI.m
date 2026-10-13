function ok=testSinglePortULConnectedDCI()
% TS 38.212 7.3.1.1.2: one configured codebook port has zero rank/TPMI bits.
% This tests installed receiver semantics, not a transmitted-layout oracle.
setup6GRSimToolkit('Verbose',false);
legacy=sixgr.phy.pdcch.DCIContext.fromLegacy(struct('NSizeGrid',25),'0_1');
data=legacy.Data;
data.ULPrecoding=struct('num_ports',1,'max_rank',1, ...
    'codebook_subset',"fullyAndPartialAndNonCoherent", ...
    'transmission_scheme',"codebook",'full_power_mode',"not_configured");
policy=sixgr.phy.pdcch.ULPrecodingField.resolve(data);
assert(policy.Width==0 && policy.MaxValue==0 && isequal(policy.RankTPMI,[1 0]));
context=sixgr.phy.pdcch.DCIContext(data);
payload=sixgr.phy.pdcch.buildDCI01UplinkGrant( ...
    struct('NSizeGrid',25,'DCIContext',context),'NumLayers',1,'TPMI',0);
decoded=sixgr.phy.pdcch.DCIParser.parse(payload.Bits,context);
localCheckImplicit(decoded);
for invalid=[2 0;1 1].'
    localReject(@()sixgr.phy.pdcch.ULPrecodingField.encode(data,invalid(1),invalid(2)), ...
        'sixgr:phy:pdcch:InvalidULPrecodingSelection');
end
bad=data; bad.ULPrecoding.max_rank=2;
localReject(@()sixgr.phy.pdcch.ULPrecodingField.resolve(bad), ...
    'sixgr:phy:pdcch:UnsupportedULPrecodingContext');

s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_pdcch_shared_queue_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.pdcch.blindSearch && cfg.phy.ssb.enable && cfg.phy.sib1.enable, ...
    'test:SinglePortReceivedClockConfiguration', ...
    'The one-port shared fixture must configure the physical broadcast path for blind-monitoring timing.');
disabledBroadcast=cfg;
disabledBroadcast.phy.sib1.enable=false;
localReject(@()sixgr.link.runCellSearch_MIB_SIB1(disabledBroadcast, ...
    'PrepareOnly',true,'UseRuntimeChannel',true,'RuntimeSlot',0), ...
    'sixgr:link:InvalidBroadcastPreparationRequest');
contexts=sixgr.truth.validateSharedDCIConfiguration(cfg);
assert(cfg.phy.pusch.NumAntennaPorts==1 && cfg.phy.srs.nPorts==1 && ...
    contexts.UL.Data.ULPrecoding.num_ports==1);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,9);
% A control request is not authorization to execute PUSCH without measured
% SRS. Exercise scheduled packing here; the shared PUSCH test executes SRS.
grant=struct('Direction','UL','Frame',1,'Slot',10,'ControlAbsoluteSlot',8, ...
    'RNTI',cfg.phy.pusch.RNTI,'NumLayers',1,'Layers',1, ...
    'PRBSet',cfg.phy.pusch.prbSet,'SymbolAllocation',cfg.phy.pusch.symbolAllocation, ...
    'MCS',cfg.phy.pusch.mcsIndex,'MCSIndex',cfg.phy.pusch.mcsIndex, ...
    'Modulation',cfg.phy.pusch.modulation,'TargetCodeRate',cfg.phy.pusch.codeRate, ...
    'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false));
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','UL');
grant=scheduler.attachCanonicalTimingDecision(grant);
grant=scheduler.finalizeExactPHYFeasibility(grant);
grant.DCI=scheduler.buildDCIBitfield(grant);
parsed=sixgr.phy.pdcch.DCIParser.parse(grant.DCI.Bits,contexts.UL);
localCheckImplicit(parsed);
assert(parsed.Fields.timing_offset_slots==1 && numel(parsed.Fields.dmrs_port_set)==1);
unexpected=struct();
for fieldName=string(grant.DCI.FieldTable.FieldName).'
    unexpected.(fieldName)=parsed.Fields.(fieldName);
end
unexpected.precoding_information_and_number_of_layers=0;
localReject(@()sixgr.phy.pdcch.DCIPacker.pack(unexpected,contexts.UL), ...
    'sixgr:phy:pdcch:unexpected_field');
localReject(@()sixgr.phy.grant.freezePHYGrant(cfg,'UL',grant, ...
    'Slot',10,'Frame',1,'HARQContext',grant.HARQ),'sixgr:mimo:MissingSRSState');
prepared=sixgr.link.preparePDCCHTransmission(cfg,'Grant',grant, ...
    'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits));
[rx,info]=sixgr.phy.dl.PDCCH_Rx(prepared.TransmitSamples,cfg, ...
    'SampleRate_Hz',prepared.SampleRateHz);
received=sixgr.phy.pdcch.materializeConnectedDCI(rx,info,cfg);
assert(received.NumLayers==1 && received.TPMI==0 && ...
    received.ControlAbsoluteSlot==8 && received.DataAbsoluteSlot==9 && ...
    received.ContextDigest==contexts.UL.Digest);
localCheckImplicit(struct('Fields',received.Fields));
ok=true;
disp('SINGLE_PORT_UL_CONNECTED_DCI_PASS zero_precoding_bits=1 independent_receiver=1');
end

function localCheckImplicit(decoded)
assert(~isfield(decoded.Fields,'precoding_information_and_number_of_layers') && ...
    decoded.Fields.precoding_information_and_number_of_layers_tpmi==0 && ...
    decoded.Fields.precoding_information_and_number_of_layers_rank_minus1==0 && ...
    decoded.Fields.ul_rank_precoding_source=="implicit_single_configured_codebook_port");
end

function localReject(fn,id)
try, fn(); catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s: %s',id,err.identifier,err.message);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
