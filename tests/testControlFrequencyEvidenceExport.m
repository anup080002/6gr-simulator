function [ok,result]=testControlFrequencyEvidenceExport()
% Declared receiver metadata -> real binders/public tables/CSV. No PHY claim.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','control_frequency_export', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder),'Never overwrite retained evidence.');
sixgr.util.ensureFolder(folder);
randomBefore=rng;
dl=cell(3,1); ul=cell(3,1); originals=cell(3,1);
for k=1:3
    e=localReceipt(k); rx=localReceiver(e); before=rx;
    p=sixgr.truth.bindPDCCHReceiverObservation(struct('Slot',k,'Status',"FAIL"), ...
        rx,struct('CandidateResults',table(0,'VariableNames',{'ErrFlag'})));
    u=sixgr.link.pucchReceiverStageEvidence(rx); u.Slot=k; u.Status="FAIL";
    assert(p.Status=="FAIL" && u.Status=="FAIL" && ...
        p.FrequencyCorrectionStatus==e.Status && u.FrequencyCorrectionStatus==e.Status);
    projected=sixgr.link.controlFrequencyEvidence(rx);
    for name=string(fieldnames(projected)).'
        assert(isequaln(p.(name),projected.(name)) && isequaln(u.(name),projected.(name)));
    end
    assert(isequaln(rx,before));
    assert(p.ReceiverFrequencyEvidenceJSON==string(jsonencode(sixgr.util.jsonSafeValue(e))) && ...
        p.ReceiverFrequencyEvidenceSHA256==string(sixgr.util.sha256Hex(char(p.ReceiverFrequencyEvidenceJSON))));
    assert(~isfield(projected,'ResidualCFO_PostCorrection_Hz'), ...
        'Same-observation estimator consistency must not become independent oscillator residual truth.');
    dl{k}=p; ul{k}=u; originals{k}=e;
end
dl=struct2table(vertcat(dl{:}),'AsArray',true);
ul=struct2table(vertcat(ul{:}),'AsArray',true);
published=localPublic(dl,ul);
for family=["pdcch_dci_public_table","pucch_uci_table"]
    T=published.(family);
    assert(height(T)==3 && isequaln(T.EstimatedCFO_Hz,[125.25;NaN;NaN]) && ...
        isequal(T.CFOCorrectionApplied,[true;false;false]));
    for k=1:3
        assert(T.ReceiverFrequencyEvidenceJSON(k)==string(jsonencode(sixgr.util.jsonSafeValue(originals{k}))) && ...
            T.FrequencyCorrectionStatus(k)==originals{k}.Status);
    end
    path=fullfile(folder,family+".csv");
    sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
    reread=sixgr.util.csvReadTable(path,'TextType','string');
    assert(height(reread)==3 && isequaln(reread.EstimatedCFO_Hz,T.EstimatedCFO_Hz) && ...
        isequal(reread.ReceiverFrequencyEvidenceJSON,T.ReceiverFrequencyEvidenceJSON) && ...
        isequal(reread.ReceiverFrequencyEvidenceSHA256,T.ReceiverFrequencyEvidenceSHA256));
end
% Historical absence is not a disabled-policy or applied-operator receipt.
rx=localReceiver(localReceipt(1)); legacy=rmfield(rx,'ReceiveFrequency');
assert(isempty(fieldnames(sixgr.link.controlFrequencyEvidence(legacy))));
p=sixgr.truth.bindPDCCHReceiverObservation(struct('Slot',1),legacy,struct());
u=sixgr.link.pucchReceiverStageEvidence(legacy); u.Slot=1;
assert(~isfield(p,'ReceiverFrequencyEvidenceJSON') && ~isfield(u,'CFOCorrectionApplied'));
old=localPublic(struct2table(p,'AsArray',true),struct2table(u,'AsArray',true));
assert(~ismember('ReceiverFrequencyEvidenceJSON',old.pdcch_dci_public_table.Properties.VariableNames) && ...
    ~ismember('CFOCorrectionApplied',old.pucch_uci_table.Properties.VariableNames));
% A late contradictory alias or raw type cannot become plausible CSV text.
for mutate=1:4
    bad=rx;
    switch mutate
        case 1, bad.EstimatedCFO_Hz=bad.EstimatedCFO_Hz+1;
        case 2, bad.ReceiveFrequency.CFOCorrectionApplied=1;
        case 3, bad.ReceiveFrequency.EstimatedCFO_Hz='A';
        case 4, bad.FrequencyCorrectionStatus="changed";
    end
    reject(@()sixgr.link.controlFrequencyEvidence(bad));
end
assert(isequaln(rng,randomBefore));
result=struct('EvidenceRoot',string(folder), ...
    'Scope',"declared_receiver_metadata_projection_not_PHY_or_accuracy",'PHYExecutions',0);
ok=true;
fprintf('CONTROL_FREQUENCY_EXPORT_PASS rows=3 channels=2 PHY_executions=0 root=%s\n',folder);
end

function out=localPublic(dl,ul)
out=sixgr.truth.buildLLSPublicOutputTables( ...
    struct('pdcch_dci_table',dl,'pucch_table',ul),sixgr.truth.llsOutputContract(), ...
    struct('logical_run_id',"declared_control_frequency_export",'run_id',1));
end
function e=localReceipt(k)
e=struct('CFOCorrectionEnabled',k~=2,'CFOEstimateAvailable',k==1, ...
    'EstimatedCFO_Hz',NaN,'EstimatedCommonFrequency_Hz',NaN, ...
    'FrequencyEstimateDomain',"received_common_frequency_not_oscillator_only", ...
    'CFOEstimateSource',"declared_receiver_metadata_fixture", ...
    'CFOCorrectionApplied',k==1,'CFOCorrectionApplied_Hz',NaN, ...
    'CFOCorrectionSource',"not_applied",'CFOCorrectionSampleOrigin',0, ...
    'CorrectionSign',-1,'CorrectionSampleCount',100,'SampleRateHz',1e6, ...
    'AlignedInputSHA256',string(repmat('a',1,64)),'CorrectedInputSHA256',string(repmat('b',1,64)), ...
    'Status',"unavailable_declared_zero_energy",'CFOObservation',struct('EstimateAvailable',k==1), ...
    'ResidualCFOObservation',struct(),'ResidualCFOEstimateAvailable',k==1, ...
    'ResidualCFOEstimatorConsistency_Hz',NaN,'ResidualCFOReusesAcquisitionObservation',k==1, ...
    'ResidualCFOEstimateRole',"not_measured");
if k==1
    e.EstimatedCFO_Hz=125.25; e.EstimatedCommonFrequency_Hz=125.25;
    e.CFOCorrectionApplied_Hz=125.25; e.CFOCorrectionSource=e.CFOEstimateSource;
    e.Status="available_declared_fixture"; e.ResidualCFOEstimatorConsistency_Hz=0.125;
    e.ResidualCFOEstimateRole="same_observation_estimator_consistency_not_independent_residual";
elseif k==2
    e.Status="disabled_by_receiver_configuration";
end
end
function rx=localReceiver(e)
timing=struct('TimingOffsetSamples',0,'AppliedTimingCorrectionSamples',0, ...
    'TimingSource',"received_reference_correlation_bounded_search", ...
    'OracleTimingUsed',false,'ReceiverZeroPaddingUsed',false);
rx=struct('ReceiveFrequency',e,'ChannelEstimationMode',"format0_noncoherent_sequence_detection", ...
    'ReceiveTiming',timing,'EffectiveGridNoiseInterferenceVariance',NaN, ...
    'DecodeNoiseInterferenceVariance',NaN,'EqualizedDecodeNoiseInterferenceVariance',NaN, ...
    'NoncoherentSequenceDetection',true,'ErrFlag',0,'Ok',true);
for name=string(fieldnames(e)).'
    if ~isstruct(e.(name)) && name~="Status", rx.(name)=e.(name); end
end
rx.FrequencyCorrectionStatus=e.Status;
end
function reject(action)
try, action(); catch cause
    assert(strcmp(cause.identifier,'sixgr:link:InvalidControlFrequencyEvidence'), ...
        'Unexpected rejection: %s',cause.identifier); return;
end
error('testControlFrequencyEvidenceExport:MissingRejection','Expected contradictory/raw-type evidence rejection.');
end
