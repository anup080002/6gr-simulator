function ok=testLLSRepairNextRunManifest()
% Configuration/export fixture only: never executes waveform slots.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'scripts'));
label=['fixture_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))];
file=prepareLLSRepairNextRunManifest(label);
manifest=jsondecode(fileread(file));
scenario=jsondecode(fileread(fullfile(fileparts(file),'scenario_resolved.json')));
assert(isequaln(manifest.ResolvedScenario,scenario));
assert(manifest.ResolvedScenario.run_control.total_slots==100 && ...
    manifest.ResolvedScenario.simulation.n_slots==100);
assert(manifest.ResolvedInternal.channel.fc_Hz==4e9 && ...
    manifest.ResolvedInternal.channel.bandwidth_Hz==100e6 && ...
    manifest.ResolvedInternal.phy.carrier.NSizeGrid==273 && ...
    manifest.ResolvedInternal.phy.carrier.SubcarrierSpacing_kHz==30);
assert(strcmp(manifest.ResolvedInternal.phy.frame.ComponentCarriers.DuplexMode,'TDD') && ...
    manifest.ResolvedScenario.mimo.n_tx_ant==64 && manifest.ResolvedScenario.mimo.n_rx_ant==4 && ...
    manifest.ResolvedScenario.mimo.max_dl_layers==4 && manifest.ResolvedScenario.mimo.max_ul_layers==4 && ...
    manifest.ResolvedInternal.channel.sampleRate_Hz==122.88e6);
assert(~manifest.ExecutionAuthorized && ~manifest.ReadyForEndToEndAcceptance && ...
    manifest.MainCheckoutPatched && strcmpi(manifest.SourceRoot,root));
assert(~isempty(manifest.ConfigSources));
for source=reshape(manifest.ConfigSources,1,[])
    assert(strcmpi(source.SHA256,sixgr.util.sha256File(source.Path)));
end
assert(strcmpi(manifest.CoreRuntimeSHA256,sixgr.util.sha256File(manifest.CoreRuntimeSource)));
assert(strcmpi(manifest.ScenarioConfigSHA256, ...
    sixgr.util.sha256File(fullfile(fileparts(file),'scenario_resolved.json'))));
fprintf('LLS_REPAIR_MANIFEST_PASS path=%s waveform_executed=0\n',file);
ok=true;
end
