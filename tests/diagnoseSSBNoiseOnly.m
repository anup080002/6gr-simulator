function evidence=diagnoseSSBNoiseOnly(outputFolder)
%DIAGNOSESSBNOISEONLY No-transmitter diagnostic, not detector qualification.
% Use the target scenario's actual receiver configuration and sampling.
% No known cell ID, transmit samples or injected variance enters SSB_Rx.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
carrier=sixgr.phy.grid.makeCarrier(cfg);
ofdm=nrOFDMInfo(carrier);
sampleCount=round(5e-3*ofdm.SampleRate);
nRx=double(cfg.phy.nRxAnt);
% Deliberately declared diagnostic episodes, not the final frozen campaign.
seeds=382150+(1:12);
rows=repmat(struct('Seed',NaN,'TransmitterPresent',false, ...
    'NumReceiveBranches',nRx,'SampleCount',sampleCount, ...
    'PSSDetected',false,'SSSDetected',false,'RecoveredPCI',NaN, ...
    'PBCHCRCPass',false,'ReceiverHestSINR_dB',NaN,'SS_SINR_dB',NaN, ...
    'SSSINRAvailable',false,'PSSMetric',NaN,'SSSMetric',NaN, ...
    'RejectionIdentifier',""),numel(seeds),1);
for k=1:numel(seeds)
    stream=RandStream('mt19937ar','Seed',seeds(k));
    noise=complex(randn(stream,sampleCount,nRx),randn(stream,sampleCount,nRx))/sqrt(2);
    rows(k).Seed=seeds(k);
    try
        [grid,sync]=sixgr.phy.dl.SSB_Rx(noise,cfg,'SampleRate_Hz',ofdm.SampleRate);
        rows(k).PSSDetected=sync.PSSDetected;
        rows(k).SSSDetected=sync.SSSDetected;
        rows(k).RecoveredPCI=sync.NCellID;
        rows(k).PSSMetric=double(sixgr.util.structGet(sync,'FreqInfo.Metric',NaN));
        rows(k).SSSMetric=sync.SSSInfo.Metric;
        pbch=sixgr.phy.dl.PBCH_Recovery(grid,sync,cfg);
        rows(k).PBCHCRCPass=pbch.Ok;
        rows(k).ReceiverHestSINR_dB=pbch.ReceiverHestSINR_dB;
        ss=sixgr.phy.refsig.measureSSSINRFromSSBGrid(grid,sync.NCellID);
        rows(k).SS_SINR_dB=ss.SS_SINR_dB;
        rows(k).SSSINRAvailable=ss.Available;
    catch cause
        if ~strcmp(cause.identifier,'sixgr:phy:ia:SSBNotDetected')
            rethrow(cause);
        end
        rows(k).RejectionIdentifier=string(cause.identifier);
    end
    fprintf('SSB_NO_TX seed=%d PSS=%d SSS=%d PBCH_CRC=%d hest_sinr_db=%.6g\n', ...
        seeds(k),rows(k).PSSDetected,rows(k).SSSDetected, ...
        rows(k).PBCHCRCPass,rows(k).ReceiverHestSINR_dB);
end
evidence=struct2table(rows);
if nargin>0
    if ~isfolder(outputFolder), mkdir(outputFolder); end
    writetable(evidence,fullfile(outputFolder,'ssb_noise_only.csv'));
end
fprintf('SSB_NO_TX_DIAGNOSTIC episodes=%d pss_detections=%d sss_detections=%d pbch_crc_passes=%d\n', ...
    height(evidence),nnz(evidence.PSSDetected),nnz(evidence.SSSDetected),nnz(evidence.PBCHCRCPass));
end
