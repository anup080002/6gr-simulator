function audit=auditLLS12dBSpatialBudget(runRoot)
% Offline scoring of retained channel coefficients; never a receiver input.
% This is a frozen-time, occupied-band spatial-power diagnostic, not a
% reconstructed runtime SINR, BLER or new primary simulation observation.
s=sixgr.lls6g.config.loadScenarioConfig(fullfile(runRoot,'meta','scenario_config_resolved.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
dl=sixgr.util.csvReadTable(fullfile(runRoot,'air_interface','csv','dl_pdsch_trials.csv'),'TextType','string');
ul=sixgr.util.csvReadTable(fullfile(runRoot,'air_interface','csv','ul_pusch_trials.csv'),'TextType','string');
[candidates,~]=sixgr.phy.dl.pmiCodebookCandidates(cfg,1,2,'Mode','type1_su_mimo');
B=complex(double(cfg.phy.csirs.precoderMatrices(:,:,1)));
Wd=[]; matched=NaN;
for k=1:numel(candidates)
    W=B*double(candidates(k).W);
    if sixgr.phy.mimo.MatrixContract.digest(W)==dl.AppliedPrecoderMatrixSHA256(1)
        Wd=W; matched=candidates(k).PMI; break;
    end
end
assert(~isempty(Wd),'audit:DLMatrixNotIdentified','Do not attribute the DL gain without matching the actually applied matrix hash.');
WuLogical=nrPUSCHCodebook(1,double(cfg.phy.pusch.NumAntennaPorts),double(ul.AppliedPrecoderPMI(1))).';
assert(sixgr.phy.mimo.MatrixContract.digest(WuLogical)==ul.AppliedPrecoderMatrixSHA256(1), ...
    'audit:ULMatrixNotIdentified','The uplink codebook must match the applied matrix hash.');
au=sixgr.rf.AntennaArrayFactory.build(cfg,'ue','signal','pusch','numPorts',size(WuLogical,1));
ad=sixgr.rf.AntennaArrayFactory.build(cfg,'bs','signal','pdsch','numPorts',size(Wd,1));
Wu=au.PortToElementMatrix*WuLogical; WdPhysical=ad.PortToElementMatrix*Wd;
audit=struct('Scope',"offline_frozen_time_spatial_power_not_runtime_SINR", ...
    'DLPMIIdentifiedByAppliedMatrixHash',matched,'DLMatrixReal',real(WdPhysical), ...
    'DLMatrixImag',imag(WdPhysical),'ULMatrixReal',real(Wu),'ULMatrixImag',imag(Wu), ...
    'DLTotalLayerPower',sum(abs(WdPhysical).^2,'all'), ...
    'ULTotalLayerPower',sum(abs(Wu).^2,'all'));
carrier=sixgr.phy.grid.makeCarrier(cfg); oi=nrOFDMInfo(carrier);
for direction=["DL","UL"]
    T=dl(1,:); if direction=="UL", T=ul(1,:); end
    sixgr.channel.validateSharedChannelObservationArtifact(runRoot,T);
    saved=load(fullfile(runRoot,T.ChannelObservationMATFile),'Captures');
    r=saved.Captures{1}.Reference;
    index=max(1,round(size(r.PathGains,1)/2));
    g=squeeze(r.PathGains(index,:,:,:)); % path, TX, RX
    F=fft(double(r.PathFilters),double(oi.Nfft),1);
    K=12*double(carrier.NSizeGrid); bins=mod((-K/2:K/2-1),double(oi.Nfft))+1;
    hd=zeros(K,size(g,3),size(g,2));
    for tx=1:size(g,2)
        for rx=1:size(g,3), hd(:,rx,tx)=F(bins,:)*g(:,tx,rx); end
    end
    if direction=="UL", hd=permute(hd,[1 3 2]); end
    gd=zeros(K,1); gu=zeros(K,1);
    for k=1:K
        H=squeeze(hd(k,:,:));
        gd(k)=sum(abs(H*WdPhysical).^2);
        gu(k)=sum(abs(H.'*Wu).^2);
    end
    row=struct('SourceTrialSlot',double(T.Slot),'SourceChannelMATFile',T.ChannelObservationMATFile, ...
        'SampleIndex',r.StartSample+index-1,'DLReceiveBranchSumGain_dB',10*log10(mean(gd)), ...
        'ULReceiveBranchSumGain_dB',10*log10(mean(gu)), ...
        'SameReciprocalChannelDLMinusULSpatialPower_dB',10*log10(mean(gd)/mean(gu)), ...
        'ConfiguredGridNoiseVariance',double(T.ReplayGridNoiseVariance), ...
        'ReportedRuntimePostEQ_SINR_dB',double(T.MeasuredSINR_dB));
    audit.(direction+"Capture")=row;
end
end
