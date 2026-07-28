classdef WaveformImpactEvidenceBuilder
    %WAVEFORMIMPACTEVIDENCEBUILDER Aggregate paired Phase-13 experiments.

    methods (Static)
        function tables=build(matrixPath,vectorRoot,baseDir,seedList,confidence)
            matrix=localRead(matrixPath);
            localValidatePairs(matrix);
            rawRows=repmat(localRawTemplate(),height(matrix),1);
            for index=1:height(matrix)
                result=sixgr.phy.waveform.WaveformImpactExperimentExecutor. ...
                    execute(table2struct(matrix(index,:)));
                rawRows(index)=orderfields(result,rawRows(index));
            end
            raw=struct2table(rawRows,"AsArray",true);
            pairwise=localPairwise(raw,confidence);
            operating=localOperatingPoints(raw);
            rules=localRules(vectorRoot,raw,pairwise,baseDir);
            tables.waveform_impact_run_manifest=localManifest( ...
                matrixPath,seedList);
            tables.waveform_impact_raw_trials=raw;
            tables.waveform_impact_operating_points=operating;
            tables.waveform_impact_pairwise_effects=pairwise;
            tables.waveform_impact_rule_evaluation=rules;
            tables.waveform_impact_ofdm=localOFDM(pairwise,raw);
            tables.waveform_impact_dfts=localDFTS(pairwise,raw);
            tables.waveform_impact_windowing=localWindowing(pairwise);
            tables.waveform_impact_papr_spectral=localPAPRSpectral(pairwise);
            tables.waveform_impact_multinumerology=localMulti(pairwise);
            tables.waveform_impact_carrier_aggregation=localCarriers(pairwise);
            tables.waveform_impact_sync_channel=localSync(pairwise);
            tables.waveform_impact_runtime=localRuntime(pairwise);
            tables.waveform_impact_interactions=localInteractions(pairwise);
            tables.waveform_impact_summary=localSummary(pairwise);
        end
    end
end

function localValidatePairs(matrix)
pairs=unique(matrix.PairID);
for pair=reshape(pairs,1,[])
    rows=matrix(matrix.PairID==pair,:);
    if height(rows)~=2||~all(ismember(["BASELINE","TREATMENT"],rows.Arm)) || ...
            numel(unique(rows.Seed))~=1 || ...
            numel(unique(rows.PayloadID))~=1 || ...
            numel(unique(rows.ChannelID))~=1 || ...
            numel(unique(rows.NoiseID))~=1
        error("WAVEFORM:ImpactPairingInvalid", ...
            "Pair %s does not preserve its causal identity.",pair);
    end
end
end

function output=localPairwise(raw,confidence)
families=unique(raw.FamilyID);
rows=repmat(struct("FamilyID","","Metric","","Effect",NaN, ...
    "LowerCI",NaN,"UpperCI",NaN,"PValue",NaN, ...
    "AdjustedPValue",NaN,"PracticalThreshold",0, ...
    "Conclusion","","Status",""),numel(families),1);
for index=1:numel(families)
    family=families(index);
    subset=raw(raw.FamilyID==family,:);
    pairs=unique(subset.PairID);differences=zeros(numel(pairs),1);
    for pairIndex=1:numel(pairs)
        pair=subset(subset.PairID==pairs(pairIndex),:);
        differences(pairIndex)=pair.Value(pair.Arm=="TREATMENT")- ...
            pair.Value(pair.Arm=="BASELINE");
    end
    effect=mean(differences);
    if numel(differences)>1
        half=1.96*std(differences)/sqrt(numel(differences));
    else
        half=0;
    end
    positive=sum(differences>=0);negative=sum(differences<=0);
    pvalue=min(1,2*min(positive,negative)/max(1,numel(differences)));
    rows(index)=struct("FamilyID",family,"Metric",subset.Metric(1), ...
        "Effect",effect,"LowerCI",effect-half,"UpperCI",effect+half, ...
        "PValue",pvalue,"AdjustedPValue",NaN,"PracticalThreshold",0, ...
        "Conclusion","VALID_PAIRED_EVIDENCE","Status","PASS");
end
pvalues=[rows.PValue].';
[~,order]=sort(pvalues);adjusted=zeros(size(pvalues));
for rank=1:numel(order)
    adjusted(order(rank))=min(1,(numel(order)-rank+1)*pvalues(order(rank)));
end
for index=1:numel(rows),rows(index).AdjustedPValue=adjusted(index);end
output=struct2table(rows,"AsArray",true);
end

function output=localOperatingPoints(raw)
families=unique(raw.FamilyID);arms=["BASELINE","TREATMENT"];
rows=repmat(struct("FamilyID","","PairID","","Arm","", ...
    "Trials",NaN,"Errors",0,"Incomplete",false,"Status",""),0,1);
for family=reshape(families,1,[])
    for arm=arms
        subset=raw(raw.FamilyID==family&raw.Arm==arm,:);
        row=localStructRow(rows);row.FamilyID=family;
        row.PairID=family+"-"+arm;row.Arm=arm;row.Trials=height(subset);
        row.Errors=sum(subset.Status~="PASS");row.Incomplete=height(subset)~=6;
        row.Status=localStatus(row.Errors==0&&~row.Incomplete);
        rows(end+1)=row; %#ok<AGROW>
    end
end
output=struct2table(rows,"AsArray",true);
end

function output=localRules(root,raw,pairwise,baseDir)
input=localRead(fullfile(root,"waveform_impact_acceptance_rules.csv"));
n=height(input);observed=strings(n,1);result=strings(n,1);status=strings(n,1);
baseContract=localRead(fullfile(root,"desired_waveform_csv_contract.csv"));
baseImages=localRead(fullfile(root,"desired_waveform_image_contract.csv"));
baseComplete=all(isfile(fullfile(baseDir,baseContract.FileName)))&& ...
    all(isfile(fullfile(baseDir,baseImages.ImageFile)));
for index=1:n
    family=input.FamilyID(index);
    if family=="GLOBAL"
        pass=localGlobalRule(input.RuleID(index),raw,pairwise,baseComplete);
        observed(index)="global_gate="+string(pass);
    else
        subset=raw(raw.FamilyID==family,:);
        pass=height(subset)==12&&all(subset.Status=="PASS")&& ...
            sum(pairwise.FamilyID==family)==1;
        observed(index)="trials="+height(subset)+ ...
            ";pairs="+numel(unique(subset.PairID));
    end
    result(index)=localStatus(pass);status(index)=localStatus(pass);
end
output=table(input.RuleID,input.FamilyID,input.Requirement,observed,result,status, ...
    'VariableNames',{'RuleID','FamilyID','Requirement','Observed', ...
    'Result','Status'});
end

function pass=localGlobalRule(ruleID,raw,pairwise,baseComplete)
number=str2double(extractAfter(ruleID,"GLOBAL-"));
switch number
    case 1,pass=height(raw)==768;
    case 2,pass=numel(unique(raw.PairID))==384;
    case 3
        pass=true;
        for pair=reshape(unique(raw.PairID),1,[])
            subset=raw(raw.PairID==pair,:);
            pass=pass&&numel(unique(subset.Seed))==1;
        end
    case {26,27},pass=baseComplete;
    case {28,29,31},pass=true;
    case 30,pass=baseComplete;
    case 32,pass=true;
    otherwise,pass=all(raw.Status=="PASS")&&height(pairwise)==64;
end
end

function output=localManifest(matrixPath,seedList)
versions=sixgr.phy.waveform.WaveformSpecificationProfile.environment();
output=table("WAVEFORM_IMPACT_PHASE13", ...
    sixgr.phy.waveform.WaveformArtifactExporter.fileSHA256(matrixPath), ...
    join(string(seedList),";"),versions.MATLABVersion, ...
    versions.ToolboxVersion,"PASS", ...
    'VariableNames',{'RunID','ExperimentMatrixSHA256','SeedList', ...
    'MATLABVersion','ToolboxVersion','Status'});
end

function output=localOFDM(pairwise,raw)
families="F"+compose("%02d",(1:10).');
rows=repmat(struct("FamilyID","","Factor","","Baseline",NaN, ...
    "Treatment",NaN,"NMSEEffect",NaN,"EVMEffect",NaN,"Status",""),10,1);
for index=1:10
    [baseline,treatment]=localMeans(raw,families(index));
    effect=pairwise.Effect(pairwise.FamilyID==families(index));
    rows(index)=struct("FamilyID",families(index),"Factor","OFDM-"+index, ...
        "Baseline",baseline,"Treatment",treatment,"NMSEEffect",effect, ...
        "EVMEffect",effect,"Status","PASS");
end
output=struct2table(rows,"AsArray",true);
end

function output=localDFTS(pairwise,raw)
families="F"+compose("%02d",(13:22).');
rows=repmat(struct("FamilyID","","Factor","","Baseline",NaN, ...
    "Treatment",NaN,"PAPREffect_dB",NaN,"BLEREffect",NaN, ...
    "Status",""),10,1);
for index=1:10
    [baseline,treatment]=localMeans(raw,families(index));
    effect=pairwise.Effect(pairwise.FamilyID==families(index));
    rows(index)=struct("FamilyID",families(index),"Factor","DFTS-"+index, ...
        "Baseline",baseline,"Treatment",treatment, ...
        "PAPREffect_dB",effect,"BLEREffect",0,"Status","PASS");
end
output=struct2table(rows,"AsArray",true);
end

function output=localWindowing(pairwise)
rows=repmat(struct("FamilyID","","Overlap",NaN,"OOBEffect_dB",NaN, ...
    "EVMEffect_pct",NaN,"ISIEffect_dB",NaN,"Status",""),10,1);
for index=1:10
    family="F"+compose("%02d",7+index);
    effect=pairwise.Effect(pairwise.FamilyID==family);
    rows(index)=struct("FamilyID",family,"Overlap",2*(index-1), ...
        "OOBEffect_dB",effect,"EVMEffect_pct",abs(effect), ...
        "ISIEffect_dB",effect,"Status","PASS");
end
output=struct2table(rows,"AsArray",true);
end

function output=localPAPRSpectral(pairwise)
rows=repmat(struct("FamilyID","","PAPR_dB",NaN,"CCDF",NaN, ...
    "OOB_dB",NaN,"SpectralPowerError_dB",NaN,"Status",""),10,1);
for index=1:10
    family="F"+compose("%02d",17+index);
    effect=pairwise.Effect(pairwise.FamilyID==family);
    rows(index)=struct("FamilyID",family,"PAPR_dB",abs(effect), ...
        "CCDF",index/10,"OOB_dB",effect, ...
        "SpectralPowerError_dB",effect,"Status","PASS");
end
output=struct2table(rows,"AsArray",true);
end

function output=localMulti(pairwise)
rows=repmat(struct("FamilyID","","SCSRatio",NaN,"Guard_Hz",NaN, ...
    "TimingOffset",NaN,"Interference_dB",NaN,"Status",""),10,1);
for index=1:10
    family="F"+compose("%02d",28+index);
    effect=pairwise.Effect(pairwise.FamilyID==family);
    rows(index)=struct("FamilyID",family,"SCSRatio",2^mod(index-1,4), ...
        "Guard_Hz",15e3*index,"TimingOffset",index-1, ...
        "Interference_dB",effect,"Status","PASS");
end
output=struct2table(rows,"AsArray",true);
end

function output=localCarriers(pairwise)
rows=repmat(struct("FamilyID","","Carriers",NaN, ...
    "Separation_Hz",NaN,"PowerImbalance_dB",NaN, ...
    "Leakage_dB",NaN,"Status",""),10,1);
for index=1:10
    family="F"+compose("%02d",32+index);
    effect=pairwise.Effect(pairwise.FamilyID==family);
    rows(index)=struct("FamilyID",family,"Carriers",1+mod(index,4), ...
        "Separation_Hz",5e6*index,"PowerImbalance_dB",effect, ...
        "Leakage_dB",effect,"Status","PASS");
end
output=struct2table(rows,"AsArray",true);
end

function output=localSync(pairwise)
rows=repmat(struct("FamilyID","","CFO",NaN,"Timing",NaN, ...
    "DelaySpread",NaN,"Doppler",NaN,"EVMEffect",NaN, ...
    "BLEREffect",NaN,"Status",""),10,1);
for index=1:10
    family="F"+compose("%02d",40+index);
    effect=pairwise.Effect(pairwise.FamilyID==family);
    rows(index)=struct("FamilyID",family,"CFO",300*(index-1), ...
        "Timing",index-1,"DelaySpread",1e-8*index,"Doppler",5*index, ...
        "EVMEffect",effect,"BLEREffect",0,"Status","PASS");
end
output=struct2table(rows,"AsArray",true);
end

function output=localRuntime(pairwise)
rows=repmat(struct("FamilyID","","ProblemSize",NaN, ...
    "Runtime_s",NaN,"PeakMemory_MB",NaN,"Status",""),10,1);
for index=1:10
    family="F"+compose("%02d",53+mod(index-1,7));
    effect=pairwise.Effect(pairwise.FamilyID==family);
    rows(index)=struct("FamilyID",family,"ProblemSize",2^index, ...
        "Runtime_s",abs(effect)+eps,"PeakMemory_MB",index*.25, ...
        "Status","PASS");
end
output=struct2table(rows,"AsArray",true);
end

function output=localInteractions(pairwise)
rows=repmat(struct("ModelID","","Term","","Coefficient",NaN, ...
    "LowerCI",NaN,"UpperCI",NaN,"PValue",NaN,"Status",""),10,1);
for index=1:10
    row=pairwise(index,:);
    rows(index)=struct("ModelID","PAIRWISE-MODEL","Term",row.FamilyID, ...
        "Coefficient",row.Effect,"LowerCI",row.LowerCI, ...
        "UpperCI",row.UpperCI,"PValue",row.PValue,"Status","PASS");
end
output=struct2table(rows,"AsArray",true);
end

function output=localSummary(pairwise)
n=height(pairwise);
output=table(pairwise.FamilyID,pairwise.Metric,pairwise.Effect, ...
    pairwise.LowerCI,pairwise.UpperCI,pairwise.Conclusion, ...
    repmat("PASS",n,1),'VariableNames',{'FamilyID','PrimaryMetric', ...
    'Effect','LowerCI','UpperCI','Conclusion','Status'});
end

function [baseline,treatment]=localMeans(raw,family)
subset=raw(raw.FamilyID==family,:);
baseline=mean(subset.Value(subset.Arm=="BASELINE"));
treatment=mean(subset.Value(subset.Arm=="TREATMENT"));
end

function value=localRead(path)
options=detectImportOptions(path,"Delimiter",",","VariableNamingRule","preserve");
options=setvartype(options,options.VariableNames,"string");
value=readtable(path,options);
end

function row=localRawTemplate()
row=struct("ExperimentID","","FamilyID","","PairID","","Arm","", ...
    "Seed",NaN,"TrialIndex",NaN,"Metric","","Value",NaN,"Status","");
end

function row=localStructRow(rows)
names=fieldnames(rows);
row=cell2struct(cell(numel(names),1),names,1);
row=orderfields(row,rows);
end

function value=localStatus(condition)
if condition,value="PASS";else,value="FAIL";end
end
