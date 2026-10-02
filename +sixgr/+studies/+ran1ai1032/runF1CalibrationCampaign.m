function receipt = runF1CalibrationCampaign(studyPath, outputRoot, runTag)
%RUNF1CALIBRATIONCAMPAIGN Bounded, resumable execution of real F1 PUSCH TBs.
% All execution policy comes from study YAML. A checkpoint commits after
% every completed PHY trial. Reinvoking the same command resumes the point.
arguments
    studyPath (1,1) string
    outputRoot (1,1) string
    runTag (1,1) string
end
assert(~isempty(regexp(char(runTag),'^[A-Za-z0-9_-]+$','once')), ...
    'sixgr:ran1ai1032:F1RunTag','runTag must be a single safe directory name.');
[study,provenance]=sixgr.studies.ran1ai1032.loadStudyConfig(studyPath);
e=study.lls.execution;
budget=double(e.transport_blocks_per_invocation);
validateattributes(budget,{'numeric'},{'scalar','integer','positive','finite'});
plan=sixgr.studies.ran1ai1032.buildLLSCasePlan(study);
C=plan.CasePlan;
selected=C.ExperimentID=="F1" & ismember(C.EntryID,string(e.entry_ids)) & ...
    ismember(C.ChannelProfile,string(e.channel_profiles)) & ismember(C.Rank,double(e.ranks));
if isfield(e,'antenna_case_ids') && ~isempty(e.antenna_case_ids)
    selected=selected & ismember(C.AntennaCaseID,string(e.antenna_case_ids));
end
C=C(selected,:);
assert(~isempty(C),'sixgr:ran1ai1032:F1Selection','F1 selection contains no physical cases.');
folder=fullfile(outputRoot,runTag,'f1');
if ~isfolder(folder), mkdir(folder); end
scientific=study;
scientific.lls.execution=rmfield(scientific.lls.execution,'transport_blocks_per_invocation');
sourceFiles=["+sixgr/+studies/+ran1ai1032/buildF1RuntimeConfig.m", ...
    "+sixgr/+studies/+ran1ai1032/runF1CalibrationCampaign.m", ...
    "+sixgr/+studies/+ran1ai1032/executeF1PUSCHTrial.m", ...
    "+sixgr/+studies/+ran1ai1032/resolveF1RFBranch.m", ...
    "+sixgr/+studies/+ran1ai1032/rfBranchIdentity.m", ...
    "+sixgr/+studies/+ran1ai1032/applyF1TransmitRF.m", ...
    "+sixgr/+studies/+ran1ai1032/applyRFStudyBranch.m", ...
    "+sixgr/+link/runULPUSCHThroughput.m","+sixgr/+phy/+ul/PUSCH_Tx.m", ...
    "+sixgr/+phy/+grid/allocPUSCHTransport.m", ...
    "+sixgr/+phy/+research/PUSCHUCIResourceAdapter.m", ...
    "+sixgr/+phy/+resource/computeResourceAccounting.m", ...
    "+sixgr/+phy/+ul/PUSCH_Rx.m","+sixgr/+channel/ChannelFactory.m", ...
    "+sixgr/+rf/applyPowerContext.m","+sixgr/+link/applyWaveformImpairments.m", ...
    "+sixgr/+truth/SharedWaveformPhysicalRuntime.m", ...
    "+sixgr/+rf/+runtime/RFImpairmentStream.m", ...
    "+sixgr/+rf/PhaseNoiseModel.m", "+sixgr/+rf/+runtime/PhaseNoiseProfile.m", ...
    "+sixgr/+rf/+runtime/PhaseNoiseProcess.m", "+sixgr/+rf/+runtime/SpectralPhaseNoiseFilter.m", ...
    "+sixgr/+rf/+runtime/resolveMultipolePhaseNoiseProfile.m", ...
    "simulator/configs/schema/core_parameter_catalog.yaml", ...
    "simulator/configs/schema/scenario_parameter_catalog.yaml",string(e.research_transport_policy_path)];
branch=sixgr.studies.ran1ai1032.resolveF1RFBranch(study,string(2^double(C.Qm(1)))+"QAM");
if isfield(branch,'phase_noise_profile_path')
    sourceFiles(end+1)=string(branch.phase_noise_profile_path);
end
sourceHashes=strings(size(sourceFiles));
for si=1:numel(sourceFiles), sourceHashes(si)=sixgr.csi.studyFileSHA256(sourceFiles(si)); end
identity=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(scientific)+join(sourceHashes,''),'UTF-8'))));
metadataPath=fullfile(folder,'campaign_identity.mat');
if isfile(metadataPath)
    prior=load(metadataPath,'identity');
    assert(string(prior.identity)==identity,'sixgr:ran1ai1032:F1ResumeIdentity', ...
        'Scientific configuration changed. Use a new run tag.');
else
    environment=struct('MATLABVersion',version,'Toolboxes',ver,'Provenance',provenance);
    save(metadataPath,'identity','study','environment','sourceFiles','sourceHashes','branch');
    copyfile(studyPath,fullfile(folder,'input_study.yaml'));
    if isfield(branch,'phase_noise_profile_path')
        copyfile(branch.phase_noise_profile_path,fullfile(folder,'input_phase_noise_profile.yaml'));
    end
    writetable(C,fullfile(folder,'selected_cases.csv'));
end
old=rng; restore=onCleanup(@()rng(old)); %#ok<NASGU>
executed=0; allComplete=true; summaries=table();
for ci=1:height(C)
    c=C(ci,:); cf=fullfile(folder,c.OutputGroupID);
    if ~isfolder(cf), mkdir(cf); end
    casePath=fullfile(cf,'case_checkpoint.mat');
    if isfile(casePath)
        loaded=load(casePath,'state'); state=loaded.state;
        assert(state.Identity==identity,'sixgr:ran1ai1032:F1ResumeIdentity','Case identity differs.');
        if ~isempty(state.Trials)
            active=state.Points(state.PointOrdinal,:);
            writetable(state.Trials,fullfile(cf,localPointName(active.InputSNRdB)+"_trials.csv"));
        end
    else
        points=plan.PointPlan(plan.PointPlan.CaseID==c.CaseID,:);
        state=struct('Identity',identity,'Points',points,'PointOrdinal',1, ...
            'RefinementAdded',false,'Curve',table(),'Trials',table());
    end
    while state.PointOrdinal<=height(state.Points) && executed<budget
        p=state.Points(state.PointOrdinal,:);
        n=height(state.Trials);
        while n<double(study.statistics.maximum_transport_blocks_per_point) && executed<budget
            trialID=n+1;
            seed=localSeed(c.ComparisonPairKey,p.InputSNRdB,trialID,study.lls.pairing_base_seed);
            cfg=sixgr.studies.ran1ai1032.buildF1RuntimeConfig(study,c,p.InputSNRdB,seed);
            if n==0
                save(fullfile(cf,localPointName(p.InputSNRdB)+"_resolved_config.mat"),'cfg','identity');
            end
            result=sixgr.studies.ran1ai1032.executeF1PUSCHTrial(cfg,study);
            T=result.TrialTable;
            localValidateTrial(T,c,p,cfg,result);
            wanted=["Seed","MCS","PRBs","Layers","Modulation","TargetCodeRate", ...
                "TBSize_bits","CRCPass","DecoderIterations","EVM_rms","NMSE_dB", ...
                "MeasuredSINR_dB","ConditionNumber_dB","NumRxAntennas","NumTxPorts", ...
                "BitErrors","BitsCompared","GoodBits","OfferedBits", ...
                "NumCodeBlocks","BaseGraph","EncodedBits","RateMatchedBits", ...
                "RateMatchPunctureBits","RateMatchRepetitionBits","DataRECount", ...
                "DMRSRECount","PTRSRECount","ConfiguredSNR_dB","AppliedAWGNSNR_dB", ...
                "NoiseVariance","NoiseVarianceSource","ExecutionBackend", ...
                "ChannelModel","DopplerHz","ConfiguredDopplerHz","TBSInputNREPerPRB","TBSInputXOverhead", ...
                "TBSInputSource","MeasuredTrialSINRSource","ChannelEstimateAvailable", ...
                "EqualizationAvailable","Notes", ...
                "PowerNormalizationPolicy","PowerNormalizationSource", ...
                "PowerNormalizationGridMeanEnergyPerRE","TransmitGridEnergyBeforeNormalization", ...
                "AppliedTransmitAmplitudeScale","AppliedGridNoiseVariance","SampleNoiseVariance", ...
                "NMSEStatus","ActualTotalTxPower_dBm", ...
                "ConfiguredTXEVMPercent","MeasuredTXEVMPercent", ...
                "ConfiguredRXEVMPercent","MeasuredRXEVMPercent","RXEVMReferenceSource", ...
                "ConfiguredRequestedPowerdBm","ConfiguredMaximumPowerdBm", ...
                "ConfiguredAppliedPowerdBm","MPRdB","PowerCapActive", ...
                "MeasuredTransmitPowerRatio","AbsolutePowerStatus", ...
                "AppliedCFOHz","PhaseNoiseApplied","PhaseNoiseProfileID","PhaseNoiseProfileSource","RFClassification", ...
                "PostRFMeanTotalTransmitSamplePower","NominalPreCapGridReferenceEnergy","RFProfileID", ...
                "PTRSConfiguredEnabled","PTRSCPECorrectionConfigured","PTRSCPECorrectionApplied", ...
                "PTRSCPECorrectionSymbols","PTRSMeanCPE_deg","PTRSCPECorrectionStatus"];
            row=T(:,intersect(wanted,string(T.Properties.VariableNames),'stable'));
            row.TrialOrdinal=trialID;
            row.CaseID=c.CaseID; row.EntryID=c.EntryID;
            row.SourceClassification="executed_phy_truth";
            row.RFBranch=string(e.rf_branch);
            row.PowerPlane=string(cfg.meta.f1PowerPlane);
            state.Trials=[state.Trials;row]; %#ok<AGROW>
            n=height(state.Trials); executed=executed+1;
            localCheckpoint(casePath,state);
            pointCSV=fullfile(cf,localPointName(p.InputSNRdB)+"_trials.csv");
            % CSV is a materialization of the committed MAT, so interrupted
            % appends can always be repaired by the next invocation.
            if n==1 || trialID==1, writetable(state.Trials,pointCSV);
            else, writetable(row,pointCSV,'WriteMode','append','WriteVariableNames',false); end
            errors=sum(~logical(state.Trials.CRCPass));
            fprintf('F1_PROGRESS case=%s reference_snr_db=%g TB=%d errors=%d invocation=%d/%d\n', ...
                c.CaseID,p.InputSNRdB,n,errors,executed,budget);
            if n>=double(study.statistics.minimum_transport_blocks_per_point) && ...
                    errors>=double(study.statistics.minimum_errors_per_point)
                break;
            end
        end
        if isempty(state.Trials), break; end
        current=localSummary(state.Trials,c,p,study);
        reached=current.TransportBlockCount>=double(study.statistics.minimum_transport_blocks_per_point) && ...
            current.ErrorCount>=double(study.statistics.minimum_errors_per_point);
        capped=current.TransportBlockCount>=double(study.statistics.maximum_transport_blocks_per_point);
        if reached || capped
            state.Curve=[state.Curve;current]; %#ok<AGROW>
            state.Trials=table(); state.PointOrdinal=state.PointOrdinal+1;
        end
        if state.PointOrdinal>height(state.Points) && ~state.RefinementAdded
            state=localRefine(state,study);
        end
        localCheckpoint(casePath,state);
        displayCurve=state.Curve;
        if ~isempty(state.Trials), displayCurve=[displayCurve;current]; end %#ok<AGROW>
        writetable(sortrows(displayCurve,'ConfiguredSNR_dB'),fullfile(cf,'all_snr_curve.csv'));
        if study.outputs.save_png
            localPlot(displayCurve,fullfile(cf,'all_snr_curve.png'),study.outputs.png_dpi);
        end
    end
    caseComplete=state.PointOrdinal>height(state.Points) && state.RefinementAdded;
    allComplete=allComplete && caseComplete;
    summary=state.Curve;
    if ~isempty(state.Trials)
        p=state.Points(state.PointOrdinal,:);
        writetable(state.Trials,fullfile(cf,localPointName(p.InputSNRdB)+"_trials.csv"));
        summary=[summary;localSummary(state.Trials,c,p,study)]; %#ok<AGROW>
    end
    if ~isempty(summary)
        writetable(sortrows(summary,'ConfiguredSNR_dB'),fullfile(cf,'all_snr_curve.csv'));
        localMergeTrialCSVs(cf);
    end
    summaries=[summaries;summary]; %#ok<AGROW>
end
if ~isempty(summaries)
    writetable(summaries,fullfile(folder,'all_cases_all_snr.csv'));
    thresholds=sixgr.studies.ran1ai1032.extractF1CalibrationThresholds(summaries,study);
    if ~isempty(thresholds), writetable(thresholds,fullfile(folder,'calibration_thresholds.csv')); end
else, thresholds=table(); end
receipt=struct('RunFolder',folder,'TransportBlocksThisInvocation',executed, ...
    'SelectedCaseCount',height(C),'AllPointsComplete',allComplete, ...
    'ThresholdCount',height(thresholds),'CampaignIdentity',identity, ...
    'Status',"incomplete_resume_required");
if allComplete, receipt.Status="execution_complete_threshold_coverage_requires_validation"; end
save(fullfile(folder,'receipt.mat'),'receipt');
end
function localMergeTrialCSVs(folder)
% Point checkpoints remain recoverable; the public raw CSV contains every
% executed SNR point of this physical curve in one file, without rebinning.
files=dir(fullfile(folder,'snr_*_trials.csv'));
if isempty(files), return; end
target=fullfile(folder,'all_snr_trials.csv'); temporary=target+".partial.csv";
dst=fopen(temporary,'wb'); assert(dst>=0,'sixgr:ran1ai1032:F1CSV','Cannot write %s',temporary);
closeDst=onCleanup(@()fclose(dst));
header="";
for i=1:numel(files)
    src=fopen(fullfile(files(i).folder,files(i).name),'rb');
    assert(src>=0,'sixgr:ran1ai1032:F1CSV','Cannot read retained trial CSV.');
    closeSrc=onCleanup(@()fclose(src));
    thisHeader=string(fgetl(src));
    if i==1, header=thisHeader; fprintf(dst,'%s\n',header);
    else, assert(thisHeader==header,'sixgr:ran1ai1032:F1CSVSchema','Retained CSV schemas differ.'); end
    while ~feof(src)
        bytes=fread(src,1024*1024,'*uint8'); fwrite(dst,bytes,'uint8');
    end
    clear closeSrc;
end
clear closeDst;
[ok,msg]=movefile(temporary,target,'f'); assert(ok,'sixgr:ran1ai1032:F1CSV','%s',msg);
end

function localValidateTrial(T,c,p,cfg,out)
assert(~out.Skipped && height(T)==1 && contains(string(out.ExecutionBackend),'waveform'), ...
    'sixgr:ran1ai1032:F1PhysicalTrial','Expected exactly one executed PUSCH waveform trial.');
assert(T.BitsCompared==T.TBSize_bits && T.TBSize_bits>0 && ...
    T.Layers==c.Rank && T.PRBs==cfg.phy.carrier.NSizeGrid, ...
    'sixgr:ran1ai1032:F1TrialIdentity','Trial dimensions or compared TB identity do not match.');
assert(abs(T.TargetCodeRate-c.TargetCodeRate)<1e-12 && ...
    abs(T.ConfiguredSNR_dB-p.InputSNRdB)<1e-10 && abs(T.AppliedAWGNSNR_dB-p.InputSNRdB)<1e-10, ...
    'sixgr:ran1ai1032:F1NoiseBinding','Actual rate and applied noise must match the requested point.');
assert(T.MCS==cfg.phy.pusch.mcsIndex && T.NumRxAntennas==c.RxChains, ...
    'sixgr:ran1ai1032:F1PhysicalDimensions','Executed MCS or receive chains differ from configured case.');
assert(T.ChannelEstimateAvailable && T.EqualizationAvailable, ...
    'sixgr:ran1ai1032:F1ReceiverEvidence','Practical channel estimation/equalization must have executed.');
exactTBS=nrTBS(char(T.Modulation),double(T.Layers),double(T.PRBs), ...
    double(T.TBSInputNREPerPRB),double(T.TargetCodeRate),double(T.TBSInputXOverhead));
assert(double(T.TBSize_bits)==double(exactTBS), ...
    'sixgr:ran1ai1032:F1ExactTBS','Executed transport block differs from independent nrTBS.');
assert(~contains(lower(string(T.Notes)),["crash","fallback","synthetic","proxy"]), ...
    'sixgr:ran1ai1032:F1RejectedTrial','Execution failure must not become a physical BLER sample.');
end

function s=localSummary(T,c,p,study)
n=height(T); k=sum(~logical(T.CRCPass));
minN=double(study.statistics.minimum_transport_blocks_per_point);
minE=double(study.statistics.minimum_errors_per_point);
maxN=double(study.statistics.maximum_transport_blocks_per_point);
alpha=1-double(study.statistics.confidence_level);
% Simultaneous coverage over bounded per-TB looks protects error-based stop.
lookAlpha=alpha/maxN;
lo=0; hi=1;
if k>0, lo=betaincinv(lookAlpha/2,k,n-k+1); end
if k<n, hi=betaincinv(1-lookAlpha/2,k+1,n-k); end
s=table(c.CaseID,c.EntryID,c.ChannelProfile,c.DelaySpread_ns,c.AntennaCaseID, ...
    c.TxChains,c.RxChains,c.Rank,c.Qm,c.TargetCodeRateX1024,p.InputSNRdB,n,k, ...
    k/n,lo,hi,n>=minN && k>=minE,n>=maxN && (n<minN || k<minE), ...
    mean(double(T.MeasuredSINR_dB),'omitnan'),string(T.RFBranch(1)),string(T.RFProfileID(1)), ...
    string(T.PowerPlane(1)),string(T.ExecutionBackend(1)), ...
    "executed_phy_truth","BONFERRONI_BOUNDED_PER_TB_CLOPPER_PEARSON", ...
    'VariableNames',{'CaseID','EntryID','ChannelProfile','DelaySpread_ns', ...
    'AntennaCaseID','TxChains','RxChains','Rank','Qm','TargetCodeRateX1024', ...
    'ConfiguredSNR_dB','TransportBlockCount','ErrorCount','BLER','BLER_CI_Low', ...
    'BLER_CI_High','StatisticsComplete','Censored','MeanMeasuredSINR_dB', ...
    'RFBranch','RFProfileID','PowerPlane','ExecutionBackend','SourceClassification','IntervalMethod'});
end

function state=localRefine(state,study)
T=sortrows(state.Curve,'ConfiguredSNR_dB');
target=double(study.sls.adaptive_selection.target_first_transmission_bler);
steps=double(study.statistics.refinement_step_db);
for i=1:height(T)-1
    if T.StatisticsComplete(i) && T.StatisticsComplete(i+1) && ...
            T.BLER(i)>target && T.BLER(i+1)<=target
        values=(T.ConfiguredSNR_dB(i)+steps):steps:(T.ConfiguredSNR_dB(i+1)-steps/2);
        for value=values
            p=state.Points(1,:); p.InputSNRdB=value; p.PointStatus="refinement_pending";
            state.Points=[state.Points;p]; %#ok<AGROW>
        end
    end
end
state.RefinementAdded=true;
end

function seed=localSeed(pair,snrDB,n,base)
hash=char(sixgr.util.sha256Hex(uint8(unicode2native( ...
    string(base)+"|"+pair+"|"+compose('%.8f',snrDB)+"|"+string(n),'UTF-8'))));
seed=1+mod(hex2dec(hash(1:8)),2^31-2);
end
function name=localPointName(snrDB)
name="snr_"+replace(replace(compose('%.4f',snrDB),'-','minus_'),'.','p');
end
function localCheckpoint(path,state)
temporary=path+".partial.mat"; save(temporary,'state','-v7.3');
[ok,msg]=movefile(temporary,path,'f'); assert(ok,'sixgr:ran1ai1032:F1Checkpoint','%s',msg);
end
function localPlot(T,path,dpi)
T=sortrows(T,'ConfiguredSNR_dB');
f=figure('Visible','off'); clean=onCleanup(@()close(f)); %#ok<NASGU>
errorbar(T.ConfiguredSNR_dB,T.BLER,T.BLER-T.BLER_CI_Low,T.BLER_CI_High-T.BLER,'o-');
xlabel('Configured occupied-RE reference SNR (dB)'); ylabel('First-transmission BLER');
title(string(T.CaseID(1)),'Interpreter','none'); grid on;
ylim([0 1]); exportgraphics(f,path,'Resolution',double(dpi));
end
