function ok=testDirectLinkEnergyReceiptPropagation(retainedFolder)
% One real direct DL and UL attempt. Not shared/control or NR performance
% qualification. Optional retainedFolder replays ONLY report publication
% from this test's original saved config/rows, into a new output directory.
% Root serializes this affected physical test.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
oldState=rng; cleanup=onCleanup(@()rng(oldState)); %#ok<NASGU>
if nargin>0
    inputs=loadOriginalReportInputs(retainedFolder);
    publishAndCheck(inputs,false);
    ok=true; return;
end
startedUTC=string(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
started=tic;
cfg=sixgr.config.defaultConfig(); cfg=withCanonicalSchedulerTiming(cfg);
cfg.run.shortRun=true; cfg.run.noiseOperatingMode='standalone_awgn_snr_argument';
cfg.run.interferenceExecutionMode='none';
cfg.integration.run_mode='FIXED_SNR_SWEEP'; cfg.integration.configured_snr_is_link_authority=true;
cfg.outputs.saveCSV=false; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true; cfg.channel.awgnReferenceREEnergy=.25;
cfg.phy.ssb.enable=false; cfg.phy.csirs.enable=false; cfg.phy.csirs.enabled=false;
folder=fullfile(pwd,'results','validation','direct_link_energy_receipts', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder)); mkdir(folder);
layout=sixgr.report.resultLayout(folder);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.ensureFolder(layout.MetaDir);
allObservations=table();
originalRows=cell(2,1); sourcePaths=strings(2,1); sourceHashes=strings(2,1);
inputConfigPaths=strings(2,1); inputConfigHashes=strings(2,1);
attemptIndex=0;
for direction=["DL","UL"]
    attemptIndex=attemptIndex+1;
    key='pdsch'; if direction=="UL", key='pusch'; end
    cfg.phy.(key).executionProfile='phy_calibration';
    cfg.phy.(key).nLayers=1; cfg.phy.(key).numLayers=1;
    cfg.phy.(key).mcsIndex=4; cfg.phy.(key).mcsTable='qam64_table1';
    cfg.phy.(key).modulation='QPSK'; cfg.phy.(key).codeRate=308/1024;
    cfg.phy.(key).prbSet=0:5; cfg.phy.(key).symbolAllocation=[2 12];
    cfg.phy.(key).mappingType='A'; cfg.phy.(key).dmrs.portSet=0;
    % Retain the original caller-owned configuration BEFORE the attempt;
    % never recover missing configuration from a later measured row.
    originalInputConfig=cfg;
    inputConfigPaths(attemptIndex)=fullfile(layout.MetaDir,lower(direction)+'_original_input_cfg.mat');
    assert(~isfile(inputConfigPaths(attemptIndex)));
    save(inputConfigPaths(attemptIndex),'originalInputConfig','-v7');
    inputConfigHashes(attemptIndex)=string(sixgr.util.sha256File(inputConfigPaths(attemptIndex)));
    if direction=="DL"
        result=sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',1,'SNR_dB',30);
    else
        result=sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',1,'SNR_dB',30);
    end
    T=result.TrialTable;
    assert(~result.Skipped && height(T)==1 && ~T.Crash && T.DecodeAttempted, ...
        'test:DirectEnergyReceiverUnavailable','Actual %s attempt failed: %s',direction,strjoin(string(T.Notes),' | '));
    assert(strlength(T.LinkEnergyEvidenceJSON)>0 && strlength(T.LinkEnergyEvidenceSHA256)==64);
    e=jsondecode(T.LinkEnergyEvidenceJSON);
    assert(e.Available && e.Identity.Seed==T.Seed && e.Identity.Slot==T.Slot && ...
        e.CodedBitCount==T.RateMatchedBits && e.TransportBlockBitCount==T.TBSize_bits);
    if isnan(T.UEIndex)
        assert(isstruct(e.Identity.UEIndex) && ...
            string(e.Identity.UEIndex.ValueState)=="original_numeric_scalar_NaN" && ...
            any(string(e.IdentityMissingNumericFields)=="UEIndex"), ...
            'Original unavailable UE identity must remain explicitly unavailable, not inferred.');
    else
        assert(isnumeric(e.Identity.UEIndex) && e.Identity.UEIndex==T.UEIndex);
    end
    assert(numel(e.EnergySumPerReceiveBranch)==T.RxWaveformBranches && ...
        ~isfield(e,'EnergyPerObservation') && ~isfield(e,'DataIndices'));
    source="air_interface/csv/dl_pdsch_trials.csv";
    if direction=="UL", source="air_interface/csv/ul_pusch_trials.csv"; end
    path=fullfile(folder,source);
    sixgr.util.csvWriteTable(path,T,'PreserveSchema',true,'RoundTripNumericText',true);
    restored=sixgr.util.csvReadTable(path,'TextType','string');
    assert(restored.LinkEnergyEvidenceJSON==T.LinkEnergyEvidenceJSON);
    sourcePaths(attemptIndex)=path;
    sourceHashes(attemptIndex)=string(sixgr.util.sha256File(path));
    originalRows{attemptIndex}=T;
    observed=sixgr.report.collectLinkEnergyRatioEvidence(restored,direction,source,sourceHashes(attemptIndex));
    assert(observed.RatioAvailable && ~observed.CountsTowardCoverage && ...
        all(isnan([observed.EsN0_dB,observed.EcNo_dB,observed.EbNo_dB])));
    assert(abs(observed.PureGridNoiseVariance-.25e-3)<1e-12);
    assert(abs(observed.MeanRxBranchEcN0_dB- ...
        10*log10(sum(e.EnergySumPerReceiveBranch)/(e.MeasurementReceipt.ReceiveBranchCount*e.CodedBitCount*e.NoiseReceipt.GridNoiseVariance)))<1e-11);
    if isempty(allObservations), allObservations=observed; else, allObservations=[allObservations;observed]; end %#ok<AGROW>
end
sixgr.util.csvWriteTable(fullfile(folder,'direct_energy_ratio_observations.csv'),allObservations, ...
    'PreserveSchema',true,'RoundTripNumericText',true);
inputs=struct('Version',"direct_energy_report_inputs/v1",'Folder',string(folder), ...
    'Config',cfg,'OriginalRows',{originalRows},'SourcePaths',sourcePaths,'SourceHashes',sourceHashes, ...
    'InputConfigPaths',inputConfigPaths,'InputConfigHashes',inputConfigHashes, ...
    'ExpectedObservations',allObservations,'StartedUTC',startedUTC,'ElapsedSeconds',toc(started));
inputPath=fullfile(layout.MetaDir,'direct_energy_report_inputs.mat');
assert(~isfile(inputPath)); save(inputPath,'inputs','-v7');
sixgr.util.jsonWrite(fullfile(layout.MetaDir,'direct_energy_report_inputs_receipt.json'), ...
    struct('Version',inputs.Version,'MATFileSHA256',string(sixgr.util.sha256File(inputPath)), ...
    'Scope',"original_input_config_and_completed_direct_rows_not_shared_scenario"));
publishAndCheck(inputs,true);
ok=true;
end

function publishAndCheck(inputs,executedHere)
folder=inputs.Folder; cfg=inputs.Config; originalRows=inputs.OriginalRows;
sourcePaths=inputs.SourcePaths; sourceHashes=inputs.SourceHashes;
allObservations=inputs.ExpectedObservations;
layout=sixgr.report.resultLayout(folder);
for k=1:2
    assert(string(sixgr.util.sha256File(sourcePaths(k)))==sourceHashes(k) && ...
        string(sixgr.util.sha256File(inputs.InputConfigPaths(k)))==inputs.InputConfigHashes(k));
    saved=load(inputs.InputConfigPaths(k),'originalInputConfig');
    assert(isequaln(saved.originalInputConfig.phy.carrier,cfg.phy.carrier) && ...
        sixgr.phy.frame.resolveDuplexMode(saved.originalInputConfig)==sixgr.phy.frame.resolveDuplexMode(cfg), ...
        'Both original direct attempts must share the report radio authority.');
    % Exercise both real CSV reader representations without changing any
    % source bytes. Singleton cell-char versus string cannot change identity.
    stringRows=sixgr.util.csvReadTable(sourcePaths(k),'TextType','string');
    defaultRows=sixgr.util.csvReadTable(sourcePaths(k));
    originalStringRows=stringRows; originalDefaultRows=defaultRows;
    direction=allObservations.Direction(k); source=allObservations.SourceArtifact(k);
    fromString=sixgr.report.collectLinkEnergyRatioEvidence(stringRows,direction,source,sourceHashes(k));
    fromDefault=sixgr.report.collectLinkEnergyRatioEvidence(defaultRows,direction,source,sourceHashes(k));
    assert(isequaln(fromString,fromDefault) && isequaln(fromString,allObservations(k,:)) && ...
        isequaln(stringRows,originalStringRows) && isequaln(defaultRows,originalDefaultRows), ...
        'test:DirectEnergyImportIdentity','CSV text containers changed original evidence identity or values.');
    % Declared serialization-only copies: these are not extra measurements.
    textCopy=stringRows; textCopy.PointSerializationProbe="  declared text  ";
    cellCopy=textCopy; cellCopy.PointSerializationProbe={'  declared text  '};
    textObserved=sixgr.report.collectLinkEnergyRatioEvidence(textCopy,direction,source,sourceHashes(k));
    cellObserved=sixgr.report.collectLinkEnergyRatioEvidence(cellCopy,direction,source,sourceHashes(k));
    assert(isequaln(textObserved,cellObserved) && ...
        contains(textObserved.InputIdentityJSON,'"PointSerializationProbe":"  declared text  "'));
    for invalid={ ["one","two"], {'one','two'}, {['one';'two']}, [1 2], {{'nested'}} }
        bad=stringRows; bad.PointSerializationProbe=invalid{1};
        rejected=false;
        try
            sixgr.report.collectLinkEnergyRatioEvidence(bad,direction,source,sourceHashes(k));
        catch cause
            assert(strcmp(cause.identifier,'sixgr:report:InvalidEnergyEvidence'), ...
                'Unexpected identity rejection: %s',cause.identifier);
            rejected=true;
        end
        assert(rejected,'Nonscalar or nested identity must not be flattened into a source ID.');
    end
end
% Use the actual report owner on those SAME original persisted RX rows.
% This wrapper declares publication scope only: it is not a newly executed
% YAML scenario, and adds no missing run/config/clock/receiver authority.
reportData=cfg; % Original internal radio aliases, not an unrelated YAML.
reportData.meta.description='Actual direct DL and UL PHY component attempts; no shared/control/scenario qualification';
reportData.output.artifact_contract_engine.enabled=true;
reportData.frequency.duplex_mode=sixgr.phy.frame.resolveDuplexMode(cfg);
reportData.frequency.n_size_grid=cfg.phy.carrier.NSizeGrid;
reportConfig=sixgr.lls6g.config.ScenarioConfig(reportData);
assert(sixgr.phy.frame.resolveDuplexMode(reportData)==sixgr.phy.frame.resolveDuplexMode(cfg));
operatingPoint=sixgr.truth.summarizeEffectiveOperatingPoint(reportConfig,originalRows{1},originalRows{2},cfg);
assert(operatingPoint.Radio.ActiveDuplexMode==sixgr.phy.frame.resolveDuplexMode(cfg) && ...
    operatingPoint.Radio.CarrierGridNumRBs==cfg.phy.carrier.NSizeGrid);
manifest=struct('CodeVersion',"",'CodeDetail',"testDirectLinkEnergyReceiptPropagation_actual_direct_RX_rows", ...
    'RandomSeed',NaN,'GeneratedUTC',string(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd''T''HH:mm:ss.SSS''Z''')), ...
    'RunnerProfile',"direct_PHY_component_not_shared_runtime", ...
    'RunCompletion',"component_attempts_returned_not_scenario_completion", ...
    'DeterministicMode',"original_per_attempt_seeds_retained_in_rows");
runtime=struct('StartedUTC',inputs.StartedUTC,'ElapsedSeconds',inputs.ElapsedSeconds, ...
    'Warnings',"Publication component only; unexercised scenario sections have no additional evidence.");
report=sixgr.truth.exportLLSReportingBundle(folder,reportConfig,cfg,struct(),manifest,runtime,struct());
% The actual receiver also retains a decision-directed residual. The legacy
% request route must preserve a metric descriptor, never publish this value
% as external-interference power or pass a string to the descriptor helper.
dlResidual=double(originalRows{1}.DecisionResidualSymbolPower_dB);
dlResidual=dlResidual(isfinite(dlResidual));
assert(~isempty(dlResidual),'The original DL attempt must exercise the residual-summary route.');
expectedResidual=[mean(dlResidual);prctile(dlResidual,95);max(dlResidual)];
for rows={report.CategoryRows,sixgr.util.csvReadTable(report.DetailCSV,'TextType','string')}
    detail=rows{1};
    residual=detail(string(detail.MetricKey)=="decision_residual_symbol_power",:);
    assert(height(residual)==3 && ...
        isequal(string(residual.Statistic),["mean";"p95";"max"]) && ...
        all(string(residual.MetricName)=="Decision residual symbol power") && ...
        all(string(residual.Unit)=="dB_relative_equalized_symbol_unit") && ...
        all(string(residual.Entity)=="DL") && ...
        all(string(residual.SourceArtifact)=="air_interface/csv/dl_pdsch_trials.csv") && ...
        all(contains(string(residual.Notes),"not a measurement of external interference power")) && ...
        all(abs(double(residual.ValueNumeric)-expectedResidual)<1e-11), ...
        'test:DirectEnergyResidualSummary','The actual residual summary lost its value, descriptor, or measurement scope.');
    assert(~any(string(detail.MetricKey)=="residual_interference_power" & isfinite(double(detail.ValueNumeric))), ...
        'The decision residual must not be relabeled as measured external interference.');
end
for rows={report.Coverage,sixgr.util.csvReadTable(report.CoverageCSV,'TextType','string')}
    coverage=rows{1};
    residual=coverage(string(coverage.MetricKey)=="decision_residual_symbol_power",:);
    assert(height(residual)==1 && residual.CountsTowardCoverage && ...
        residual.CoveredRowCount==3 && residual.ObservedRowCount==3 && ...
        string(residual.Availability)=="observed" && ...
        string(residual.MetricName)=="Decision residual symbol power" && ...
        string(residual.SourceArtifacts)=="air_interface/csv/dl_pdsch_trials.csv" && ...
        ~any(string(coverage.MetricKey)=="residual_interference_power"), ...
        'test:DirectEnergyResidualCoverage','Catalog requests and actual residual outputs must share the correct metric identity.');
end
published=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir,'link_energy_ratio_observations.csv'), ...
    'TextType','string');
assert(height(published)==2 && isequal(string(published.Direction),["DL";"UL"]) && ...
    all(published.RatioAvailable) && ~any(published.CountsTowardCoverage) && ...
    all(isnan([published.EsN0_dB;published.EcNo_dB;published.EbNo_dB])));
assert(isequal(published.Properties.VariableNames,allObservations.Properties.VariableNames));
for name=string(allObservations.Properties.VariableNames)
    expected=allObservations.(name); actual=published.(name);
    if isnumeric(expected)||islogical(expected)
        assert((isnumeric(actual)||islogical(actual)) && isequaln(double(actual),double(expected)), ...
            'test:DirectEnergyReportMismatch','Persisted diagnostic numeric field changed: %s',name);
    else
        assert(isequal(string(actual),string(expected)), ...
            'test:DirectEnergyReportMismatch','Persisted diagnostic/source field changed: %s',name);
    end
end
for k=1:2
    assert(string(sixgr.util.sha256File(sourcePaths(k)))==sourceHashes(k), ...
        'The report owner must not rewrite the original actual receiver source.');
    restored=sixgr.util.csvReadTable(sourcePaths(k),'TextType','string');
    assert(restored.LinkEnergyEvidenceJSON==originalRows{k}.LinkEnergyEvidenceJSON && ...
        restored.LinkEnergyEvidenceSHA256==originalRows{k}.LinkEnergyEvidenceSHA256 && ...
        published.LinkEnergyEvidenceJSON(k)==restored.LinkEnergyEvidenceJSON && ...
        published.LinkEnergyEvidenceSHA256(k)==restored.LinkEnergyEvidenceSHA256 && ...
        published.SourceArtifactSHA256(k)==sourceHashes(k) && published.SourceRow(k)==1);
    e=jsondecode(published.LinkEnergyEvidenceJSON(k));
    assert(e.Identity.Direction==string(restored.Direction) && e.Identity.Seed==restored.Seed && ...
        e.Identity.Slot==restored.Slot && e.CodedBitCount==published.CodedBitCount(k) && ...
        e.TransportBlockBitCount==published.TransportBlockBitCount(k) && ...
        e.NoiseReceipt.GridNoiseVariance==published.PureGridNoiseVariance(k));
end
fprintf('DIRECT_LINK_ENERGY_RECEIPTS_PASS retained_DL_attempts=1 retained_UL_attempts=1 PHY_executed_here=%d report_owner_rows=2 shared_runtime=0 evidence=%s\n',executedHere,folder);
end

function inputs=loadOriginalReportInputs(retainedFolder)
sourceLayout=sixgr.report.resultLayout(retainedFolder);
inputPath=fullfile(sourceLayout.MetaDir,'direct_energy_report_inputs.mat');
receiptPath=fullfile(sourceLayout.MetaDir,'direct_energy_report_inputs_receipt.json');
assert(isfile(inputPath)&&isfile(receiptPath),'test:DirectEnergyOriginalConfigUnavailable', ...
    'Report-only replay requires an original saved config/rows record; historical CSV cannot supply missing config.');
receipt=jsondecode(fileread(receiptPath));
assert(string(receipt.Version)=="direct_energy_report_inputs/v1" && ...
    string(receipt.MATFileSHA256)==string(sixgr.util.sha256File(inputPath)));
loaded=load(inputPath,'inputs'); inputs=loaded.inputs;
assert(inputs.Version=="direct_energy_report_inputs/v1" && ...
    string(java.io.File(char(inputs.Folder)).getCanonicalPath())== ...
    string(java.io.File(char(retainedFolder)).getCanonicalPath()));
% Keep the original report/failure artifacts and all raw bytes untouched.
folder=fullfile(sourceLayout.Root,'report_only_retry_'+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder)); layout=sixgr.report.resultLayout(folder);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
for k=1:2
    assert(string(sixgr.util.sha256File(inputs.SourcePaths(k)))==inputs.SourceHashes(k));
    target=fullfile(folder,inputs.ExpectedObservations.SourceArtifact(k));
    assert(~isfile(target)); copyfile(inputs.SourcePaths(k),target);
    assert(string(sixgr.util.sha256File(target))==inputs.SourceHashes(k));
    inputs.SourcePaths(k)=string(target);
end
inputs.Folder=string(folder);
end
