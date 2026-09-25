function rows=diagnosePUCCHFormat2SymbolDetection(configPath,outputRoot)
% Component observations only: NOT waveform/timing or detector qualification.
% Reuse the installed CSI/SR allocation and frozen YAML threshold. No fitting.
assert(~isfolder(outputRoot),'test:EvidenceExists','Preserve earlier diagnostics.');
scenario=sixgr.lls6g.config.loadScenarioConfig(configPath);
cfg=sixgr.lls6g.buildInternalConfig(scenario,outputRoot);
id=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',cfg.lls6g.users.rnti_start,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
assert(isscalar(rrc.Data.CSIResources),'test:AmbiguousCSIResource','One installed CSI resource required.');
resource=rrc.resourceByID(rrc.Data.CSIResources);
assert(resource.Format==2,'test:Format2Required','This diagnostic covers Format 2 only.');
report=sixgr.phy.mimo.CSIReportConfiguration( ...
    cfg.phy.csi.reportConfiguration,cfg.phy.csi.reportConfigurationEpoch);
% Select one configured reporting occasion; no access/received timing claim.
slot=double(cfg.phy.csi.reportOffsetSlots)+1;
sr=sixgr.truth.buildConfiguredSRCalendar(cfg,ue,slot,slot);
overlap=sixgr.truth.resolveConfiguredSROverlap(sr,slot, ...
    [resource.Data.StartSymbol resource.Data.NumSymbols],0);
A=report.part1BitCount()+report.part2BitCount()+overlap.EncodedBitCount;
assert(A>=3 && A<=11,'test:SmallBlockRequired','Configured CSI/SR must use 3--11 small-block bits.');
carrier=sixgr.phy.grid.makeCarrier(cfg);
carrier.NFrame=floor((slot-1)/double(carrier.SlotsPerFrame));
carrier.NSlot=mod(slot-1,double(carrier.SlotsPerFrame));
pucch=resource.toolboxConfig();
[~,info]=nrPUCCHIndices(carrier,pucch);
[threshold,source]=sixgr.phy.pucch.resolveDetectionThreshold( ...
    struct('Format',resource.Format),cfg.phy.pucch.receiverDetectionThresholds);
stream=RandStream('mt19937ar','Seed',double(cfg.run.seed));
bits=int8(randi(stream,[0 1],A,1));
coded=nrUCIEncode(bits,info.G);
signal=nrPUCCH(carrier,pucch,coded);
% Unit QPSK symbols, not configured RF watts or an executed sample-domain SNR.
variance=mean(abs(signal).^2)/10^(double(cfg.channel.snr_dB)/10);
noise=sqrt(variance/2)*(randn(stream,size(signal))+1i*randn(stream,size(signal)));
unrelated=nrSymbolModulate(int8(randi(stream,[0 1],2*numel(signal),1)),'QPSK');
inputs={signal+noise,noise,unrelated+noise};
names=["coded_signal_present","noise_only","unrelated_qpsk_interference"];
rows=table();
for k=1:numel(inputs)
    symbols=inputs{k};
    [soft,~,correlation]=nrPUCCHDecode(carrier,pucch,A,symbols,variance, ...
        'DetectionThreshold',threshold);
    decoded=sixgr.phy.pucch.UCIDecoder.decode(soft{1},A);
    energyRatio=mean(abs(symbols).^2)/variance;
    metric=sixgr.phy.pucch.PUCCHDetector.selectMetric( ...
        resource.Format,false,correlation,energyRatio,A);
    decision=sixgr.phy.pucch.PUCCHDetector.decide(resource.Format,metric,threshold,decoded.Bits);
    receiverAccepted=decision.Detected && numel(decoded.Bits)==A && decoded.CRCPassed;
    if k==1
        assert(receiverAccepted && isequal(decoded.Bits,bits), ...
            'test:SignalDecodeFailed','Retain a failure, never substitute transmitted payload bits.');
    end
    row=table(names(k),A,numel(symbols),variance,threshold,string(source),correlation, ...
        energyRatio,metric,numel(decoded.Bits),receiverAccepted,decoded.CRCApplicable, ...
        'VariableNames',{'Case','PayloadBits','SymbolCount','SymbolNoiseVariance','Threshold', ...
        'ThresholdSource','ToolboxCorrelationMetric','EnergyRatio','SelectedMetric', ...
        'DecodedBitCount','ReceiverAccepted','CRCApplicable'});
    rows=[rows;row]; %#ok<AGROW>
end
if ~isfolder(outputRoot), mkdir(outputRoot); end
writetable(rows,fullfile(outputRoot,'symbol_detection_diagnostic.csv'));
save(fullfile(outputRoot,'observations.mat'),'inputs','bits','rows','carrier','pucch','cfg');
sixgr.util.jsonWrite(fullfile(outputRoot,'scope.json'),struct( ...
    'Scope','configured_symbol_domain_component_not_waveform_or_statistical_qualification', ...
    'Scenario',string(configPath),'Seed',cfg.run.seed,'MATLABVersion',version, ...
    'ThresholdTuned',false,'PhysicalTimingAcquired',false,'QualificationPassed',false));
disp(rows);
end
