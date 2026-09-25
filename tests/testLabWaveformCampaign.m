function testLabWaveformCampaign
% Focused actual-coded waveform, native clock, table authority and guard tests.
c=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml');
s=c.toStruct(); profiles=sixgr.phy.research.validateLabWaveform(s);
assert(isequal([profiles.MCS],[26 25 24]));
assert(isequal([profiles.TargetCodeRate],[948 900.5 853]/1024));
f=sixgr.phy.FrameStructureEngine(s,'FrameCoreOnly',true);
assert(f.SampleRate_Hz==491520000 && f.FFTSize==4096 && f.NRB==264);
assert(s.mimo.n_layers==2 && s.mimo.n_tx_ant==2 && s.mimo.n_rx_ant==2);
assert(sum(arrayfun(@(k)f.IsDLAllocation(k,[0 14]),0:7))==5);
assert(sum(arrayfun(@(k)f.IsULAllocation(k,[0 14]),0:7))==2);
samples=0;
for k=0:79
    carrier=nrCarrierConfig('NSizeGrid',264,'SubcarrierSpacing',120,'NSlot',k);
    info=nrOFDMInfo(carrier,'Nfft',4096,'SampleRate',491520000,'Windowing',0);
    % nrOFDMInfo CP vectors cover a subframe; select the actual slot segment.
    [w,~]=nrOFDMModulate(carrier,nrResourceGrid(carrier,2),'Nfft',4096,'SampleRate',491520000,'Windowing',0);
    assert(info.Nfft==4096); samples=samples+size(w,1);
end
assert(samples==4915200 && mod(samples,8)==0);
rng(100,'twister'); dirs=["DL","UL"]; slots=[0 6];
for di=1:2
    a=sixgr.phy.research.SharedChannelLink.allocation(s,slots(di),dirs(di));
    assert(a.Qm==10 && a.NumLayers==2 && a.NumPhysicalPorts==2 && a.CodingLayout.BaseGraph==1);
    assert(a.TransportBlockSize==nrTBS('1024QAM',2,264,a.NREPerPRB,948/1024,0));
    tb=int8(randi([0 1],a.TransportBlockSize,1));
    tx=sixgr.phy.research.SharedChannelLink.transmit(s,slots(di),tb,dirs(di));
    nv=(.5/10^4)/tx.OFDM.SampleToGridNoiseVarianceGain;
    noisy=tx.Waveform+sqrt(nv/2)*(randn(size(tx.Waveform))+1j*randn(size(tx.Waveform)));
    rx=sixgr.phy.research.SharedChannelLink.receive(s,slots(di),noisy,dirs(di));
    assert(rx.CRCPass && isequal(rx.TransportBlock,tb),'Actual high-SNR coded payload failed.');
    assert(~rx.PerfectCSI && rx.ChannelEstimateSource=="received_DMRS_nrChannelEstimate");
    measured=10*log10(sum(abs(tx.Grid(a.DataIndices)).^2,'all')/sum(abs(rx.Grid(a.DataIndices)-tx.Grid(a.DataIndices)).^2,'all'));
    assert(abs(measured-40)<.2,'Native sample/grid noise calibration differs from configured SNR.');
    fprintf('LAB_FOCUSED %s TBS=%d CRC=1 measuredSNR=%.4f\n',dirs(di),a.TransportBlockSize,measured);
end
bad=s; bad.research_dl.target_code_rate=.82; localReject(bad,'sixgr:lab:MCSRateMismatch');
bad=s; bad.control.pucch_enabled=true; localReject(bad,'sixgr:lab:EnabledUnsupportedBlock');
bad=s; bad.mimo.n_rx_ant=1; localReject(bad,'sixgr:lls6g:config:BadRank');
bad=s; bad.research_receiver.channel_estimation='perfect_identity_awgn'; localReject(bad,'sixgr:lab:ReceiverPolicy');
old=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml');
assert(old.get('research_dl.target_code_rate')==.82 && old.get('scenario.runner_profile')=="research_tdd_link");
fprintf('testLabWaveformCampaign PASS\n');
end

function localReject(s,id)
try
    sixgr.phy.research.validateLabWaveform(s);
catch e
    assert(string(e.identifier)==string(id),'Unexpected rejection: %s',e.identifier); return;
end
error('Expected rejection %s.',id);
end
