function out=calibrateH0Threshold(cfg,bundle,receiverProfile,trialCount,pfa,seed,options)
%CALIBRATEH0THRESHOLD Empirically calibrate normalized max detector under H0.
arguments
    cfg (1,1) struct
    bundle (1,1) struct
    receiverProfile (1,1) string
    trialCount (1,1) double {mustBeInteger,mustBePositive}
    pfa (1,1) double {mustBeGreaterThan(pfa,0),mustBeLessThan(pfa,1)}
    seed (1,1) double
    options.TrialOverrides (1,1) struct = struct()
end
statistics=zeros(trialCount,1);
for i=1:trialCount
    trial=localTrial("h0_"+receiverProfile+"_"+i,seed+i,receiverProfile);
    names=fieldnames(options.TrialOverrides);
    for fieldIndex=1:numel(names)
        trial.(names{fieldIndex})=options.TrialOverrides.(names{fieldIndex});
    end
    trial.TargetPresent=false;
    [row,~]=sixgr.isac.runJointWaveformTrial(cfg,bundle,trial);
    statistics(i)=row.PeakPower/max(row.NoiseFloorPower,realmin);
end
ordered=sort(statistics,"ascend");
quantileIndex=max(1,min(trialCount,ceil((1-pfa)*trialCount)));
multiplier=ordered(quantileIndex);
decisions=statistics>multiplier;
[ciLow,ciHigh]=sixgr.lls.stats.wilsonInterval(nnz(decisions),trialCount,.95);
qualified=trialCount>=ceil(double(cfg.metrics.minimumExpectedFalseAlarmsForQualification)/pfa);
out=struct("ReceiverProfile",receiverProfile,"TrialCount",trialCount, ...
    "RequestedPFA",pfa,"ThresholdToNoiseFloor",multiplier, ...
    "EmpiricalPFA",mean(decisions),"PFACILow",ciLow,"PFACIHigh",ciHigh, ...
    "PublicationQualified",qualified,"Statistics",statistics, ...
    "EvidenceClass","executed_h0_common_waveform_receiver_statistics");
end

function trial=localTrial(id,seed,receiver)
trial=struct("TrialId",char(id),"Seed",double(seed),"WaveformSeed",double(seed), ...
    "DelayOverCP",1,"NormalizedDoppler",.01,"SensingMode","trp_monostatic", ...
    "CollisionRatioPercent",0,"CollisionResponse","share_reuse", ...
    "TDDPattern","all_dl","TargetPresent",false,"UseGeometryDelay",false, ...
    "PortProfile","single_port","ReceiverProfile",char(receiver), ...
    "CoherentSymbols",14,"CollisionMaskProfile","random_isolated", ...
    "SequenceVariant","default");
end
