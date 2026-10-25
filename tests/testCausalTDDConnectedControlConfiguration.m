function ok=testCausalTDDConnectedControlConfiguration()
% Configuration/native allocation only: no RF, received timing or RRC claim.
% Reproduces the main bundle's slot-one startup consumer before acquisition.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(root,'results','validation','causal_tdd_connected_control', ...
    char(java.util.UUID.randomUUID()));
mkdir(folder);
fprintf('CAUSAL_TDD_CONNECTED_CONTROL_EVIDENCE %s\n',folder);
paths=["scenarios/lls_causal_access_to_data_wiring_tdd.yaml", ...
    "scenarios/lls_causal_access_to_data_wiring_tdd_short.yaml", ...
    "validation/main_independent_broadcast_access.yaml", ...
    "scenarios/lls_pdcch_shared_queue_fixture.yaml", ...
    "scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml"];
receipts=cell(numel(paths),1);
for k=1:numel(paths)
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile(root,'simulator','configs',paths(k)));
    original=s.toStruct();
    hashes=arrayfun(@(p)string(sixgr.util.sha256File(p)),s.SourceFiles);
    assert(any(endsWith(replace(s.SourceFiles,'\','/'), ...
        '/control/connected_single_port_tdd.yaml')));
    cfg=sixgr.lls6g.buildInternalConfig(s,fullfile(folder,"case_"+k));
    before=cfg; beforeRNG=rng;
    contexts=sixgr.truth.validateSharedDCIConfiguration(cfg);
    assert(isequaln(before,cfg) && isequaln(beforeRNG,rng) && isequaln(original,s.toStruct()), ...
        'test:ConfigurationMutation','Startup validation must not repair its input or execute PHY.');
    assert(cfg.phy.carrier.NSizeGrid==25 && cfg.phy.carrier.SubcarrierSpacing==15 && ...
        cfg.phy.pdsch.enable && cfg.phy.pusch.enable && ...
        cfg.run.controlGating.pbchRequired && cfg.run.controlGating.prachRequired);
    for direction=["DL","UL"]
        c=contexts.(direction); aligned=sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(c);
        assert(~c.Data.LegacyCompatibility && ...
            c.Data.ExecutionProfile=="configured_connected_dci_r18" && ...
            c.Data.SpecVersion=="18.8.0" && aligned.Selected.AlignedBits>0);
    end
    continuous=contains(paths(k),'continuous_iq');
    expectedPorts=1+double(continuous);
    assert(contexts.UL.Data.ULPrecoding.num_ports==expectedPorts && ...
        cfg.phy.pusch.NumAntennaPorts==expectedPorts && cfg.phy.srs.nPorts==expectedPorts && ...
        contexts.UL.Data.ULPrecoding.max_rank==1 && cfg.phy.pusch.maxLayers==1 && ...
        contexts.DL.Data.TCIPresent==continuous, ...
        'test:InheritedControlOverride','Keep the parent one-port path and explicit sibling two-port/TCI overrides.');
    assert(isequal(cfg.phy.pdsch.timeDomainAllocations,[0 2 12 0;1 2 8 0]) && ...
        isequal(cfg.phy.pusch.timeDomainAllocations,[0 0 13 1;1 0 13 2]) && ...
        cfg.phy.pdsch.dmrs.NSCID==0 && cfg.phy.pusch.dmrs.NSCID==0);
    carrier=sixgr.phy.grid.makeCarrier(cfg);
    rx=sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build(cfg,carrier,cfg.phy.pdsch.RNTI,true);
    tx=sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build(cfg,carrier,cfg.phy.pdsch.RNTI,false);
    assert(isequaln(rx.CORESET,tx.CORESET) && isequaln(rx.SearchSpace,tx.SearchSpace) && ...
        rx.RNTI==tx.RNTI && rx.NStartBWP==tx.NStartBWP && rx.NSizeBWP==tx.NSizeBWP);
    txIndices=nrPDCCHResources(carrier,tx); rxIndices=nrPDCCHResources(carrier,rx);
    assert(~isempty(txIndices) && ~isempty(rxIndices));
    % Missing installed policy still fails before channel/RF materialization.
    bad=cfg; bad.phy.pdcch.operatorControl=rmfield(bad.phy.pdcch.operatorControl,'connected_dci');
    reject(@()sixgr.truth.validateSharedDCIConfiguration(bad), ...
        'sixgr:phy:pdcch:missing_dci_context');
    reject(@()sixgr.truth.CoupledWaveformStream.initialize(struct('CurrentSlot',1),bad,{bad}), ...
        'sixgr:phy:pdcch:missing_dci_context');
    missingSR=cfg;
    missingSR.validation.pucch_resources=rmfield(missingSR.validation.pucch_resources,'scheduling_request_resources');
    reject(@()sixgr.truth.validateSharedDCIConfiguration(missingSR),'sixgr:truth:MissingInstalledSRCalendar');
    assert(isequal(hashes,arrayfun(@(p)string(sixgr.util.sha256File(p)),s.SourceFiles)));
    receipts{k}=struct('Path',paths(k),'SourceFiles',s.SourceFiles,'SourceHashes',hashes, ...
        'DLContext',contexts.DL.Data,'ULContext',contexts.UL.Data, ...
        'NativeTXPDCCHIndices',txIndices,'NativeRXPDCCHIndices',rxIndices, ...
        'Scope',"installed_configuration_and_native_RE_allocation_not_received_control");
    fprintf('CAUSAL_TDD_CONNECTED_CONTROL_CASE_PASS %s\n',paths(k));
end
save(fullfile(folder,'original_configuration_evidence.mat'),'receipts');
ok=true;
fprintf('CAUSAL_TDD_CONNECTED_CONTROL_PASS scenarios=%d waveform_execution=0\n',numel(paths));
end

function reject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingDCIConfigurationRejection','Expected %s.',id);
end
