function ok=testFlatAWGNSRSWaveformCandidate()
% Focused physical SRS candidate test, not integrated/statistical acceptance.
% Known NR pilots + acquired samples enter estimation; channel/noise truth
% enter only waveform generation and independent scoring afterwards.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
folder=fullfile(pwd,'logs','srs_flat_waveform_candidate', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(scenario,folder);
strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15);
ofdm=nrOFDMInfo(carrier);
stream=RandStream('mt19937ar','Seed',5192459);
rows=struct([]);
for snr=[-10 20]
 for ports=[1 2 4]
  for comb=[2 4]
   for hopping=[false true]
    srs=strict.ToolboxSRS;
    srs.NumSRSPorts=ports; srs.SRSPeriod='on'; srs.KTC=comb;
    srs.BSRS=double(hopping); srs.BHop=0;
    srs.NumSRSSymbols=4; srs.SymbolStart=10; srs.Repetition=1;
    widths=srs.BandwidthConfigurationTable{:,'m_SRS_0'};
    ids=srs.BandwidthConfigurationTable{:,'C_SRS'};
    srs.CSRS=ids(find(widths<=carrier.NSizeGrid,1,'last'));
    if comb==4, srs.CyclicShift=6; else, srs.CyclicShift=0; end
    if ports==1
        H=[.8 .6i];
    elseif ports==2
        H=[.8 0 .6 0;0 .6 0 .8];
    else
        H=[.8 0;0 .6;.6 0;0 .8];
    end
    R=size(H,2);
    ind=nrSRSIndices(carrier,srs); sym=nrSRS(carrier,srs);
    txGrid=nrResourceGrid(carrier,ports); txGrid(ind)=sym;
    transmitted=nrOFDMModulate(carrier,txGrid,'Windowing',0);
    leading=17; trailing=23;
    desired=[complex(zeros(leading,R));transmitted*H;complex(zeros(trailing,R))];
    gridVariance=sixgr.link.resolveAWGNReferenceEnergy(cfg)/10^(snr/10);
    sampleVariance=gridVariance/double(ofdm.Nfft);
    noise=sqrt(sampleVariance/2)*(randn(stream,size(desired))+1i*randn(stream,size(desired)));
    received=desired+noise;
    [aligned,timing]=sixgr.phy.sync.alignULReferenceObservation( ...
        carrier,received,ind,sym,[0 leading+trailing]);
    grid=sixgr.phy.waveform.ofdmDemodulate(carrier,aligned);
    % Regenerate receiver-known reference, never extract transmitted data.
    known=nrResourceGrid(carrier,ports); known(ind)=nrSRS(carrier,srs);
    X=reshape(known,[],ports); Y=reshape(grid,[],R);
    mask=any(X~=0,2); X=X(mask,:); Y=Y(mask,:);
    fit=sixgr.phy.rx.estimateFlatAWGNMultiportChannel(Y,X);
    nmse=norm(fit.GainPerPortReceiveBranch-H,'fro')^2/norm(H,'fro')^2;
    expectedNMSE=gridVariance*R*real(trace((X'*X)\eye(ports)))/norm(H,'fro')^2;
    row=struct('ReferenceSNR_dB',snr,'Ports',ports,'ReceiveBranches',R, ...
        'Comb',comb,'Hopping',hopping,'PilotRECount',size(X,1), ...
        'TrueTimingOffset_samples',leading,'MeasuredTimingOffset_samples',timing.TimingOffsetSamples, ...
        'InjectedGridNoiseVarianceScoringOnly',gridVariance, ...
        'EstimatedGridNoiseVariance',fit.NoiseVariance, ...
        'NoiseError_dB',10*log10(fit.NoiseVariance/gridVariance), ...
        'ChannelNMSE_dB',10*log10(nmse),'ExpectedMeanNMSE_dB',10*log10(expectedNMSE), ...
        'ErrorToExpectedMeanRatio',nmse/expectedNMSE, ...
        'Scope',"physical_AWGN_candidate_not_integrated_or_statistically_qualified");
    rows=[rows;row]; %#ok<AGROW>
   end
  end
 end
end
results=struct2table(rows);
writetable(results,fullfile(folder,'waveform_candidate.csv'));
disp(results);
assert(all(results.MeasuredTimingOffset_samples==results.TrueTimingOffset_samples), ...
    'test:FlatSRSTiming','Known-pilot timing acquisition failed; retain the failed row.');
assert(all(abs(results.NoiseError_dB)<2), ...
    'test:FlatSRSNoise','Measured noise exceeds the fixed two-dB engineering bound.');
assert(all(results.ErrorToExpectedMeanRatio<6), ...
    'test:FlatSRSChannel','Channel error exceeds the fixed statistical-model regression bound.');
fprintf('FLAT_SRS_WAVEFORM_CANDIDATE_PASS cases=%d evidence=%s runtime_enabled=0\n',height(results),folder);
ok=true;
end
