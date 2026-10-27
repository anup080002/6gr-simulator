function ok=testScheduledSRIProjection()
% Actual scheduler packing and descriptive projection, no RF/received-CRC claim.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_pdcch_shared_queue_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,9);
g=struct('Direction','UL','Frame',1,'Slot',10,'ControlAbsoluteSlot',8, ...
    'RNTI',cfg.phy.pusch.RNTI,'NumLayers',1,'Layers',1, ...
    'PRBSet',cfg.phy.pusch.prbSet,'SymbolAllocation',cfg.phy.pusch.symbolAllocation, ...
    'MCS',cfg.phy.pusch.mcsIndex,'MCSIndex',cfg.phy.pusch.mcsIndex, ...
    'Modulation',cfg.phy.pusch.modulation,'TargetCodeRate',cfg.phy.pusch.codeRate, ...
    'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false));
before=sixgr.truth.projectAcceptedSRSDecisionEvidence(g);
assert(isnan(before.ScheduledSRI)&&isnan(before.ScheduledSRSResourceIndicator));
sch=sixgr.l2.mac.SchedulerPF(cfg,'Direction','UL');
g=sch.attachCanonicalTimingDecision(g);
g=sch.finalizeExactPHYFeasibility(g);
g.DCI=sch.buildDCIBitfield(g);
ctx=sixgr.phy.pdcch.DCIContext(g.DCI.ContextData);
decoded=sixgr.phy.pdcch.DCIParser.parse(g.DCI.Bits,ctx);
assert(~isfield(decoded.Fields,'srs_resource_indicator')&& ...
    decoded.Fields.srs_resource_index0based==0&& ...
    decoded.Fields.srs_resource_selection_source=="implicit_single_configured_resource");
original=g; projected=sixgr.truth.projectAcceptedSRSDecisionEvidence(g);
assert(projected.ScheduledSRI==0&&projected.ScheduledSRSResourceIndicator==0);
assert(isequaln(g,original),'Projection cannot mutate the scheduler owner.');
assert(projected.AcceptedSRSMeasurementID=="",'Packed control cannot invent a received SRS observation.');
explicit=g; explicit.SRI=0; explicit.SRSResourceIndicator=0;
assert(isequaln(projected,sixgr.truth.projectAcceptedSRSDecisionEvidence(explicit)));
conflict=g; conflict.SRI=1; reject(conflict);
conflict=g; conflict.SRSResourceIndicator=1; reject(conflict);
conflict=g; conflict.DCI.ContextDigest="incorrect-original-context"; reject(conflict);
conflict=g; conflict.DCI.PayloadHash="incorrect-original-payload"; reject(conflict);
conflict=g; conflict.RNTI=double(g.RNTI)+1; reject(conflict);
absent=rmfield(g,'DCI'); absent.SRSResourceID=0;
missing=sixgr.truth.projectAcceptedSRSDecisionEvidence(absent);
assert(isnan(missing.ScheduledSRI)&&isnan(missing.ScheduledSRSResourceIndicator), ...
    'A measurement/configured resource ID is not a scheduled selector.');
% Existing explicit scheduler selections remain original owner evidence even
% before packing; no implicit value is filled for the absent sibling alias.
absent.SRI=0; direct=sixgr.truth.projectAcceptedSRSDecisionEvidence(absent);
assert(direct.ScheduledSRI==0&&isnan(direct.ScheduledSRSResourceIndicator));
ok=true;
fprintf('SCHEDULED_SRI_PROJECTION_PASS implicit_zero_original_packed_control=1 RF_executions=0\n');
end
function reject(owner)
try
    sixgr.truth.projectAcceptedSRSDecisionEvidence(owner);
catch cause
    assert(string(cause.identifier)=="sixgr:truth:ScheduledSRIPublicationMismatch", ...
        'Unexpected rejection %s: %s',cause.identifier,cause.message);
    return;
end
error('test:MissingScheduledSRIGuard','Conflicting original control evidence was accepted.');
end
