function ok=testLiveCSVPlotPublication()
% Publication integration with declared CSV fixture, not radio qualification.
setup6GRSimToolkit('Verbose',false);
for name=["lls_causal_access_to_data_wiring_tdd.yaml","lls_causal_access_to_data_wiring.yaml"]
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',name));
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    assert(cfg.outputs.liveCSVPNGEnabled==(logical(s.get('output.live_csv_png_enabled')) && ...
        cfg.outputs.saveFigures && cfg.outputs.savePNG));
    for contract=[false true]
        policy=sixgr.lls6g.runners.resolveWaveformBundlePublicationPolicy(cfg,contract);
        assert(policy.SaveFigures==(cfg.outputs.saveFigures && ~contract));
        assert(policy.LiveCSVPNGEnabled, ...
            'Terminal CSV raster authority must not disable live CSV raster publication.');
        for field=["saveFigures","savePNG","liveCSVPNGEnabled"]
            disabled=cfg; disabled.outputs.(field)=false;
            disabledPolicy=sixgr.lls6g.runners.resolveWaveformBundlePublicationPolicy(disabled,contract);
            assert(~disabledPolicy.LiveCSVPNGEnabled);
        end
    end
end
root=tempname; mkdir(root);
cfg.outputs.liveCSVPNGEnabled=false;
receipt=sixgr.artifact.publishLiveCSVPlots(cfg,root);
assert(~receipt.Enabled && isempty(dir(fullfile(root,'reports'))));
cfg.outputs.liveCSVPNGEnabled=true;
T=table("DL",1,7,9,"delivered_to_runtime_scheduler",10,"actual_decoded_csi", ...
    'VariableNames',{'Direction','UEIndex','SourceSlot','DeliveredSlot','DeliveryStatus','CQI','Source'});
sixgr.util.ensureFolder(fullfile(root,'air_interface','csv'));
sixgr.util.csvWriteTable(fullfile(root,'air_interface','csv','csi_feedback_reports.csv'),T,'PreserveSchema',true);
receipt=sixgr.artifact.publishLiveCSVPlots(cfg,root);
assert(receipt.Enabled && receipt.CreatedCount==1 && isfile(receipt.Manifest));
manifest=jsondecode(fileread(receipt.Manifest));
assert(~manifest.terminal_qualification);
second=sixgr.artifact.publishLiveCSVPlots(cfg,root);
assert(string(second.Status)=="unchanged_verified_snapshot");
code=fileread(which('sixgr.truth.runWaveformLinkBundle'));
assert(contains(code,'liveArtifacts.LivePNGSnapshots = sixgr.artifact.publishLiveCSVPlots(cfg, rootRunFolder)'));
assert(contains(code,'outputs.liveCSVPNGEnabled') && contains(code,'outputs.savePNG'));
assert(contains(code,'structGet(opt, "LiveCSVPNGEnabled"'), ...
    'Bundle must honor the independent live-renderer authority.');
runner=fileread(which('sixgr.lls6g.runners.runSingle'));
assert(contains(runner,'opt.LiveCSVPNGEnabled = publicationPolicy.LiveCSVPNGEnabled;') && ...
    contains(runner,'sixgr.lls6g.runners.resolveWaveformBundlePublicationPolicy('));
assert(contains(runner,'browserPublicationRequired = logical(sixgr.util.structGet(') && ...
    contains(runner,'if browserPublicationRequired') && ...
    contains(runner,'"terminal_browser_contract_refresh:" + string(refreshIdentifier)'), ...
    ['A terminal browser refresh may fail the run only when browser ' ...
    'publication is part of the mandatory claim.']);
fprintf('LIVE_CSV_PLOT_PUBLICATION_PASS: config gate, actual PNG, snapshot receipt, runtime call binding.\n');
ok=true;
end
