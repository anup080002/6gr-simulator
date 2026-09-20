function ok=testExperimentalFrozenGrantContext()
% Coding-policy immutability only; no acquisition/SRS/decoder qualification.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_four_port_connected_research_ul_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.phy.pusch.mcsIndex=4;
cfg.phy.pusch.modulation='1024QAM';
cfg.phy.pusch.codeRate=.5;
W=[eye(2);zeros(2)]/sqrt(2);
grant=struct('Direction','UL','Frame',0,'Slot',7, ...
    'RNTI',cfg.phy.pusch.RNTI,'UEIndex',1,'ServingCell',1, ...
    'NumLayers',2,'Layers',2,'NumLogicalPorts',4,'NumElements',4, ...
    'NumRFChains',4,'NumRxAntennas',4,'PRBSet',0:5, ...
    'SymbolAllocation',[0 13],'MCSIndex',4,'Modulation','1024QAM', ...
    'MCSTable',cfg.phy.pusch.mcsTable,'TargetCodeRate',.5, ...
    'TransmissionScheme','nonCodebook','PrecodingMatrixLogicalPorts',W, ...
    'PrecodingMatrix',W,'PrecoderNormalizationConvention','unit_frobenius');
frozen=sixgr.phy.grant.freezePHYGrant(cfg,'UL',grant,'Frame',0,'Slot',7);
assert(isfield(frozen.CodingLayout,'ExperimentalMCSTable') && ...
    isequaln(frozen.CodingLayout.ExperimentalMCSTable,cfg.phy.pusch.experimentalMCSTable), ...
    'Experimental frozen grants must bind the complete installed codepoint definition.');
assert(isequaln(frozen.CodingLayout.ResearchTransportPolicy,cfg.phy.pusch.researchTransportPolicy));
assert(~frozen.CodingLayout.StandardNR && ...
    string(frozen.CodingLayout.ResearchClass)=="optional_research_experiment");
% Ambient candidate choices cannot change an already scheduled codepoint.
ambient=cfg;
ambient.phy.pusch.mcsTable='qam64_table1';
ambient.phy.pusch=rmfield(ambient.phy.pusch,{'experimentalMCSTable','researchTransportPolicy'});
replay=sixgr.phy.grant.applyPHYGrantToConfig(ambient,frozen);
assert(string(replay.phy.pusch.mcsTable)==string(cfg.phy.pusch.mcsTable));
assert(isequaln(replay.phy.pusch.experimentalMCSTable,cfg.phy.pusch.experimentalMCSTable) && ...
    isequaln(replay.phy.pusch.researchTransportPolicy,cfg.phy.pusch.researchTransportPolicy));
assert(replay.phy.pusch.mcsIndex==4 && strcmp(replay.phy.pusch.modulation,'1024QAM'));
bad=frozen;
bad.CodingLayout.ExperimentalMCSTable.Rows(5,3)=.9;
localReject(@()sixgr.phy.grant.applyPHYGrantToConfig(cfg,bad), ...
    'sixgr:research:FrozenTransportContextMismatch');
bad=frozen; bad.CodingLayout.TargetCodeRate=.9;
localReject(@()sixgr.phy.grant.applyPHYGrantToConfig(cfg,bad), ...
    'sixgr:research:FrozenTransportContextMismatch');
bad=frozen; bad.CodingLayout.ResearchTransportPolicy.unboundExtraField=true;
localReject(@()sixgr.phy.grant.applyPHYGrantToConfig(cfg,bad), ...
    'sixgr:research:FrozenTransportContextMismatch');
bad=rmfield(frozen.CodingLayout,'ResearchTransportPolicy');
missing=frozen; missing.CodingLayout=bad;
localReject(@()sixgr.phy.grant.applyPHYGrantToConfig(cfg,missing), ...
    'sixgr:research:FrozenTransportContextMismatch');
reuse=grant; reuse.PHYGrant=frozen;
changed=cfg; changed.phy.pusch.researchTransportPolicy.research_pusch_uci.resource_mapping='invalid';
localReject(@()sixgr.phy.grant.freezePHYGrant(changed,'UL',reuse,'Frame',0,'Slot',7), ...
    'sixgr:research:FrozenTransportContextMismatch');
fprintf('EXPERIMENTAL_FROZEN_GRANT_CONTEXT_PASS\n');
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
