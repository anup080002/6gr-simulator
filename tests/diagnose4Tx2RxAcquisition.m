function out=diagnose4Tx2RxAcquisition()
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
folder=fullfile(pwd,'results','lls','acquisition_4tx2rx_m10db', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(s,folder);
out=sixgr.link.runCellSearch_MIB_SIB1(cfg,'NumSubframes',5,'UseRuntimeChannel',true);
names={'Ok','Crash','Status','FailureReason','PSSDetected','SSSDetected','MIBDecoded','SIB1StrictOk', ...
    'PSSNormalizedMetric','PSSDetectionThreshold','SSSNormalizedMetric','SSSDetectionThreshold'};
row=struct();
for k=1:numel(names)
    if isfield(out,names{k}), row.(names{k})=out.(names{k}); end
end
writetable(struct2table(row,'AsArray',true),fullfile(folder,'acquisition.csv'));
save(fullfile(folder,'acquisition.mat'),'out','cfg','-v7.3');
disp(row); fprintf('ACQUISITION_OUTPUT=%s\n',folder);
end
