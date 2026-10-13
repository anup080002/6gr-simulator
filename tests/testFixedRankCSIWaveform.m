function ok=testFixedRankCSIWaveform()
% Actual full-grid CSI-RS OFDM/receiver/report test, NOT a scenario run.
% Reuse the installed 64-element/eight-beam map with a declared static
% linear test channel. This does not qualify CDL, RF patterns or access.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/fixtures/lls_fixed_rank4_connected_config.yaml');
installed=sixgr.lls6g.buildInternalConfig(source,tempname);
folder=fullfile(pwd,'results','lls','fixed_rank_csi_receiver', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); rows=table();
cases=[30 273;120 264];
for index=1:size(cases,1)
    scs=cases(index,1); nPRB=cases(index,2);
    carrier=nrCarrierConfig('SubcarrierSpacing',scs,'NSizeGrid',nPRB, ...
        'NCellID',installed.phy.carrier.NCellID,'NSlot',5);
    cfg=installed;
    cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
    cfg.phy.carrier.NSizeGrid=nPRB;
    cfg.phy.carrier.SubcarrierSpacing=scs;
    cfg.phy.carrier.SubcarrierSpacing_kHz=scs;
    cfg.phy.pdsch.prbSet=0:nPRB-1;
    cfg.phy.csirs.numRBsByResource=repmat(nPRB,1,8);
    cfg.phy.rx.cfoCorrectionEnabled=false;
    cfg.runtime.currentSlot=6;
    cfg.lls6g.runtime.AbsoluteSlotIndex0=5;
    cfg.lls6g.userContext=struct('RuntimeUEIndex',1,'RuntimeCurrentSlot',6);
    cfg.lls6g.runtimePowerContext=struct( ...
        'WaveformAmplitudeUnit','normalized_unit_es','PhysicalDevicePowerClaim',false);
    % Exercise policy authority even if an older installed report supports
    % more ranks. Keep the wire unchanged; restrict the actual search.
    cfg.phy.csi.rankDomain=[1 2 4];
    cfg.phy.csi.reportConfiguration.AllowedRanks=[1 2 4];
    physical=sixgr.phy.refsig.materializeCSIRSPhysicalGrid( ...
        carrier,cfg,'WaveformPortCount',64);
    assert(physical.Event.Transmitted && size(physical.Grid,3)==64 && ...
        physical.Event.NumResources==8);
    [waveform,ofdm]=nrOFDMModulate(carrier,physical.Grid);
    basis=cfg.phy.csirs.precoderMatrices(:,:,1);
    channel=diag([1 .7 .3 .1])*basis';
    % This is a test-channel execution, never a channel oracle given to RX.
    delay=37; searchEnd=73; snr=20;
    capture=[zeros(delay,4);waveform*channel.';zeros(searchEnd-delay,4)];
    capture=sixgr.phy.waveform.addOccupiedREAWGN(capture,carrier,snr, ...
        'Seed',5101321+index,'SignalEnergyPerOccupiedRE',1);
    rx=sixgr.phy.refsig.receiveCSIRSWaveform( ...
        carrier,cfg,capture,capture,[0 searchEnd],struct());
    [report,detail]=sixgr.phy.refsig.computeCSIRSFeedback(carrier,cfg,rx);
    assert(report.RI==4 && isequal(size(report.Precoder_W),[4 4]) && ...
        report.RankDomain==4 && ~report.ConfiguredOracleUsed && ...
        ~detail.PDSCHDecodeAttempted && ~detail.DCIConsumed);
    assert(rx.ReceiveTiming.TimingOffsetSamples==delay && ...
        ~rx.ReceiveTiming.OracleTimingUsed && ...
        rx.CSIMeasurementState.Slot==6);
    wire=sixgr.phy.mimo.CSIReportConfiguration( ...
        cfg.phy.csi.reportConfiguration,cfg.phy.csi.reportConfiguration.Epoch);
    received=wire.decode(report.CSIPart1Bits,report.CSIPart2Bits);
    assert(received.RI==4 && received.PMI==report.PMI && ...
        received.CQI_CW0==report.CQI && received.CRI==report.CRI);
    assert(all(isfinite(report.SelectionInfo.SelectedSINRPerRELayer),'all'));
    if scs==120
        assert(ofdm.Nfft==4096 && ofdm.SampleRate==491.52e6);
    end
    row=table(scs,nPRB,ofdm.SampleRate,ofdm.Nfft,64,4,8,report.RI, ...
        report.PMI,report.CRI,report.CQI,report.SINR_dB, ...
        rx.ReceiveTiming.TimingOffsetSamples, ...
        "CSI_only_OFDM_declared_static_linear_channel_not_CDL_or_scenario_acceptance", ...
        false,'VariableNames',{'SCS_kHz','NSizeGrid','SampleRateHz','Nfft', ...
        'PhysicalTxDimensions','RxDimensions','CSIResources','RI','PMI','CRI', ...
        'CQI','MeasuredCSIObjective_dB','TimingEstimateSamples','Scope','ScenarioAccepted'});
    rows=[rows;row]; %#ok<AGROW>
    writetable(rows,fullfile(folder,'received_csi.csv'));
    save(fullfile(folder,sprintf('case_%d.mat',index)), ...
        'carrier','cfg','channel','delay','snr','report','detail','row','-v7.3');
    fprintf('FIXED_RANK_CSI_WAVEFORM scs=%g PRB=%g TX=64 RX=4 beams=8 RI=%g PMI=%g CQI=%g\n', ...
        scs,nPRB,report.RI,report.PMI,report.CQI);
end
assert(height(rows)==2);
fprintf('FIXED_RANK_CSI_WAVEFORM_PASS evidence=%s\n',folder);
ok=true;
end
