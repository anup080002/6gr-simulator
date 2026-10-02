function out = calibrateSLSFTP3Loads(cases, policy, executeS0, outputFolder)
%CALIBRATESLSFTP3LOADS Measure S0 load, then freeze rates across comparators.
% executeS0(request) must execute the requested case/rate using its unchanged
% seed bundle and return SystemLevelRunner output. Each iteration/drop is
% persisted before its acceptance check. Bisection uses common random seeds.
arguments
    cases table
    policy struct
    executeS0 (1,1) function_handle
    outputFolder (1,1) string
end
localValidatePolicy(policy);
required = ["ComparatorID","CaseID","IndependentDropID","ExecutionParameters","TargetRUPercent"];
if ~all(ismember(required,string(cases.Properties.VariableNames)))
    error("sixgr:ran1ai1032:LoadCalibrationCases","Missing case identities or execution parameters.");
end
base = cases(string(cases.ComparatorID)=="S0",:);
if isempty(base), error("sixgr:ran1ai1032:LoadCalibrationS0Missing","Calibration requires S0 cases."); end
keys = sixgr.studies.ran1ai1032.slsLoadCalibrationKey(base);
groupKeys = unique(keys,"stable");
if ~isfolder(outputFolder), mkdir(outputFolder); end
if isfile(fullfile(outputFolder,"load_calibration_iterations.csv")) || ...
        isfile(fullfile(outputFolder,"frozen_ftp3_rates.csv"))
    error("sixgr:ran1ai1032:LoadCalibrationOutputExists", ...
        "Calibration evidence already exists; select a new output folder to preserve it.");
end
frozen = table(); history = table();
for g=1:numel(groupKeys)
    group = base(keys==groupKeys(g),:);
    if numel(unique(string(group.IndependentDropID)))~=height(group) || ...
            height(group)<policy.minimum_independent_drops
        error("sixgr:ran1ai1032:LoadCalibrationDrops", ...
            "S0 calibration requires unique independent drops and the configured minimum count.");
    end
    target = double(group.TargetRUPercent(1));
    if ~(isfinite(target) && target>0 && target<100)
        error("sixgr:ran1ai1032:LoadCalibrationTarget","Target RU must lie between 0 and 100 percent.");
    end
    lowerRate = 0; upperRate = NaN; rate = policy.initial_arrival_rate_per_cell_s;
    accepted = false;
    for iteration=1:policy.maximum_iterations
        totalOccupied=0; totalAvailable=0; evidenceHashes=strings(height(group),1);
        baseConfigHashes=strings(height(group),1);
        backendLabels=strings(height(group),1); calibrationHashes=strings(height(group),1);
        for d=1:height(group)
            folder=fullfile(outputFolder,groupKeys(g), ...
                sprintf('iteration_%03d',iteration),sprintf('drop_%03d',d));
            if ~isfolder(folder), mkdir(folder); end
            request=struct("Case",group(d,:),"ArrivalRatePerCell_s",rate, ...
                "Iteration",iteration,"OutputFolder",folder, ...
                "FirstMeasurementTTI",policy.warmup_tti+1);
            save(fullfile(folder,"request.mat"),"request");
            try
                result=executeS0(request);
                save(fullfile(folder,"runtime_result.mat"),"result","-v7.3");
                localValidateResult(result,group(d,:),rate);
                baseConfigHashes(d)=string(result.Details.LoadCalibrationBaseConfigSHA256);
                if result.Details.WaveformBacked
                    backendLabels(d)="waveform";
                else
                    backendLabels(d)=string(result.Details.ExecutionBackend);
                    calibrationHashes(d)=string(result.Details.CalibrationSHA256);
                end
                measured=sixgr.studies.ran1ai1032.measureSLSResourceUtilization( ...
                    result.Details.SchedulerGrants,result.Details.ResourceOpportunityTable, ...
                    "UL",policy.warmup_tti+1);
                writetable(measured.PerCellSlot,fullfile(folder,"resource_utilization.csv"));
            catch ME
                failure=struct("Identifier",string(ME.identifier), ...
                    "Message",string(ME.message),"CaseID",string(group.CaseID(d)));
                save(fullfile(folder,"failure.mat"),"failure");
                rethrow(ME);
            end
            totalOccupied=totalOccupied+measured.OccupiedPRBSymbols;
            totalAvailable=totalAvailable+measured.AvailablePRBSymbols;
            identity=struct("CaseID",string(group.CaseID(d)),"Rate",rate, ...
                "SeedBundle",result.Details.SeedBundle, ...
                "Occupied",measured.OccupiedPRBSymbols,"Available",measured.AvailablePRBSymbols, ...
                "GrantSHA256",localHash(table2struct(result.Details.SchedulerGrants)), ...
                "OpportunitySHA256",localHash(table2struct(result.Details.ResourceOpportunityTable)), ...
                "ArrivalSHA256",localHash(table2struct(result.Details.TrafficArrivalEvents)));
            evidenceHashes(d)=localHash(identity);
        end
        if numel(unique(baseConfigHashes))~=1
            error("sixgr:ran1ai1032:LoadCalibrationConfigChanged", ...
                "A calibration group must execute one unchanged base runtime configuration.");
        end
        if numel(unique(backendLabels))~=1 || numel(unique(calibrationHashes))~=1
            error('sixgr:ran1ai1032:LoadCalibrationConfigChanged', ...
                'A calibration group cannot mix waveform/abstraction backends or different BLER calibration datasets.');
        end
        if iteration>1 && (baseConfigHashes(1)~=previousBaseHash || ...
                backendLabels(1)~=previousBackend || calibrationHashes(1)~=previousCalibrationHash)
            error("sixgr:ran1ai1032:LoadCalibrationConfigChanged", ...
                "The base runtime configuration, backend or BLER calibration changed during load calibration.");
        end
        previousBaseHash=baseConfigHashes(1);
        previousBackend=backendLabels(1);
        previousCalibrationHash=calibrationHashes(1);
        measuredRU=100*totalOccupied/totalAvailable;
        r=table(groupKeys(g),iteration,rate,target,measuredRU,totalOccupied,totalAvailable, ...
            height(group),localHash(evidenceHashes), ...
            'VariableNames',{'CalibrationKey','Iteration','ArrivalRatePerCell_s', ...
            'TargetRUPercent','MeasuredRUPercent','OccupiedPRBSymbols','AvailablePRBSymbols', ...
            'IndependentDropCount','EvidenceSHA256'});
        r.PHYExecutionMode=backendLabels(1);
        r.LinkCalibrationSHA256=calibrationHashes(1);
        history=[history;r]; %#ok<AGROW>
        writetable(history,fullfile(outputFolder,"load_calibration_iterations.csv"));
        if abs(measuredRU-target)<=policy.tolerance_percentage_points
            accepted=true;
            r.ComparatorID="S0"; r.Status="calibrated_measured_S0";
            r.FirstMeasurementTTI=policy.warmup_tti+1;
            r.TolerancePercentagePoints=policy.tolerance_percentage_points;
            r.PolicySHA256=localHash(policy);
            r.BaseConfigSHA256=baseConfigHashes(1);
            r.RUDefinition=measured.Definition;
            r.CalibrationSHA256=localHash(table2struct(r));
            frozen=[frozen;r]; %#ok<AGROW>
            writetable(frozen,fullfile(outputFolder,"frozen_ftp3_rates.csv"));
            save(fullfile(outputFolder,"frozen_ftp3_rates.mat"),"frozen","policy");
            break
        end
        if measuredRU<target, lowerRate=rate; else, upperRate=rate; end
        if isnan(upperRate)
            nextRate=min(rate*policy.bracket_expansion_factor,policy.maximum_arrival_rate_per_cell_s);
        else
            nextRate=(lowerRate+upperRate)/2;
        end
        if nextRate==rate, break; end
        rate=nextRate;
    end
    if ~accepted
        error("sixgr:ran1ai1032:LoadCalibrationDidNotConverge", ...
            "S0 key %s reached %.4f%% RU versus %.4f%% target; retained measured iterations at %s.", ...
            groupKeys(g),measuredRU,target,outputFolder);
    end
end
out=struct("Ok",true,"Rates",frozen,"Iterations",history,"OutputFolder",outputFolder);
end

function localValidatePolicy(p)
required=["initial_arrival_rate_per_cell_s","maximum_arrival_rate_per_cell_s", ...
    "bracket_expansion_factor","maximum_iterations","tolerance_percentage_points", ...
    "minimum_independent_drops","warmup_tti"];
for name=required
    if ~isfield(p,name) || ~isnumeric(p.(name)) || ~isscalar(p.(name)) || ~isfinite(p.(name))
        error("sixgr:ran1ai1032:LoadCalibrationPolicy","Missing/invalid scalar policy field %s.",name);
    end
end
if p.initial_arrival_rate_per_cell_s<=0 || p.maximum_arrival_rate_per_cell_s<p.initial_arrival_rate_per_cell_s || ...
        p.bracket_expansion_factor<=1 || p.maximum_iterations<1 || p.maximum_iterations~=fix(p.maximum_iterations) || ...
        p.tolerance_percentage_points<=0 || p.tolerance_percentage_points>=100 || ...
        p.minimum_independent_drops<1 || p.minimum_independent_drops~=fix(p.minimum_independent_drops) || ...
        p.warmup_tti<0 || p.warmup_tti~=fix(p.warmup_tti)
    error("sixgr:ran1ai1032:LoadCalibrationPolicy","Load-calibration bounds/counts/tolerance are invalid.");
end
end

function localValidateResult(r,c,rate)
if ~isstruct(r) || ~isfield(r,"Ok") || ~r.Ok || ~isfield(r,"Details")
    error("sixgr:ran1ai1032:LoadCalibrationRunFailed","S0 runner did not complete successfully.");
end
d=r.Details;
fields=["WaveformBacked","ProxyPHYActive","FallbackUsed","SeedBundle", ...
    "SchedulerGrants","ResourceOpportunityTable","TrafficArrivalEvents","TrafficModel", ...
    "TrafficArrivalRatePerCell_s","LoadCalibrationBaseConfigSHA256","DecodeUnavailableUL"];
waveform=logical(sixgr.util.structGet(d,'WaveformBacked',false)) && ...
    ~logical(sixgr.util.structGet(d,'ProxyPHYActive',true));
abstract=string(sixgr.util.structGet(d,'ExecutionBackend',''))=="CALIBRATED_LINK_ABSTRACTION" && ...
    ~logical(sixgr.util.structGet(d,'WaveformBacked',true)) && ...
    logical(sixgr.util.structGet(d,'ProxyPHYActive',false)) && ...
    logical(sixgr.util.structGet(d,'CalibrationQualified',false)) && ...
    string(sixgr.util.structGet(d,'SourceClassification',''))=="calibrated_sls_estimate_not_waveform_truth" && ...
    strlength(string(sixgr.util.structGet(d,'CalibrationSHA256','')))==64;
if ismember('PlannedExecutionArchitecture',c.Properties.VariableNames)
    if string(c.PlannedExecutionArchitecture)=="calibrated_link_abstraction", waveform=false;
    else, abstract=false; end
else
    abstract=false; % Legacy receipts cannot silently change their PHY definition.
end
if ~all(isfield(d,fields)) || ~(waveform || abstract) || d.FallbackUsed || ...
        lower(string(d.TrafficModel))~="ftp3" || ...
        ~isequal(double(d.TrafficArrivalRatePerCell_s),double(rate)) || ...
        strlength(string(d.LoadCalibrationBaseConfigSHA256))~=64 || ...
        any(~isfinite(double(d.DecodeUnavailableUL))) || any(double(d.DecodeUnavailableUL)~=0) || ...
        ~isequaln(d.SeedBundle,c.ExecutionParameters{1}.SeedBundle) || ...
        ~istable(d.TrafficArrivalEvents)
    error("sixgr:ran1ai1032:LoadCalibrationEvidence", ...
        "S0 calibration requires the planned waveform or qualified calibrated backend, frozen seeds, FTP3 arrivals and exact resource evidence.");
end
end

function h=localHash(v)
h=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(v)),"UTF-8"))));
end
