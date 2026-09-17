function ok=testResearchTDDLink()
% Complete configured TDD interval, exact payloads, physical clock and IQ.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
config=fullfile(pwd,'simulator','configs','scenarios','lls_7ghz_400mhz_1024qam_tdd_30db.yaml');
scfg=sixgr.lls6g.config.loadScenarioConfig(config); s=scfg.toStruct();
folder=tempname; mkdir(folder);
out=run_6g_phy_lls_single(config,folder,'integrated');
assert(out.ResultOk && ~out.Manifest.StandardNR && ~out.Manifest.StatisticalQualification);
assert(out.Ok && out.Config.ConfigHash==scfg.ConfigHash);
T=out.TrialTable; S=out.SummaryTable;
assert(height(T)==7 && all(T.CRCPass & T.TBExact) && all(T.Qm==10));
assert(sum(T.Direction=="DL")==3 && sum(T.Direction=="UL")==4);
assert(abs(out.Manifest.HorizonSeconds-.001)<1e-12);
assert(numel(unique(T.TBID))==height(T));
assert(all(T.EVMRMS<1.5*10^(-s.simulation.snr_db/20)));
for d=["DL","UL"]
    rows=T.Direction==d; row=S.Direction==d;
    assert(S.DeliveredUniqueBits(row)==sum(T.TBSBits(rows)));
    assert(S.GoodputBitsPerSecond(row)==sum(T.TBSBits(rows))/.001);
    tx=load(fullfile(out.RunFolder,'waveform',lower(d+"_TX"),'raw_iq.mat'));
    rx=load(fullfile(out.RunFolder,'waveform',lower(d+"_RX"),'raw_iq.mat'));
    assert(size(tx.Waveform,1)==491520 && isequal(size(tx.Waveform),size(rx.Waveform)));
    assert(tx.SampleRateHz==491520000 && tx.CenterFrequencyHz==7e9);
    assert(~isequal(tx.Waveform,rx.Waveform));
    clock=readtable(fullfile(out.RunFolder,'air_interface','csv','timeline.csv'));
    assert(all(clock.StartSample(2:end)==clock.StopSampleExclusive(1:end-1)));
    inactive=~clock.(d+"Active");
    for k=find(inactive).'
        assert(all(tx.Waveform(clock.StartSample(k)+1:clock.StopSampleExclusive(k),:)==0,'all'));
    end
end
iq=readtable(fullfile(out.RunFolder,'waveform','iq_manifest.csv'));
assert(height(iq)==8 && all(iq.ClippedComponents==0));
assert(all(iq.QuantizationMaxError<=.5/32767+eps));
assert(isfile(fullfile(out.RunFolder,'reports','image','tdd_goodput.png')));
try
    run_6g_phy_lls_single(config,folder,'integrated');
    error('test:ExpectedRejection','Existing evidence must not be overwritten.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:research:RunAlreadyExists'));
end
bad=s; bad.control.pdcch_enabled=true;
try
    sixgr.lls6g.runners.runResearchTDD(sixgr.lls6g.config.ScenarioConfig(bad),folder,'unsupported');
    error('test:ExpectedRejection','Unsupported enabled control must be rejected.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:research:UnsupportedEnabledBlock'));
end
fprintf('RESEARCH_TDD_LINK_PASS evidence=%s DL_Gbps=%g UL_Gbps=%g\n', ...
    out.RunFolder,S.GoodputBitsPerSecond(S.Direction=="DL")/1e9, ...
    S.GoodputBitsPerSecond(S.Direction=="UL")/1e9);
ok=true;
end
