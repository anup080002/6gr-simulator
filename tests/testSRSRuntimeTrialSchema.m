function ok=testSRSRuntimeTrialSchema()
% Exercise the exact private collector and its preallocation using two native
% received-IQ component results without original shared-reference authority.
% Isolate the unchanged local functions in a
% generated test harness: no 100-slot campaign or report recovery is needed.
% The generated source is a diagnostic artifact, never a production path.
setup6GRSimToolkit('Verbose',false);
[~,receptions]=testSRSSharedPhaseHistory();
source=fileread(which('sixgr.truth.runWaveformLinkBundle'));
starts=regexp(source,'(?m)^function ','start');
assert(numel(starts)>1);
locals=source(starts(2):end);
template=sixgr.truth.makeLinkTrialRow(receptions{1}.Config,"UL",40,45);
assert(isfield(template,'RuntimeNoiseVarianceSource') && ...
    isstring(template.RuntimeNoiseVarianceSource) && ...
    isscalar(template.RuntimeNoiseVarianceSource) && ...
    template.RuntimeNoiseVarianceSource=="", ...
    'The canonical preallocated trial must declare the SRS noise source.');
factoryCall='sixgr.truth.makeLinkTrialRow(varargin{:})';
assert(isscalar(strfind(locals,factoryCall)), ...
    'The private collector must retain its single canonical row-factory delegate.');
folder=fullfile(pwd,'results','lls','srs_runtime_trial_schema', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
% Reproduce only the absent preallocation field against the current schema.
% The exact collector remains unchanged; only its row-factory delegate calls
% a test-local wrapper which removes that one field after canonical creation.
negativeLocals=strrep(locals,factoryCall,'srsRowWithoutNoiseSource(varargin{:})');
negativeLocals=[negativeLocals sprintf([ ...
    '\nfunction row=srsRowWithoutNoiseSource(varargin)\n' ...
    'row=sixgr.truth.makeLinkTrialRow(varargin{:});\n' ...
    'row=rmfield(row,''RuntimeNoiseVarianceSource'');\nend\n'])];
writeHarness(folder,'srsCollectorBeforeRepair',negativeLocals);
writeHarness(folder,'srsCollectorAfterRepair',locals);
addpath(folder); cleanup=onCleanup(@()rmpath(folder));
try
    srsCollectorBeforeRepair(receptions{1}.Config,receptions{1}.Output);
    error('test:SRSExpectedSchemaFailure','Old collector unexpectedly accepted its row.');
catch cause
    assert(strcmp(cause.identifier,'MATLAB:heterogeneousStrucAssignment'), ...
        'Expected the retained slot-45 failure, got %s: %s',cause.identifier,cause.message);
end
rows=table();
for k=1:numel(receptions)
    out=receptions{k}.Output;
    before=rng;
    row=srsCollectorAfterRepair(receptions{k}.Config,out);
    assert(isequal(before,rng),'Reduction must not execute another channel/noise realization.');
    assert(height(row)==1 && ~row.Crash && row.Status=="FAIL" && ...
        row.ReceiverUsable && row.SRSRuntimeEvidenceUsable && ...
        ~row.ChannelNMSEReferenceAvailable && ~row.StrictOk, ...
        'Practical receiver usability must survive without false reference qualification.');
    assert(string(row.RuntimeNoiseVarianceSource)==string(out.RuntimeNoiseVarianceSource) && ...
        row.RuntimeNoiseVarianceMean==out.RuntimeNoiseVarianceMean && ...
        string(row.RuntimeNoiseVarianceDomain)==string(out.RuntimeNoiseVarianceDomain));
    for field=string(fieldnames(sixgr.link.srsPilotPhaseEvidence())).'
        assert(isequaln(row.(field),out.(field)),'Lost SRS phase evidence: %s',field);
    end
    for field=string(fieldnames(sixgr.link.srsPowerControlEvidence())).'
        assert(isequaln(row.(field),out.(field)),'Lost SRS power evidence: %s',field);
    end
    assert(isequaln(row.NMSE_dB,out.NMSE_dB) && row.MeasuredTrialSINR_dB==out.SINR_dB && ...
        row.RankEstimate==out.RankEstimate && row.WidebandCQI==out.CQI);
    assert(isequaln(row.SRS_RSRP_dB_re_UnitOccupiedRE_Es,out.SRS_RSRP_dB_re_UnitOccupiedRE_Es) && ...
        row.SRSRSRPSource==string(out.SRSRSRPSource) && ...
        row.SRSRSRPStatus==string(out.SRSRSRPStatus) && ...
        row.SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es== ...
            sixgr.truth.formatNumericEvidenceVector(out.SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es), ...
        'Original normalized SRS operands and source/status must survive the actual collector.');
    for field=["EstimatedRI","EstimatedTPMI","RISource","TPMISource", ...
            "TPMICandidateCount","TPMIMutualInformation"]
        assert(isfield(out,field) && ismember(field,string(row.Properties.VariableNames)), ...
            'test:SRSSpatialProvenanceMissing', ...
            'The production collector must retain the executed SRS estimator field %s.',field);
        if ischar(out.(field)) || isstring(out.(field))
            assert(string(row.(field))==string(out.(field)));
        else
            assert(isequaln(row.(field),out.(field)));
        end
    end
    % A default zero is not independent arrival-timing scoring. This
    % collector has received measurements only; the actual execution-plane
    % arrival reference is bound separately after practical reception.
    if ~isfield(out,'TrueTimingOffset_samples')
        assert(isnan(row.TrueTimingOffset_samples) && ...
            row.TimingScoringReferenceSource=="unavailable", ...
            'test:SRSDefaultTimingTruth', ...
            'Missing independent timing reference must not become a zero-offset truth value.');
    end
    for field=string(fieldnames(sixgr.phy.srs.measureReceivedPilotEVM())).'
        assert(isequaln(row.(field),out.(field)), ...
            'Production SRS collector lost measured pilot EVM field: %s',field);
    end
    assert(isnan(row.EVM_rms) && row.EVMSymbolCount==0 && isempty(out.PilotEVMPairs));
    for field=string(fieldnames(sixgr.link.srsReferenceEvidence())).'
        assert(isequaln(row.(field),out.(field)),'Lost explicit reference/composite status: %s',field);
    end
    for field=string(fieldnames(sixgr.truth.scoreSharedSRSAntennaPower())).'
        assert(isequaln(row.(field),out.(field)),'Lost optional power-reference status: %s',field);
    end
    assert(strlength(row.ChannelEstimateSource)>0 && ...
        row.ChannelEstimateSource==string(out.ChannelEstimateSource));
    assert(row.RuntimeStageWaveformsUsed && strlength(row.ReceiverObservationSHA256)==64 && ...
        row.ReceiverObservationSHA256==out.ReceiverObservationSHA256);
    rows=[rows;row]; %#ok<AGROW>
end
% A missing measurement stays missing; no preceding row may fill its value.
missing=receptions{2}.Output;
missing=rmfield(missing,{'RuntimeNoiseVarianceMean','RuntimeNoiseVarianceDomain','RuntimeNoiseVarianceSource'});
row=srsCollectorAfterRepair(receptions{2}.Config,missing);
assert(~row.Crash && isnan(row.RuntimeNoiseVarianceMean) && ...
    row.RuntimeNoiseVarianceDomain=="" && row.RuntimeNoiseVarianceSource=="");
missingSpatial=receptions{2}.Output;
missingSpatial=rmfield(missingSpatial,{'EstimatedRI','EstimatedTPMI','RISource', ...
    'TPMISource','TPMICandidateCount','TPMIMutualInformation'});
row=srsCollectorAfterRepair(receptions{2}.Config,missingSpatial);
assert(~row.Crash && isnan(row.EstimatedRI) && isnan(row.EstimatedTPMI) && ...
    row.RISource=="" && row.TPMISource=="" && ...
    isnan(row.TPMICandidateCount) && isnan(row.TPMIMutualInformation), ...
    'Missing estimator provenance must not be filled from configuration or another reception.');
failed=receptions{2}.Output;
failed.Ok=false; failed.StrictOk=false; failed.FailureReason="declared_negative_receiver_result";
row=srsCollectorAfterRepair(receptions{2}.Config,failed);
assert(~row.Crash && row.Status=="FAIL" && row.FailureReason==failed.FailureReason);
sixgr.util.csvWriteTable(fullfile(folder,'srs_trials.csv'),rows,'PreserveSchema',true);
saved=sixgr.util.csvReadTable(fullfile(folder,'srs_trials.csv'));
assert(height(saved)==2 && isequal(string(saved.RuntimeNoiseVarianceSource),string(rows.RuntimeNoiseVarianceSource)));
fprintf('SRS_RUNTIME_TRIAL_SCHEMA_PASS received_component_occasions=2 shared_owner=0 original_failure_reproduced=1 evidence=%s\n',folder);
ok=true;
end

function writeHarness(folder,name,locals)
% Use literal production function bodies, not rewritten collector logic.
path=fullfile(folder,[name '.m']);
[fid,msg]=fopen(path,'w'); assert(fid>=0,'%s',msg);
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'function T=%s(cfg,received)\n',name);
fprintf(fid,'T=localCollectSRSTrials(cfg,40,1,[],45,received);\nend\n');
fprintf(fid,'%s',locals);
end
