function ok=testBidirectionalULResourcePlan()
% Legal configured PUSCH/SRS/PUCCH ownership, not an end-to-end run pass.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/validation/lls_bidirectional_disjoint_ul.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(string(cfg.phy.pdcch.jointAdmissionPolicy)=="ul_preschedule_first", ...
    'The connected two-UE fixture must not bypass joint control admission.');
sixgr.truth.validateCoupledNoisePowerAuthority(cfg);
assert(sixgr.rf.isNormalizedFixedSNRPowerReference(cfg), ...
    'The standalone fixed-SNR fixture must use normalized TX power and matching receiver noise.');
contexts=sixgr.truth.validateSharedDCIConfiguration(cfg);
assert(isequal(double(cfg.phy.pusch.SymbolAllocation),[0 11]));
assert(any(all(contexts.UL.Data.ULTimeDomainAllocations(:,2:3)==[0 11],2)));
assert(sixgr.phy.pdcch.DCIContextFactory.supportsSymbolAllocation(cfg,'UL',[0 11]));
assert(~sixgr.phy.pdcch.DCIContextFactory.supportsSymbolAllocation(cfg,'UL',[0 14]));
assert(cfg.phy.synchronization.maxReceivedULTimingAgeSlots==4, ...
    'The fix must preserve the original measured-clock freshness limit.');
strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
assert(strict.ToolboxSRS.SymbolStart==11);
assert(numel(cfg.phy.srs.ueResourceBindings)==2);
multi=struct('Enabled',true,'NumUsers',2,'RNTIStart',201, ...
    'ExecutionModel','slot_coupled_truth');
runtime=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempdir,multi,struct(),50);
runtime.CurrentServingIdx(:)=1;
bound=cell(1,2); grids=cell(1,2);
for ue=1:2
    [bound{ue},~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,ue,'UL');
    binding=bound{ue}.phy.srs.UEFrequencyResourceBinding;
    assert(binding.UEIndex==ue && binding.RNTI==200+ue && binding.CombOffset==ue-1);
    native=sixgr.phy.srs.buildSRSConfigFromScenario(bound{ue});
    % Exercise the installed calendar, not an assumed slot-zero occasion.
    for slot0=0:2*native.ToolboxCarrier.SlotsPerFrame-1
        native.ToolboxCarrier.NSlot=mod(slot0,native.ToolboxCarrier.SlotsPerFrame);
        native.ToolboxCarrier.NFrame=floor(slot0/native.ToolboxCarrier.SlotsPerFrame);
        if ~isempty(nrSRSIndices(native.ToolboxCarrier,native.ToolboxSRS)), break; end
    end
    grids{ue}=nrResourceGrid(native.ToolboxCarrier,native.NumSRSPorts);
    grids{ue}(nrSRSIndices(native.ToolboxCarrier,native.ToolboxSRS))= ...
        nrSRS(native.ToolboxCarrier,native.ToolboxSRS);
end
assert(any(grids{1}~=0,'all') && any(grids{2}~=0,'all'));
assert(~any(any(grids{1}~=0,3) & any(grids{2}~=0,3),'all'), ...
    'Production runtime UE binding must keep the configured SRS combs disjoint.');
carrier=sixgr.phy.grid.makeCarrier(cfg); p=cfg.phy.pusch;
grant=struct('UEIndex',1,'PRBSet',double(p.PRBSet), ...
    'SymbolAllocation',double(p.SymbolAllocation),'Modulation',char(string(p.modulation)), ...
    'NumLayers',double(p.numLayers),'RNTI',double(p.RNTI), ...
    'TransformPrecoding',logical(p.transformPrecoding), ...
    'TransmissionScheme',char(string(p.TransmissionScheme)), ...
    'NumAntennaPorts',double(p.NumAntennaPorts),'TPMI',double(p.TPMI), ...
    'NID',double(p.NID),'MappingType',char(string(p.mappingType)));
resources=cfg.validation.pucch_resources.resources; checked=0;
for slot0=0:2*carrier.SlotsPerFrame-1
    carrier.NSlot=mod(slot0,carrier.SlotsPerFrame);
    carrier.NFrame=floor(slot0/carrier.SlotsPerFrame);
    if isempty(nrSRSIndices(carrier,strict.ToolboxSRS)), continue; end
    grant.ScheduledAbsoluteSlot=slot0+1; grant.Slot=slot0+1;
    for ue=1:2
        d=sixgr.phy.frame.resolveSRSPUSCHCollision(cfg,grant,slot0+1,ue);
        assert(~d.Collision && d.SRSRECount>0 && d.PUSCHRECount>0);
        for r=reshape(resources,1,[])
            pucch=struct('UEIndex',1,'RNTI',p.RNTI,'PUCCHResourceId',r.id);
            d=sixgr.phy.frame.resolveSRSPUCCHCollision(cfg,pucch,slot0+1,ue);
            assert(~d.Collision && d.SRSRECount>0 && d.PUCCHRECount>0);
        end
    end
    checked=checked+1;
end
assert(checked>0);
% Reproduce the old allocation. Reject the configured starvation hazard;
% never change PUCCH priority or refresh timing from an untransmitted SRS.
bad=s.toStruct(); bad.reference_signals.srs.symbol_start=13;
try
    sixgr.lls6g.buildInternalConfig(bad,tempname);
catch ME
    assert(strcmp(ME.identifier,'sixgr:lls6g:config:SRSFirstMeasurementPUCCHCollision'), ...
        'Unexpected starvation rejection: %s',ME.identifier);
    fprintf('BIDIRECTIONAL_UL_RESOURCE_PLAN_PASS native_occasions=%d stale_guard_unchanged=1 DCI_TDRA_bound=1\n',checked);
    ok=true; return;
end
error('test:MissingRejection','The old SRS/PUCCH symbol collision must remain rejected.');
end
