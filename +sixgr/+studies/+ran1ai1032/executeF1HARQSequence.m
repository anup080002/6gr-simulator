function out=executeF1HARQSequence(study,caseRow,snrHistory,seeds)
% Physical conditional HARQ experiment, not scheduled-network timing truth.
% Every attempted RV uses the original TB and accumulated mother-code LLRs.
% Independent attempt realizations are explicit, NOT a correlated channel.
arguments
    study (1,1) struct
    caseRow table
    snrHistory (1,:) double {mustBeFinite}
    seeds (1,:) double {mustBeInteger,mustBePositive}
end
p=study.harq.calibration;
assert(string(p.channel_evolution)=="independent_attempt_realizations" && ...
    string(p.feedback_assumption)=="ideal_error_free_delayed_control", ...
    'sixgr:ran1ai1032:HARQCalibrationPolicy','Select the explicit independent-attempt/ideal-feedback experiment.');
rv=double(study.harq.rv_sequence(:).');
assert(numel(snrHistory)==numel(rv) && numel(seeds)==numel(rv) && ...
    numel(unique(seeds))==numel(seeds), ...
    'sixgr:ran1ai1032:HARQCalibrationHistory','One SNR and independent seed per configured RV is required.');
retained=struct(); rows=table(); resolved=cell(0,1);
for k=1:numel(rv)
    cfg=sixgr.studies.ran1ai1032.buildF1RuntimeConfig(study,caseRow,snrHistory(k),seeds(k));
    resolved{end+1,1}=cfg; %#ok<AGROW>
    retained.RV=rv(k);
    [trial,next]=sixgr.studies.ran1ai1032.executeF1PUSCHTrial(cfg,study,retained);
    row=trial.TrialTable;
    if k>1
        assert(row.TransportBlockSHA256==rows.TransportBlockSHA256(1) && ...
            row.TBSize_bits==rows.TBSize_bits(1) && row.HARQSoftCombiningApplied, ...
            'sixgr:ran1ai1032:HARQCalibrationIdentity','Retransmission changed TB identity or discarded prior evidence.');
    end
    row.Attempt=k; row.PriorAttemptsFailed=all(~rowsLogical(rows));
    row.SNRHistory_dB=string(jsonencode(snrHistory(1:k)));
    row.RVHistory=string(jsonencode(rv(1:k)));
    row.ChannelEvolution=string(p.channel_evolution);
    row.FeedbackAssumption=string(p.feedback_assumption);
    row.WaveformExecuted=true;
    row.PrimaryStudyAccepted=false;
    row.ResolvedConfigSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(sixgr.util.jsonSafeValue(cfg)),'UTF-8'))));
    rows=[rows;row]; %#ok<AGROW>
    retained=next;
    if row.CRCPass, break; end
end
out=struct('TrialTable',rows,'Delivered',logical(rows.CRCPass(end)), ...
    'AttemptsExecuted',height(rows),'UniqueDeliveredBits', ...
    double(rows.TBSize_bits(1))*double(rows.CRCPass(end)), ...
    'SourceClassification',"executed_waveform_HARQ_independent_attempts", ...
    'PrimaryStudyAccepted',false,'ResolvedConfigurations',{resolved});
end
function values=rowsLogical(rows)
values=false(0,1);
if ~isempty(rows), values=logical(rows.CRCPass); end
end
