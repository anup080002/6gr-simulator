function ok=testReceivedCSIToScheduledPDSCH(preflightOnly)
% Actual shared CSI -> combined PUCCH -> admitted PF feedback -> later
% scheduled/decoded PDCCH -> emitted/completed PDSCH with canonical data
% preparation, completion/publication and per-UE state drain. YAML gates and TAG
% expiry are unchanged. The explicit coexistence fixture reserves SRS 11,
% PUSCH 0:10 and PUCCH 12:13; it does not alter the collision fixture.
% This is one 5 MHz component, not n40/full access,
% activated Type-D TCI, RR coverage, or a BLER/adaptation qualification.
if nargin<1, preflightOnly=false; end
assert(islogical(preflightOnly) && isscalar(preflightOnly));
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
fixture=fullfile(root,'simulator','configs','scenarios', ...
    'lls_tdd_received_csi_application_coexistence_fixture.yaml');
s=sixgr.lls6g.config.loadScenarioConfig(fixture);
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
localMappedAllocationPreflight(cfg);
if preflightOnly, ok=true; return; end
folder=fullfile(root,'logs','received_csi_to_scheduled_pdsch');
if ~isfolder(folder), mkdir(folder); end
[ok,state]=testSharedPUSCHChannelArtifacts('TDD',false,false,true,true,true,false, ...
    tempname(folder),fixture,false,true,false,false,true,2,false,false,true);
assert(ok && state.TestContinuationCompleted && ...
    state.TestContinuationApplication.WaveformApplicationVerified && ...
    ~state.TestContinuationApplication.FullScenarioQualified);
assert(state.TestCanonicalCompletionDrainVerified && ...
    height(state.TestPublishedDLTrials)==1 && isempty(state.TestPublishedULTrials) && ...
    isempty(state.SharedCompletedDataPlans) && ...
    isequaln(state.SharedULLinkAdaptationStates,state.TestPublishedULStates), ...
    'The physical continuation must publish the canonical finalized row and drain its actual LA output.');
end

function localMappedAllocationPreflight(cfg)
% Configured native RE mapping only, not emitted/recovered waveform proof.
strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
carrier=strict.ToolboxCarrier; carrier.NSlot=strict.ExpectedSlotSet(1);
symbolSet=@(indices)reshape(unique(floor(mod(double(indices(:))-1, ...
    double(carrier.NSizeGrid)*12*double(carrier.SymbolsPerSlot))/ ...
    (double(carrier.NSizeGrid)*12))),1,[]);
srsSymbols=symbolSet(nrSRSIndices(carrier,strict.ToolboxSRS));
assert(isequal(srsSymbols,11) && strict.NumSRSSymbols==1 && ...
    strict.Periodicity==5 && strict.Offset==4);
assert(isequal(double(cfg.phy.pusch.symbolAllocation),[0 11]));
dci=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
assert(isequal(double(dci.Data.ULTimeDomainAllocations),[0 0 11 1;1 0 11 2]));
[data,~,pusch]=sixgr.phy.grid.allocREsPUSCH(carrier,cfg,'FixedReferenceMode',true);
dmrs=nrPUSCHDMRSIndices(carrier,pusch);
puschSymbols=symbolSet([data(:);dmrs(:)]);
assert(isequal(puschSymbols,0:10) && isempty(intersect(puschSymbols,srsSymbols)));
id=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',cfg.lls6g.users.rnti_start,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
for k=1:numel(rrc.Resources)
    resource=rrc.Resources(k);
    symbols=symbolSet(nrPUCCHIndices(carrier,resource.toolboxConfig()));
    assert(isequal(symbols,12:13) && isempty(intersect(symbols,[srsSymbols puschSymbols])));
end
[~,ulAllowed]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,strict.Offset+1);
assert(ulAllowed && cfg.run.controlGating.srsRequired && ...
    cfg.run.controlGating.pbchRequired && cfg.run.controlGating.trsRequired);
fprintf('CSI_APPLICATION_ALLOCATION_PREFLIGHT_PASS native_SRS=11 native_PUSCH=0:10 native_PUCCH=12:13 waveform_qualification=0\n');
end
