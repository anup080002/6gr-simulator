classdef CalibratedWaveformRunner
    %CALIBRATEDWAVEFORMRUNNER Bounded waveform-truth evidence for BWOP.
    %
    % Every data row emitted by this adapter comes from sixgr.lls.runLLS
    % or the strict PDCCH waveform validator.  Power-normalization cases
    % are executed at their physically adjusted per-RE Es/N0; the reported
    % reference SNR is retained separately so no axis relabeling can hide
    % the actual noise point used by the receiver.

    methods (Static)
        function out = run(cfg,modeCfg,runFolder)
            arguments
                cfg (1,1) struct
                modeCfg (1,1) struct
                runFolder (1,1) string
            end

            authority = cfg.calibrated_waveform;
            caseTable = localCaseTable(authority);
            trialCap = min(double(modeCfg.max_trials_per_point), ...
                double(authority.transport_blocks_per_point));
            if trialCap < 1
                error("sixgr:bwop:InvalidCalibratedTrialCap", ...
                    "A calibrated waveform mode requires at least one transport block per point.");
            end

            configDir = fullfile(runFolder,"config","derived_lls");
            llsRoot = fullfile(runFolder,"raw","lls");
            sixgr.util.ensureFolder(configDir);
            sixgr.util.ensureFolder(llsRoot);
            summaryParts = cell(height(caseTable),1);
            trialParts = cell(height(caseTable),1);
            indexRows = cell(height(caseTable),1);
            for ii = 1:height(caseTable)
                c = caseTable(ii,:);
                basePath = localBasePath(authority,c.Link);
                [llsCfg,~] = sixgr.lls.loadConfig(basePath);
                llsCfg = localApplyCase(llsCfg,c,authority,trialCap,cfg.master_seed,ii);
                llsCfg = sixgr.lls.validateConfig(llsCfg,"ConfigPath", ...
                    "bwop.calibrated_waveform."+c.CaseID);
                childPath = fullfile(configDir,c.CaseID+".yaml");
                sixgr.lls6g.config.writeYAML(childPath,llsCfg);

                fprintf("  BWOP waveform case %d/%d: %s (%s, %d RB, %s)\n", ...
                    ii,height(caseTable),c.CaseID,c.Link,c.AllocationRB,c.PowerMode);
                result = localRunOrReuseLLS(childPath,llsCfg,llsRoot);
                if ~ismember(result.Status,["pass","complete_valid"])
                    error("sixgr:bwop:CalibratedLLSFailed", ...
                        "Waveform case %s failed strict LLS validation.",c.CaseID);
                end
                summaryParts{ii} = localAnnotate(result.SummaryTable,c);
                trialParts{ii} = localAnnotate(result.TrialTable,c);
                indexRows{ii} = table(c.CaseID,c.StudyID,c.Link,c.PowerMode, ...
                    c.AllocationRB,string(result.RunFolder),string(result.Status), ...
                    string(result.ConfigSHA256),double(result.RuntimeSeconds), ...
                    'VariableNames',{'CaseID','StudyID','Link','PowerMode', ...
                    'AllocationRB','RunFolder','Status','ConfigSHA256','RuntimeSeconds'});
            end

            commonSummaryParts=cellfun(@localCommonSummaryProjection,summaryParts, ...
                'UniformOutput',false);
            summary = vertcat(commonSummaryParts{:});
            pdschSummary = summary(summary.Link=="PDSCH",:);
            puschSummary = summary(summary.Link=="PUSCH",:);
            pdschTrials = vertcat(trialParts{caseTable.Link=="PDSCH"});
            puschTrials = vertcat(trialParts{caseTable.Link=="PUSCH"});
            commonParts=cellfun(@localCommonTrialProjection,trialParts, ...
                'UniformOutput',false);
            trials = vertcat(commonParts{:});
            sixgr.bwop.EvidenceClassifier.assertNotProxy(summary);
            sixgr.bwop.EvidenceClassifier.assertNotProxy(trials);
            localValidateWaveformRows(summary,trials,trialCap,authority);

            pdcch = localRunPDCCH(authority,cfg.master_seed,runFolder);
            dlJoint = summary(summary.StudyID=="DL-001",:);
            dlJoint = localJointInput(dlJoint);
            joint = sixgr.bwop.JointSIB1Study.combine(pdcch.Summary,dlJoint);

            out = struct();
            out.Summary = summary;
            out.PDSCHSummary = pdschSummary;
            out.PUSCHSummary = puschSummary;
            out.Trials = trials;
            out.PDSCHTrials = pdschTrials;
            out.PUSCHTrials = puschTrials;
            out.RunIndex = vertcat(indexRows{:});
            out.CALFixedPSD = summary(summary.StudyID=="CAL-001" & ...
                summary.PowerMode=="fixed_psd",:);
            out.CALFixedTotal = summary(summary.StudyID=="CAL-001" & ...
                summary.PowerMode=="fixed_total_power",:);
            out.PDSCH = summary(summary.StudyID=="DL-001",:);
            out.PUSCH = summary(summary.StudyID=="UL-002",:);
            out.PDCCH = pdcch.Summary;
            out.PDCCHTrials = pdcch.Trials;
            out.JointSIB1 = joint;
            out.Quality = localQualityTable(summary,trials,pdcch,trialCap,authority);
        end
    end
end

function T = localCommonSummaryProjection(T)
fields=["ScenarioId","ConfigSHA256","SNRIndex","SNRD", ...
    "NumTB","NumBlockErrors","BLER","BLERLowerCI","BLERUpperCI", ...
    "ConfidenceLevel","NumBits","NumBitErrors","BER", ...
    "SuccessfulInformationBits","SimulatedDurationSeconds","ThroughputBps", ...
    "MeanMeasuredSNRdB","MeasuredSNRStdDevdB","StoppingReason", ...
    "RuntimeSeconds","ExecutionBackend","ApproximationMode","StatisticalClass", ...
    "CaseID","StudyID","Link","PowerMode","ReferenceSNRdB", ...
    "ActualPerRESNRdB","SNROffsetDb","ActualAllocationRB","EvidenceClass"];
% readtable may normalize the SNR header differently across MATLAB releases.
if ismember("SNRdB",string(T.Properties.VariableNames))
    T.SNRD=double(T.SNRdB);
elseif ~ismember("SNRD",string(T.Properties.VariableNames))
    error("sixgr:bwop:MissingCommonSummaryField","LLS summary is missing SNRdB.");
end
missing=fields(~ismember(fields,string(T.Properties.VariableNames)));
if ~isempty(missing)
    error("sixgr:bwop:MissingCommonSummaryField", ...
        "LLS summary schema is missing shared field(s): %s.",strjoin(missing,", "));
end
T=T(:,fields);
T.ScenarioId=string(T.ScenarioId);T.ConfigSHA256=string(T.ConfigSHA256);
T.StoppingReason=string(T.StoppingReason);T.ExecutionBackend=string(T.ExecutionBackend);
T.ApproximationMode=string(T.ApproximationMode);T.StatisticalClass=string(T.StatisticalClass);
snrName=find(strcmp(T.Properties.VariableNames,"SNRD"),1);
T.Properties.VariableNames{snrName}='SNRdB';
end

function T = localCommonTrialProjection(T)
fields=["ScenarioId","ConfigSHA256","SNRIndex","TrialIndex", ...
    "TargetSNRdB","MeasuredSNRdB","TransportBlockSizeBits","BitErrors", ...
    "CRCError","ACK","DataREPerLayer","DMRSRE","PTRSRE","ReservedRE", ...
    "CodedBitsG","MCSIndex","MCSTable","Modulation","ModulationOrder", ...
    "TargetCodeRate","NumLayers","NumTxPorts","NumRxAntennas", ...
    "SignalEnergyPerOccupiedRE","RequestedGridNoiseVariance", ...
    "MeasuredGridNoiseVariance","ChannelModel","ChannelRealizationSource", ...
    "ChannelEstimationMode","ChannelEstimateSource","LDPCSource", ...
    "UseMexLDPC","LDPCDecoderEngine","RuntimeSeconds", ...
    "CaseID","StudyID","Link","PowerMode","ReferenceSNRdB", ...
    "ActualPerRESNRdB","SNROffsetDb","ActualAllocationRB","EvidenceClass"];
missing=fields(~ismember(fields,string(T.Properties.VariableNames)));
if ~isempty(missing)
    error("sixgr:bwop:MissingCommonTrialField", ...
        "Waveform trial schema is missing shared field(s): %s.",strjoin(missing,", "));
end
T=T(:,fields);
end

function T = localCaseTable(a)
names = ["case_id","study_id","link","power_mode","frequency_hz", ...
    "bandwidth_mhz","scs_khz","n_size_grid","start_prb","allocation_rb", ...
    "symbol_start","symbol_length","channel_model","delay_spread_ns", ...
    "velocity_kmph","snr_offset_db"];
lengths = zeros(size(names));
for ii=1:numel(names)
    if ~isfield(a.cases,names(ii))
        error("sixgr:bwop:MissingCalibratedCaseField", ...
            "calibrated_waveform.cases.%s is required.",names(ii));
    end
    lengths(ii)=numel(a.cases.(names(ii)));
end
if numel(unique(lengths))~=1 || lengths(1)<1
    error("sixgr:bwop:CalibratedCaseLengthMismatch", ...
        "All calibrated waveform case arrays must have one value per case.");
end
T=table(string(a.cases.case_id(:)),string(a.cases.study_id(:)), ...
    upper(string(a.cases.link(:))),lower(string(a.cases.power_mode(:))), ...
    double(a.cases.frequency_hz(:)),double(a.cases.bandwidth_mhz(:)), ...
    double(a.cases.scs_khz(:)),double(a.cases.n_size_grid(:)), ...
    double(a.cases.start_prb(:)),double(a.cases.allocation_rb(:)), ...
    double(a.cases.symbol_start(:)),double(a.cases.symbol_length(:)), ...
    upper(string(a.cases.channel_model(:))),double(a.cases.delay_spread_ns(:)), ...
    double(a.cases.velocity_kmph(:)),double(a.cases.snr_offset_db(:)), ...
    'VariableNames',{'CaseID','StudyID','Link','PowerMode','FrequencyHz', ...
    'BandwidthMHz','SCSkHz','NSizeGrid','StartPRB','AllocationRB', ...
    'SymbolStart','SymbolLength','ChannelModel','DelaySpreadNS', ...
    'VelocityKmph','SNROffsetDb'});
if numel(unique(T.CaseID))~=height(T) || ...
        any(~ismember(T.Link,["PDSCH","PUSCH"])) || ...
        any(~ismember(T.PowerMode,["fixed_psd","fixed_total_power","fixed_pmax"]))
    error("sixgr:bwop:InvalidCalibratedCase", ...
        "Calibrated cases require unique IDs, PDSCH/PUSCH links and supported power modes.");
end
end

function path = localBasePath(a,link)
if link=="PDSCH"
    path=string(a.pdsch_base_config);
else
    path=string(a.pusch_base_config);
end
end

function c = localApplyCase(c,row,a,trialCap,masterSeed,index)
c.scenario.id=char("bwop_"+lower(row.CaseID));
c.scenario.description=char("Bounded BWOP waveform-truth case "+row.CaseID);
c.simulation.link=char(row.Link);
c.simulation.masterSeed=double(masterSeed)+index*1000;
c.simulation.commonRandomKey=char("bwop_"+lower(row.CaseID)+"_crn_v1");
c.simulation.snrDb=double(a.reference_snr_db(:).')+double(row.SNROffsetDb);
c.simulation.minTransportBlocks=trialCap;
c.simulation.minBlockErrors=1;
c.simulation.maxTransportBlocks=trialCap;
c.simulation.confidenceLevel=double(a.confidence_level);
c.simulation.statisticalClass='diagnostic_only';
c.execution.parallelEnabled=false;
c.execution.maximumWorkers=1;
c.execution.batchTransportBlocks=1;
c.carrier.frequencyHz=double(row.FrequencyHz);
c.carrier.bandwidthMHz=double(row.BandwidthMHz);
c.carrier.subcarrierSpacingKHz=double(row.SCSkHz);
c.carrier.nSizeGrid=double(row.NSizeGrid);
c.allocation.startPRB=double(row.StartPRB);
c.allocation.numberPRB=double(row.AllocationRB);
c.allocation.symbols=[double(row.SymbolStart),double(row.SymbolLength)];
c.channel.model=char(row.ChannelModel);
c.channel.delaySpreadSeconds=double(row.DelaySpreadNS)*1e-9;
c.channel.velocityKmph=double(row.VelocityKmph);
c.channel.txAntennas=1;
c.channel.rxAntennas=1;
c.channel.seed=double(masterSeed)+index*1000+17;
c.receiver.channelEstimation='practical';
c.receiver.postEqualizationSINR.dmrsResidualBoundEnabled=false;
c.receiver.postEqualizationSINR.decisionDirectedResidualBoundEnabled=false;
c.receiver.decoderNoiseVariance.mode='post_equalization';
c.provenance.requireCleanWorktree=false;
c.provenance.requireStableSourceThroughoutRun=false;
c.results.generatePlots=true;
c.results.imageFormat='png';
end

function T = localAnnotate(T,c)
n=height(T);
T.CaseID=repmat(c.CaseID,n,1);
T.StudyID=repmat(c.StudyID,n,1);
T.Link=repmat(c.Link,n,1);
T.PowerMode=repmat(c.PowerMode,n,1);
if ismember("SNRdB",string(T.Properties.VariableNames))
    actualSNR=double(T.SNRdB);
else
    actualSNR=double(T.TargetSNRdB);
end
T.ReferenceSNRdB=actualSNR-double(c.SNROffsetDb);
T.ActualPerRESNRdB=actualSNR;
T.SNROffsetDb=repmat(double(c.SNROffsetDb),n,1);
T.ActualAllocationRB=repmat(double(c.AllocationRB),n,1);
T.EvidenceClass=repmat("CALIBRATED_LLS",n,1);
end

function localValidateWaveformRows(summary,trials,trialCap,a)
criticalSummary=["SNRdB","NumTB","BLER","BLERLowerCI","BLERUpperCI", ...
    "MeanMeasuredSNRdB","RuntimeSeconds"];
criticalTrials=["TargetSNRdB","MeasuredSNRdB","TransportBlockSizeBits", ...
    "BitErrors","CRCError","DataREPerLayer","DMRSRE","CodedBitsG", ...
    "RequestedGridNoiseVariance","MeasuredGridNoiseVariance"];
if any(~isfinite(summary{:,criticalSummary}),"all") || ...
        any(~isfinite(double(trials{:,criticalTrials})),"all")
    error("sixgr:bwop:NonFiniteCalibratedEvidence", ...
        "Calibrated waveform evidence contains non-finite critical values.");
end
counts=groupcounts(trials,"CaseID");
expected=numel(double(a.reference_snr_db))*trialCap;
if any(counts.GroupCount~=expected)
    error("sixgr:bwop:CalibratedTrialCountMismatch", ...
        "Every bounded waveform case must contain exactly %d trials.",expected);
end

if any(abs(double(trials.MeasuredSNRdB)-double(trials.TargetSNRdB))> ...
        double(a.maximum_measured_snr_error_db))
    error("sixgr:bwop:SNRCalibrationFailure", ...
        "Measured waveform Es/N0 differs from the configured point beyond tolerance.");
end
if any(trials.TransportBlockSizeBits<=0 | trials.DataREPerLayer<=0 | ...
        trials.CodedBitsG<=0 | trials.MeasuredGridNoiseVariance<=0)
    error("sixgr:bwop:InvalidWaveformAccounting", ...
        "Waveform accounting must be finite and strictly positive.");
end
end

function result = localRunOrReuseLLS(childPath,llsCfg,llsRoot)
expectedFolder=fullfile(llsRoot,char(string(llsCfg.scenario.id)),"measured");
[~,configProvenance]=sixgr.lls.loadConfig(string(childPath));
provenancePath=fullfile(expectedFolder,"run_provenance.json");
required=["bler_vs_snr.csv","transport_block_trials.csv", ...
    "truth_contract.csv","result_validity.csv","artifact_manifest.csv"];
canReuse=isfile(provenancePath)&&all(arrayfun(@(name) ...
    isfile(fullfile(expectedFolder,name)),required));
if canReuse
    provenance=jsondecode(fileread(provenancePath));
    canReuse=string(provenance.ConfigSHA256)==string(configProvenance.ConfigSHA256)&& ...
        string(provenance.ResultValidity)=="complete_valid"&& ...
        string(provenance.ExecutionBackend)=="waveform_truth"&& ...
        string(provenance.ApproximationMode)=="none";
end
if canReuse
    fprintf("    reusing hash-matched complete waveform evidence: %s\n",expectedFolder);
    result=struct("Status","complete_valid","RunFolder",string(expectedFolder), ...
        "ConfigSHA256",string(configProvenance.ConfigSHA256), ...
        "SummaryTable",readtable(fullfile(expectedFolder,"bler_vs_snr.csv"), ...
            "VariableNamingRule","preserve"), ...
        "TrialTable",readtable(fullfile(expectedFolder,"transport_block_trials.csv"), ...
            "VariableNamingRule","preserve"), ...
        "RuntimeSeconds",double(provenance.RuntimeSeconds));
else
    if isfolder(expectedFolder)
        error("sixgr:bwop:ExistingLLSEvidenceMismatch", ...
            "Existing child LLS evidence is incomplete or does not match the current config hash: %s.", ...
            expectedFolder);
    end
    result=sixgr.lls.runLLS(childPath,"OutputRoot",llsRoot, ...
        "RunTag","measured","GeneratePlots",true);
end
end

function p = localRunPDCCH(a,masterSeed,runFolder)
scenarioObject=sixgr.lls6g.config.loadScenarioConfig(string(a.pdcch_base_config));
scenario=scenarioObject.toStruct();
scenario=sixgr.util.structSet(scenario,"control.pdcch_strict.low_snr_sweep_db", ...
    double(a.reference_snr_db(:).'));
scenario=sixgr.util.structSet(scenario,"control.pdcch_strict.low_snr_trials", ...
    double(a.pdcch_trials_per_point));
scenario=sixgr.util.structSet(scenario,"control.pdcch_strict.false_alarm_snr_db", ...
    double(a.reference_snr_db(:).'));
scenario=sixgr.util.structSet(scenario,"control.pdcch_strict.false_alarm_trials", ...
    double(a.pdcch_trials_per_point));
scenario=sixgr.util.structSet(scenario, ...
    "control.pdcch_strict.statistical_qualification.minimum_waveform_trials", ...
    double(a.pdcch_trials_per_point));
scenario=sixgr.util.structSet(scenario, ...
    "control.pdcch_strict.statistical_qualification.maximum_waveform_trials", ...
    double(a.pdcch_trials_per_point));
scenario=sixgr.util.structSet(scenario,"simulation.random_seed",double(masterSeed)+90000);
folder=fullfile(runFolder,"raw","lls","pdcch_strict");
sixgr.util.ensureFolder(folder);
internal=sixgr.lls6g.buildInternalConfig(scenario,folder);
result=sixgr.phy.pdcch.runStrictPDCCHValidation(internal,"RunFolder",folder, ...
    "RunId","bwop_pdcch_bounded","ScenarioName","bwop_pdcch_bounded", ...
    "EvidenceScope","bwop_component_waveform","WriteArtifacts",true);
if ~logical(result.StrictOk)
    error("sixgr:bwop:StrictPDCCHFailed", ...
        "The bounded strict PDCCH waveform campaign failed.");
end
raw=result.ArtifactTables.pdcch_low_snr_sweep;
trials=double(raw.NumTrials);errors=trials-double(raw.NumCrcPass);
summary=table(double(raw.SNRdB),trials,errors,errors./trials, ...
    double(raw.CrcPassProbability),double(raw.CrcPassCILower), ...
    double(raw.CrcPassCIUpper),repmat("CALIBRATED_LLS",height(raw),1), ...
    'VariableNames',{'SNRdB','Trials','Errors','BLER','SuccessProbability', ...
    'SuccessCILower','SuccessCIUpper','EvidenceClass'});
p=struct("Summary",summary,"Trials",result.ArtifactTables.pdcch_trials, ...
    "StrictOk",logical(result.StrictOk));
end

function T = localJointInput(summary)
if isempty(summary)
    error("sixgr:bwop:MissingJointPDSCHCase", ...
        "DL-001 waveform rows are required for joint SIB1 evidence.");
end
T=table(double(summary.ReferenceSNRdB),double(summary.NumTB), ...
    double(summary.NumBlockErrors),'VariableNames',{'SNRdB','Trials','Errors'});
end

function T = localQualityTable(summary,trials,pdcch,trialCap,a)
snrError=abs(double(trials.MeasuredSNRdB)-double(trials.TargetSNRdB));
checks=["all_case_status_pass";"exact_trial_count";"finite_summary_values"; ...
    "finite_trial_values";"snr_calibration";"positive_resource_accounting"; ...
    "proxy_rows_absent";"strict_pdcch_pass"];
expected=height(unique(summary(:,"CaseID")))*numel(double(a.reference_snr_db))*trialCap;
passes=[height(summary)>0; height(trials)==expected; ...
    all(isfinite(summary.BLER));all(isfinite(trials.MeasuredSNRdB)); ...
    all(snrError<=double(a.maximum_measured_snr_error_db)); ...
    all(trials.DataREPerLayer>0 & trials.CodedBitsG>0);true;logical(pdcch.StrictOk)];
details=["cases="+height(unique(summary(:,"CaseID"))); ...
    "observed="+height(trials)+", expected="+expected; ...
    "summary_rows="+height(summary);"trial_rows="+height(trials); ...
    "max_abs_error_db="+max(snrError);"minimum_data_re="+min(trials.DataREPerLayer); ...
    "EvidenceClassifier.assertNotProxy passed";"strict_ok="+pdcch.StrictOk];
T=table(checks,logical(passes),string(details), ...
    'VariableNames',{'Check','Pass','Detail'});
end
