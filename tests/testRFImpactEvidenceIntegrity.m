function result=testRFImpactEvidenceIntegrity()
% Actual bounded RF-kernel observations, not NR receiver/BLER qualification.
% No full 768-case matrix, waveform link runner, decoder or campaign.
source=string(fullfile(pwd,'tests','vectors','rf'));
root=string(fullfile(pwd,'results','validation','rf_impact_evidence_integrity', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))));
assert(~isfolder(root),'RF:ImpactTestDestination','Refuse evidence overwrite.'); mkdir(root);
vectors=fullfile(root,'original_vector_subset'); mkdir(vectors);
matrix=readtable(fullfile(source,'rf_impact_experiment_matrix.csv'),'TextType','string','VariableNamingRule','preserve');
originalHash=string(sixgr.util.sha256File(fullfile(source,'rf_impact_experiment_matrix.csv')));
for name=["rf_impact_analysis_families.csv","rf_impact_acceptance_rules.csv", ...
        "desired_rf_impact_csv_contract.csv","desired_rf_impact_image_contract.csv"]
    copyfile(fullfile(source,name),fullfile(vectors,name));
end
matrixPath=fullfile(vectors,'rf_impact_experiment_matrix.csv');
subset=matrix(ismember(matrix.FamilyID,["F34","F35"]),:); writetable(subset,matrixPath);
before=rng;
e=sixgr.rf.runtime.RFImpactEvidenceBuilder.build(matrixPath,[11 23 47 89 131 197],0.95, ...
    'SelectedFamilyIDs',["F34","F35"]);
assert(isequal(before,rng),'RF:ImpactTestRNG','Bounded input generators may not consume global RNG.');
r=e.rf_impact_raw_trials;
assert(height(r)==24&&height(e.rf_impact_data_converters)==24&&numel(unique(r.ExperimentID))==24);
assert(isequal(r.ExperimentID,subset.ExperimentID)&&all(r.ADCResultAvailable));
assert(all(r.Kernel=="ADCModel.quantize")&&all(r.ReferencePlane=="normalized_complex_time_waveform_kernel_input_output"));
assert(all(r.ObservationMode=="executed_waveform_kernel")&&~any(r.ReceiverExecuted|r.TransportBlockDecoderExecuted));
assert(all(r.RequestedFeatureStatus=="unqualified_component_kernel_only")&&~any(e.rf_impact_summary.FeatureQualified));
assert(all(isnan(r.BLER))&&~any(r.BLERAvailable)&&all(r.BLERStatus=="unavailable_no_transport_block_decoder"));
assert(all(isnan(r.CFOError_Hz))&&all(isnan(r.TimingError_samples))&&all(isnan(r.FalseLock)));
assert(isempty(e.rf_impact_interactions)&&~any(e.rf_impact_runtime.ParallelExecutionPerformed));
assert(all(isnan(e.rf_impact_runtime.PeakMemory_MB))&&all(strlength(e.rf_impact_runtime.ParallelDigest)==0));
for k=1:height(r)
    o=e.ObservationOperands{k}; x=double(o.Input); y=double(o.Output); q=o.ReturnedEvidence;
    assert(q.Bits==r.Bits(k)&&q.FullScale==r.FullScale(k)&&q.ClippingRatio==r.ClippingRatio(k));
    if r.Role(k)=="baseline", assert(r.Bits(k)==14&&r.FullScale(k)==1.2);
    else, assert(r.Bits(k)==12-(str2double(extractAfter(r.FamilyID(k),'F'))-32)&&r.FullScale(k)==0.6); end
    reference=sum(abs(x(:)).^2); errorEnergy=sum(abs(y(:)-x(:)).^2);
    assert(r.ReferenceEnergy(k)==reference&&r.ErrorEnergy(k)==errorEnergy);
    assert(r.Value(k)==100*sqrt(errorEnergy/reference)&&r.Value(k)==r.WaveformRelativeRMSError_pct(k));
    assert(isequaln(r.WaveformSignalToErrorRatio_dB(k),10*log10(reference/errorEnergy)));
    assert(r.ClippingRatio(k)==mean(double(q.Clipped(:)))&&r.ADCErrorVariance(k)==q.ErrorVariance);
    assert(r.InputSHA256(k)==string(sixgr.phy.waveform.WaveformHash.runtimeArray(o.Input)));
    assert(r.OutputSHA256(k)==string(sixgr.phy.waveform.WaveformHash.runtimeArray(o.Output)));
    n=numel(y); f=(-n/2:n/2-1)'*r.SampleRate_Hz(k)/n;
    spectrum=abs(fftshift(fft(y(:),n))).^2/n^2;
    a=sum(spectrum(f>=r.AssignedBandLow_Hz(k)&f<=r.AssignedBandHigh_Hz(k)));
    b=sum(spectrum(abs(f)>=r.AdjacentAbsBandLow_Hz(k)&abs(f)<=r.AdjacentAbsBandHigh_Hz(k)));
    assert(a==r.AssignedBandPower(k)&&b==r.AdjacentBandPower(k));
    assert(isequaln(r.MeasuredBandPowerRatio_dB(k),10*log10(a/b)));
end
rules=e.rf_impact_rule_evaluation;
assert(any(~rules.Evaluated)&all(isnan(rules.Passed(~rules.Evaluated))));
assert(all(rules.Status(~rules.Evaluated)=="not_evaluated"));
assert(~any(e.rf_impact_pairwise_effects.StatisticallyQualified));
assert(all(isnan(e.rf_impact_pairwise_effects.CILower))&&all(isnan(e.rf_impact_pairwise_effects.PValue)));

% The same original pair records in a different order must not change
% paired differences or the observation values. This is a second actual
% bounded kernel execution, not an assertion of parallel execution.
shuffled=subset([2:2:height(subset),1:2:height(subset)],:); writetable(shuffled,matrixPath);
again=sixgr.rf.runtime.RFImpactEvidenceBuilder.build(matrixPath,[11 23 47 89 131 197],0.95, ...
    'SelectedFamilyIDs',["F34","F35"]);
assert(isequaln(sortrows(r,'ExperimentID'),sortrows(again.rf_impact_raw_trials,'ExperimentID')));
assert(isequaln(e.rf_impact_pairwise_effects,again.rf_impact_pairwise_effects));
assert(isequal(before,rng));

% Reject malformed source pairs before any kernel execution.
wrong=subset; wrong.Seed(2)=23; writetable(wrong,matrixPath);
localError(@()localBuild(matrixPath,["F34","F35"]),'RF:ImpactPairIdentity');
writetable(subset(2:end,:),matrixPath);
localError(@()localBuild(matrixPath,["F34","F35"]),'RF:ImpactPairIdentity');
writetable([subset;subset(1,:)],matrixPath);
localError(@()localBuild(matrixPath,["F34","F35"]),'RF:ImpactPairIdentity');
writetable(subset,matrixPath);

% Invalid contracts must fail before creating any publication, while legal
% small comma-delimited contracts retain semicolon list values as text.
localTestContractReaders(e,vectors,root);
publication=fullfile(root,'published_original_observations');
s=sixgr.rf.runtime.RFImpactArtifactExporter.export(e,vectors,publication);
originalContract=fullfile(root,'published_original_contract');
localSnapshotContract(vectors,originalContract,e.Metadata.ExperimentMatrixSHA256);
assert(s.PublicationPassed&&~s.Passed&&~s.AcceptanceCriteriaPassed&&~isempty(s.UnavailableMandatoryRules));
persisted=sixgr.util.csvReadTable(fullfile(publication,'rf_impact_data_converters.csv'),'TextType','string');
assert(height(persisted)==24&&isequal(persisted.ExperimentID,r.ExperimentID));
for name=["Bits","FullScale","ClippingRatio","ADCErrorVariance","WaveformRelativeRMSError_pct", ...
        "WaveformSignalToErrorRatio_dB","ReferenceEnergy","ErrorEnergy","BLER"]
    assert(isequaln(persisted.(name),r.(name)),'RF:ImpactTestRoundtrip','Changed %s.',name);
end
for name=["InputSHA256","OutputSHA256","KernelConfigJSON","KernelConfigSHA256", ...
        "MeasurementReceiptJSON","MeasurementReceiptSHA256"]
    assert(isequal(persisted.(name),r.(name)));
end
assert(all(persisted.SourceOperandsMATSHA256==s.OperandArchiveSHA256));
saved=load(fullfile(publication,s.OperandArchive));
assert(isequaln(saved.Observations,e.ObservationOperands));
audit=s.ImageAudit; absent=audit.ImageFile=="rf_impact_adc_bits.png";
assert(nnz(absent)==1&&audit.PlottedRowCount(absent)==0&& ...
    startsWith(audit.Status(absent),"unavailable")&&~isfile(fullfile(publication,'rf_impact_adc_bits.png')));
for image=["rf_impact_converter_bits_error.png","rf_impact_converter_fullscale_clipping.png"]
    a=audit(audit.ImageFile==image,:); assert(height(a)==1&&a.PlottedRowCount==24&&a.SourceRowCount==24);
    points=sixgr.util.csvReadTable(fullfile(publication,a.PointsCSV),'TextType','string');
    assert(isequal(points.ExperimentID,r.ExperimentID)&&numel(unique(points.ExperimentID))==24);
    assert(isequaln(points.PlotX,r.(a.XColumn))&&isequaln(points.PlotY,r.(a.YColumn)));
    assert(all(points.ADCResultAvailable)&&all(strlength(points.PlotSeriesIdentityJSON)>0));
    assert(string(sixgr.util.sha256File(fullfile(publication,image)))==a.PNGSHA256);
    assert(string(sixgr.util.sha256File(fullfile(publication,a.PointsCSV)))==a.PointsCSVSHA256);
end
localError(@()sixgr.rf.runtime.RFImpactArtifactExporter.export(e,vectors,publication),'RF:ImpactArtifactExists');
bad=e; bad.rf_impact_raw_trials.BLER(1)=0.01;
localError(@()sixgr.rf.runtime.RFImpactArtifactExporter.export(bad,vectors,fullfile(root,'reject_fake_bler')),'RF:ImpactOperandClosure');
bad=e; bad.ObservationOperands{1}.Output(1)=bad.ObservationOperands{1}.Output(1)+1;
localError(@()sixgr.rf.runtime.RFImpactArtifactExporter.export(bad,vectors,fullfile(root,'reject_changed_operand')),'RF:ImpactOperandClosure');
bad=e; bad.ObservationOperands{1}.ReturnedEvidence.Bits=8;
localError(@()sixgr.rf.runtime.RFImpactArtifactExporter.export(bad,vectors,fullfile(root,'reject_changed_adc_result')),'RF:ImpactOperandClosure');
bad=e; bad.rf_impact_raw_trials.Value(1)=bad.rf_impact_raw_trials.Value(1)+0.1;
resealed=removevars(bad.rf_impact_raw_trials(1,:),{'MeasurementReceiptJSON','MeasurementReceiptSHA256'});
token=string(jsonencode(sixgr.util.jsonSafeValue(table2struct(resealed))));
sha=string(sixgr.util.sha256Hex(uint8(unicode2native(char(token),'UTF-8'))));
bad.rf_impact_raw_trials.MeasurementReceiptJSON(1)=token; bad.rf_impact_raw_trials.MeasurementReceiptSHA256(1)=sha;
bad.ObservationOperands{1}.MeasurementReceiptJSON=token; bad.ObservationOperands{1}.MeasurementReceiptSHA256=sha;
localError(@()sixgr.rf.runtime.RFImpactArtifactExporter.export(bad,vectors,fullfile(root,'reject_resealed_metric_copy')),'RF:ImpactOperandClosure');
bad=e; bad.rf_impact_data_converters=[bad.rf_impact_data_converters;bad.rf_impact_data_converters(1,:)];
localError(@()sixgr.rf.runtime.RFImpactArtifactExporter.export(bad,vectors,fullfile(root,'reject_replicated_observation')),'RF:ImpactContract');

% A real named metric and numerical rule are evaluated; an unresolved
% profile limit remains unknown. Neither is replaced by a finiteness PASS.
rulePath=fullfile(vectors,'rf_impact_acceptance_rules.csv');
ruleFixture=localReadRuleFixture(rulePath);
at=find(ruleFixture.FamilyID=="F34");
assert(isscalar(at),'RF:ImpactTestRuleFixture','Preserve exactly one original F34 rule.');
ruleFixture.Metric(at)="PairedEffect:WaveformRelativeRMSError_pct";
ruleFixture.Operator(at)="<="; ruleFixture.Threshold(at)="-1"; writetable(ruleFixture,rulePath);
small=subset(subset.FamilyID=="F34"&endsWith(subset.PairID,'-P01'),:); writetable(small,matrixPath);
failedRule=localBuild(matrixPath,"F34"); check=failedRule.rf_impact_rule_evaluation;
check=check(check.FamilyID=="F34",:);
assert(height(check)==1&&check.Evaluated&&check.Passed==0&&check.Status=="FAIL");
ruleFixture.Threshold(at)="profile_limit"; writetable(ruleFixture,rulePath);
unknownRule=localBuild(matrixPath,"F34"); check=unknownRule.rf_impact_rule_evaluation;
check=check(check.FamilyID=="F34",:);
assert(height(check)==1&&~check.Evaluated&&isnan(check.Passed)&&check.Status=="not_evaluated");
copyfile(fullfile(source,'rf_impact_acceptance_rules.csv'),rulePath,'f');

% One original pair for each remaining distinct execution branch: actual
% returned/array operands, not fabricated family-specific success claims.
branchIDs=["F01","F09","F11","F14","F19","F24","F25","F30","F41","F43","F49","F50","F53","F62"];
branchRows=matrix(ismember(matrix.FamilyID,branchIDs)&endsWith(matrix.PairID,'-P01'),:);
assert(height(branchRows)==2*numel(branchIDs)); writetable(branchRows,matrixPath);
% A bare absolute metric may not silently mean treatment-minus-baseline.
% Both actual F50 band ratios exceed this limit while their difference does
% not: the old ambiguous rule would falsely pass this declared boundary.
% This 10 dB engineering test boundary is NOT an NR/RF acceptance limit.
% The metric uses one FFT over four OFDM blocks, including their boundary
% leakage; it does not assert an ideal single-symbol out-of-band null.
bareMetricBoundary_dB=10;
ruleFixture=localReadRuleFixture(rulePath);
at=find(ruleFixture.FamilyID=="F50");
assert(isscalar(at),'RF:ImpactTestRuleFixture','Preserve exactly one original F50 rule.');
ruleFixture.Metric(at)="MeasuredBandPowerRatio_dB";
ruleFixture.Operator(at)="<="; ruleFixture.Threshold(at)=string(bareMetricBoundary_dB);
writetable(ruleFixture,rulePath);
branches=localBuild(matrixPath,branchIDs);
% Persist the actual source operands and exact contracts before assertions
% about their values. A failed boundary must not erase the observed source.
imageContract=readtable(fullfile(vectors,'desired_rf_impact_image_contract.csv'),'TextType','string','VariableNamingRule','preserve');
imageContract=imageContract(ismember(imageContract.ImageFile, ...
    ["rf_impact_power_control_target.png","rf_impact_declared_spectral_band_ratio.png"]),:);
imageContract.ExpectedTitle=imageContract.ExpectedTitle+"; original values, not ""NR criteria""";
writetable(imageContract,fullfile(vectors,'desired_rf_impact_image_contract.csv'));
branchPublication=sixgr.rf.runtime.RFImpactArtifactExporter.export(branches,vectors,fullfile(root,'published_branch_observations'));
branchContract=fullfile(root,'published_branch_contract');
localSnapshotContract(vectors,branchContract,branches.Metadata.ExperimentMatrixSHA256);
ambiguous=branches.rf_impact_rule_evaluation;
ambiguous=ambiguous(ambiguous.FamilyID=="F50",:);
actual=branches.rf_impact_pairwise_effects;
actual=actual(actual.FamilyID=="F50",:);
assert(actual.BaselineMean>bareMetricBoundary_dB&&actual.TreatmentMean>bareMetricBoundary_dB&& ...
    actual.Effect<bareMetricBoundary_dB);
assert(height(ambiguous)==1&&~ambiguous.Evaluated&&isnan(ambiguous.Observed)&& ...
    isnan(ambiguous.Passed)&&ambiguous.Status=="not_evaluated");
assert(height(branches.rf_impact_raw_trials)==height(branchRows)&&~any(branches.rf_impact_raw_trials.BLERAvailable));
for k=1:height(branchRows)
    o=branches.ObservationOperands{k}; r0=branches.rf_impact_raw_trials(k,:);
    if isempty(o.Output)
        assert(r0.SampleCount==0&&isnan(r0.OutputMeanPower)&&contains(r0.ReferencePlane,'analytical'));
    else
        assert(r0.ReferenceEnergy==sum(abs(double(o.Input(:))).^2));
        assert(r0.ErrorEnergy==sum(abs(double(o.Output(:))-double(o.Input(:))).^2));
    end
    if r0.FamilyID=="F14", assert(r0.AppliedPhaseRMS_rad==o.ReturnedEvidence.IntegratedRMS_rad); end
    if r0.FamilyID=="F53"
        assert(r0.RequestedPower_dBm==o.ReturnedEvidence.RequestedPower_dBm&& ...
            r0.AppliedPowerTarget_dBm==o.ReturnedEvidence.ClampedPowerTarget_dBm);
        assert(r0.Kernel=="DeclaredAdditivePowerBudgetEquation"&& ...
            ~o.ReturnedEvidence.ReceiverMeasurementUsed&&~o.ReturnedEvidence.DecodedControlUsed&& ...
            ~o.ReturnedEvidence.WaveformPowerApplied&&~isfield(o.Configuration,'MeasuredPathloss_dB'));
        cfg=o.Configuration;
        expected=cfg.P0_dBm+10*log10(2^cfg.Mu*cfg.MRB)+cfg.Alpha*cfg.AssumedPathloss_dB+cfg.DeltaTF_dB+cfg.AssumedTPCOffset_dB;
        assert(r0.RequestedPower_dBm==expected&&r0.AppliedPowerTarget_dBm==min(cfg.PCMAX_dBm,expected));
    end
end
assert(branchPublication.PublicationPassed&&~branchPublication.Passed);
assert(height(branchPublication.ImageAudit)==2&& ...
    isequal(branchPublication.ImageAudit.Title,imageContract.ExpectedTitle)&& ...
    isequal(branchPublication.ImageAudit.SeriesColumns,imageContract.SeriesColumns));
powerPlot=branchPublication.ImageAudit(branchPublication.ImageAudit.ImageFile=="rf_impact_power_control_target.png",:);
assert(powerPlot.SourceRowCount==4&&powerPlot.AvailableRowCount==2&&powerPlot.PlottedRowCount==2);
assert(originalHash==string(sixgr.util.sha256File(fullfile(source,'rf_impact_experiment_matrix.csv'))));
result=struct('Passed',true,'Root',root,'OriginalContract',originalContract,'BranchContract',branchContract, ...
    'ConverterExecutions',24,'ReorderedExecutions',24, ...
    'OtherBranchExecutions',height(branchRows),'RuleBoundaryExecutions',4,'WaveformLinkExecutions',0,'TransportBlockDecodes',0, ...
    'Scope',"actual_bounded_RF_kernels_and_export_contract_not_link_or_device_qualification");
fprintf('RF_IMPACT_EVIDENCE_INTEGRITY_PASS original_converter_rows=24 padding=0 BLER_population=0 root=%s\n',root);
end

function e=localBuild(path,ids)
e=sixgr.rf.runtime.RFImpactEvidenceBuilder.build(path,[11 23 47 89 131 197],0.95,'SelectedFamilyIDs',ids);
end
function rules=localReadRuleFixture(path)
% Mixed profile tokens/numerical limits must not make automatic detection
% skip the original family-rule prefix or convert unresolved limits to NaN.
options=detectImportOptions(path,'Delimiter',',','VariableNamingRule','preserve');
options.DataLines=[2 Inf];
options=setvartype(options,options.VariableNames,'string');
rules=readtable(path,options);
assert(nnz(rules.FamilyID=="F34")==1&&nnz(rules.FamilyID=="F50")==1, ...
    'RF:ImpactTestRuleFixture','Retain the complete original family-rule population.');
end
function localTestContractReaders(e,vectors,root)
for stem=["desired_rf_impact_csv_contract","desired_rf_impact_image_contract"]
    path=fullfile(vectors,stem+".csv");
    backup=fullfile(root,stem+"_before_parser_negatives.csv"); copyfile(path,backup);
    restore=onCleanup(@()copyfile(backup,path,'f'));
    options=detectImportOptions(path,'Delimiter',',','VariableNamingRule','preserve');
    options.VariableNamesLine=1; options.DataLines=[2 Inf];
    options=setvartype(options,options.VariableNames,'string');
    original=readtable(path,options);
    header=string(original.Properties.VariableNames); body=table2cell(original);
    for kind=["unknown_header","missing_header","duplicate_header","duplicate_target", ...
            "short_row","extra_column","extra_data_field"]
        names=header; values=body;
        switch kind
            case "unknown_header", names(end)="UnknownDeclaredColumn";
            case "missing_header", names=names(1:end-1); values=values(:,1:end-1);
            case "duplicate_header", names(end)=names(1);
            case "duplicate_target", values=[values;values(1,:)];
            case "short_row", values{1,end}="";
            case "extra_column", names=[names,"UnexpectedColumn"]; values=[values,repmat({"extra"},size(values,1),1)];
            case "extra_data_field", values=[values,repmat({"extra"},size(values,1),1)];
        end
        if kind=="extra_data_field"
            writecell(cellstr(names),path,'Delimiter',',');
            writecell(values,path,'Delimiter',',','WriteMode','append');
        else
            writecell([cellstr(names);values],path,'Delimiter',',');
        end
        destination=fullfile(root,"reject_"+stem+"_"+kind);
        localError(@()sixgr.rf.runtime.RFImpactArtifactExporter.export(e,vectors,destination),'RF:ImpactContractSchema');
        assert(~isfolder(destination),'RF:ImpactTestContractPublication', ...
            'Malformed original contract must fail before any publication.');
    end
    clear restore
    assert(string(sixgr.util.sha256File(path))==string(sixgr.util.sha256File(backup)));
end
end
function localSnapshotContract(source,destination,expectedMatrixSHA256)
assert(~isfolder(destination),'RF:ImpactTestDestination','Refuse contract snapshot overwrite.');
mkdir(destination);
for name=["rf_impact_experiment_matrix.csv","rf_impact_analysis_families.csv", ...
        "rf_impact_acceptance_rules.csv","desired_rf_impact_csv_contract.csv","desired_rf_impact_image_contract.csv"]
    copyfile(fullfile(source,name),fullfile(destination,name));
    assert(string(sixgr.util.sha256File(fullfile(source,name)))== ...
        string(sixgr.util.sha256File(fullfile(destination,name))),'RF:ImpactTestContractSnapshot', ...
        'Contract snapshot bytes changed: %s.',name);
end
assert(string(sixgr.util.sha256File(fullfile(destination,'rf_impact_experiment_matrix.csv')))== ...
    expectedMatrixSHA256,'RF:ImpactTestContractSnapshot','Retain the exact original executed matrix bytes.');
end
function localError(f,identifier)
try, f(); catch ME, assert(strcmp(ME.identifier,identifier),'Expected %s; received %s.',identifier,ME.identifier); return; end
error('RF:ImpactTestExpectedRejection','Expected %s.',identifier);
end
