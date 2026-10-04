function result = evaluateComponentControlEvidence(cfg, rawTrials, component)
%EVALUATECOMPONENTCONTROLEVIDENCE Check isolated executed control PHY rows.
% No new waveform, identity binding, outcome substitution or connected-grant
% claim is made here. Statistical detector qualification is a separate gate.
component = lower(string(component));
assert(isscalar(component) && ismember(component,["pdcch","pucch"]), ...
    'sixgr:truth:UnsupportedComponentControl','Expected PDCCH or PUCCH.');
T = sixgr.util.structGet(rawTrials,upper(component),table());
assert(istable(T),'sixgr:truth:ComponentControlTableRequired', ...
    'Component control evidence must be an executed trial table.');
failure = "";
pass = false(height(T),1);
if isempty(T)
    failure = "missing_component_"+component+"_rows";
else
    n = height(T);
    scope = localText(T,"EvidenceScope")=="component_anchor" & ...
        localNumber(T,"SameScenarioInPathEligible")==0;
    expected = [string(sixgr.util.structGet(cfg,"run.scenarioID","")), ...
        lower(string(sixgr.util.structGet(cfg,"meta.configHash",""))), ...
        string(sixgr.util.structGet(cfg,"run.runTag","")), ...
        string(sixgr.util.structGet(cfg,"run.executionID", ...
        sixgr.util.structGet(cfg,"meta.executionID","")))];
    identity = true(n,1);
    names = ["ScenarioID","ConfigHash","RunID","ExecutionID"];
    for k=1:numel(names)
        identity = identity & strlength(expected(k))>0 & ...
            localText(T,names(k))==expected(k);
    end
    identity = identity & ~isempty(regexp(char(expected(2)), ...
        '^[0-9a-f]{64}$','once'));
    truth = true(n,1);
    for flag=["Crash","Skipped","ToolboxMissing","ProxyUsed", ...
            "FallbackFlag","PlaceholderFlag"]
        if ismember(flag,string(T.Properties.VariableNames))
            truth = truth & localNumber(T,flag)==0;
        end
    end
    for name=["SourceClassification","ExecutionBackend","ApproximationMode","E2EAirModel"]
        value = lower(localText(T,name));
        for forbidden=["proxy","fallback","synthetic","logistic","lookup"]
            truth = truth & ~contains(value,forbidden);
        end
        truth = truth & value~="lut";
    end
    receiver = localText(T,"Status")=="PASS";
    for flag=["StrictOk","ReceiverUsable","DecodeUsable", ...
            "StrictReceiverEvidenceOk","ResourceExtractionAvailable", ...
            "ChannelEstimateAvailable"]
        receiver = receiver & localNumber(T,flag)==1;
    end
    if component=="pdcch"
        compared=localNumber(T,"PDCCHDCIBitsCompared");
        expectedBits=localNumber(T,"PDCCHExpectedDCIBitCount");
        decodedBits=localNumber(T,"PDCCHDecodedDCIBitCount");
        receiver=receiver & localNumber(T,"DCICrcPass")==1 & ...
            localNumber(T,"PDCCHPayloadMatch")==1 & ...
            localNumber(T,"PDCCHReceiverTrialExecuted")==1 & ...
            localNumber(T,"PDCCHDCIBitErrors")==0;
        % GrantValid is deliberately not asserted: this component decodes
        % DCI but does not establish an issued connected-runtime grant.
    else
        compared=localNumber(T,"BitsCompared");
        expectedBits=localNumber(T,"ExpectedBitCount");
        decodedBits=localNumber(T,"DecodedBitCount");
        applicable=localNumber(T,"CRCApplicable");
        receiver=receiver & localNumber(T,"UCIContentMatch")==1 & ...
            localNumber(T,"BitErrors")==0 & ...
            localNumber(T,"DetectionAttempted")==1 & ...
            localNumber(T,"DetectionUsable")==1 & ...
            (applicable==0 | (applicable==1 & localNumber(T,"CRCPass")==1));
    end
    receiver=receiver & isfinite(compared) & compared>0 & compared==fix(compared) & ...
        compared==expectedBits & compared==decodedBits;
    pass=scope & identity & truth & receiver;
    if ~all(scope), failure="component_scope_missing_or_conflicting";
    elseif ~all(identity), failure="component_execution_identity_mismatch";
    elseif ~all(truth), failure="nonphysical_or_incomplete_component_rows";
    elseif ~all(receiver), failure="component_receiver_decode_failure";
    end
end
strictOk=~isempty(pass) && all(pass);
result=struct("Ok",strictOk,"StrictOk",strictOk, ...
    "FailureReason",failure,"EvidenceScope","component_anchor", ...
    "SameScenarioInPathEligible",false,"InPathRuntimeValidationComplete",false, ...
    "RuntimeEvidenceSource","isolated_component_waveform", ...
    "StatisticalDetectorQualified",false,"LaunchedSupplementalWaveform",false, ...
    "PassingRowCount",nnz(pass),"TrialRowCount",height(T), ...
    "ValidationAuthority","sixgr.truth.evaluateComponentControlEvidence/v1", ...
    "SourceTableSHA256",sixgr.kpi.hashKPISourceRows(T), ...
    "ArtifactTables",struct(char(component+"_trials"),T));
end

function value=localNumber(T,name)
value=nan(height(T),1);
if ismember(name,string(T.Properties.VariableNames))
    raw=T.(name);
    if isnumeric(raw) || islogical(raw), value=double(raw(:));
    else, value=str2double(string(raw(:))); end
end
end

function value=localText(T,name)
value=repmat("",height(T),1);
if ismember(name,string(T.Properties.VariableNames))
    value=strtrim(string(T.(name)));
    value(ismissing(value))="";
end
end
