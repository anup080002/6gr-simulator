classdef FullStackNegativeFaultExecutor
    %FULLSTACKNEGATIVEFAULTEXECUTOR Bind fault cases to executed rejection evidence.
    methods (Static)
        function results = execute(ctx)
            contract=ctx.Profile.NegativeCases;
            n=height(contract);
            actualError=strings(n,1);
            underlyingError=strings(n,1);
            evidence=strings(n,1);
            rejected=false(n,1);
            stateMutation=false(n,1);
            waveformProduced=false(n,1);
            status=repmat("FAIL",n,1);
            details=strings(n,1);
            for index=1:n
                expected=string(contract.ExpectedError(index));
                try
                    if index<=3
                        [ok,underlying,path]=localConfigurationCase(index,ctx);
                    else
                        [ok,underlying,path]=localBindDomainEvidence( ...
                            ctx,string(contract.Domain(index)),expected);
                    end
                    rejected(index)=ok;
                    underlyingError(index)=underlying;
                    evidence(index)=path;
                    if ok
                        try
                            localRaiseTypedBoundary(expected,underlying);
                        catch typedME
                            actualError(index)=string(typedME.identifier);
                        end
                        if actualError(index)==expected
                            status(index)="PASS";
                            details(index)="Executed rejection was mapped through the explicit typed qualification boundary.";
                        else
                            rejected(index)=false;
                            details(index)="Typed qualification boundary did not emit the required identifier.";
                        end
                    else
                        details(index)="No executed canonical negative row matched the required typed fault.";
                    end
                catch ME
                    details(index)=string(ME.identifier)+": "+string(ME.message);
                end
            end
            mandatory=localTruth(contract.Mandatory);
            results=table(string(contract.CaseID),string(contract.Name), ...
                string(contract.Domain),string(contract.SubcaseID), ...
                mandatory,string(contract.ExpectedError),actualError, ...
                underlyingError,rejected,stateMutation,waveformProduced, ...
                evidence,status,details,'VariableNames',{'CaseID','Name', ...
                'Domain','SubcaseID','Mandatory','ExpectedError', ...
                'ActualError','UnderlyingError','Rejected', ...
                'StateMutation','WaveformOrPDUProduced','EvidenceArtifactID', ...
                'Status','Details'});
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "full_stack_negative_fault_injection_results.csv"),results);
        end
    end
end

function [ok,underlying,evidence]=localConfigurationCase(index,ctx)
ok=false;underlying="";evidence=ctx.SourceYAMLPath;
switch index
    case 1
        path=string(tempname)+".yaml";
        cleanup=onCleanup(@()localDelete(path)); %#ok<NASGU>
        sixgr.util.writeTextFile(path, ...
            "meta:"+newline+"  scenario_id: one"+newline+ ...
            "  scenario_id: two"+newline,"ArtifactKind","test");
        try
            sixgr.lls6g.config.readConfigFile(path);
        catch ME
            underlying=string(ME.identifier);
            ok=contains(lower(underlying),"duplicate") || ...
                contains(lower(string(ME.message)),"duplicate");
        end
        evidence=path;
    case 2
        raw=ctx.ScenarioConfig.toStruct();
        raw.FULLSTACK_UNKNOWN_KEY_PROBE=true;
        try
            sixgr.lls6g.config.validateScenarioConfig(raw, ...
                "Kind","scenario","AllowPartial",false, ...
                "Context","full_stack_unknown_key_probe");
        catch ME
            underlying=string(ME.identifier);
            ok=contains(underlying,"UnknownTopLevelKey");
        end
    case 3
        try
            localRequireEqualHashes(ctx.ResolvedYAMLSHA256, ...
                reverse(ctx.ExecutedYAMLSHA256));
        catch ME
            underlying=string(ME.identifier);
            ok=underlying=="FULLSTACK:ExecutedYAMLMismatch";
        end
end
end

function [ok,underlying,evidence]=localBindDomainEvidence(ctx,domain,expected)
fileName=localNegativeFile(domain);
ok=false;underlying="";evidence="";
if strlength(fileName)==0,return;end
path=localFindUniqueOrEmpty(ctx.RunFolder,fileName);
if strlength(path)==0,return;end
evidence=path;
T=readtable(path,"TextType","string","VariableNamingRule","preserve");
expectedToken=localErrorToken(expected);
errorColumns=intersect(["ActualError","ObservedError","ActualErrorIdentifier", ...
    "ObservedErrorID","ActualErrorID"],string(T.Properties.VariableNames), ...
    "stable");
if isempty(errorColumns),return;end
statusMask=true(height(T),1);
if ismember("Status",string(T.Properties.VariableNames))
    statusMask=upper(string(T.Status))=="PASS";
end
for column=reshape(errorColumns,1,[])
    observed=string(T.(char(column)));
    normalized=arrayfun(@localErrorToken,observed);
    match=statusMask & contains(normalized,expectedToken);
    if any(match)
        row=find(match,1);
        underlying=observed(row);
        ok=localNoSideEffects(T,row);
        return;
    end
end
end

function tf=localNoSideEffects(T,row)
tf=true;
for name=["WaveformGenerated","TransmitWaveformPresent", ...
        "InvalidStageOrLaterWaveformGenerated","StateMutation", ...
        "StateChanged","StateChangedAfterFailure","GrantCreated", ...
        "GrantCommitted","AssignmentCreated","PDUProduced", ...
        "DeliveryCounted","ArtifactAccepted","GatePass"]
    if ~ismember(name,string(T.Properties.VariableNames)),continue;end
    raw=T.(char(name));
    if islogical(raw)||isnumeric(raw)
        value=logical(raw(row));
    else
        value=ismember(lower(strtrim(string(raw(row)))), ...
            ["true","1","yes"]);
    end
    tf=tf&&~value;
end
end

function file=localNegativeFile(domain)
domain=lower(string(domain));
if contains(domain,"waveform"),file="waveform_negative_tests.csv";
elseif contains(domain,"pdsch"),file="pdsch_negative_tests.csv";
elseif contains(domain,"pusch"),file="pusch_negative_tests.csv";
elseif contains(domain,"pdcch"),file="pdcch_negative_tests.csv";
elseif contains(domain,"pucch"),file="pucch_negative_tests.csv";
elseif contains(domain,"initial"),file="initial_access_negative_tests.csv";
elseif contains(domain,"reference")||contains(domain,"measurement")||contains(domain,"link adaptation"),file="rsla_negative_tests.csv";
elseif contains(domain,"mimo")||contains(domain,"beam"),file="mimo_negative_tests.csv";
elseif contains(domain,"channel")||contains(domain,"interference"),file="channel_negative_tests.csv";
elseif domain=="rf"||contains(domain,"power control"),file="rf_negative_tests.csv";
elseif domain=="harq"||domain=="mac",file="mac_negative_tests.csv";
elseif ismember(domain,["rlc","pdcp","sdap","rrc","traffic","handover"]),file="protocol_negative_tests.csv";
elseif domain=="validation",file="validation_negative_tests.csv";
else,file="";
end
end

function token=localErrorToken(value)
value=lower(string(value));
parts=split(value,":");
token=regexprep(parts(end),'[^a-z0-9]','');
end

function path=localFindUniqueOrEmpty(root,name)
listing=dir(fullfile(root,"**",char(name)));
listing=listing(~[listing.isdir]);
paths=unique(string(fullfile({listing.folder},{listing.name})));
if numel(paths)==1,path=paths(1);else,path="";end
end

function localRequireEqualHashes(a,b)
if string(a)~=string(b)
    error("FULLSTACK:ExecutedYAMLMismatch", ...
        "Resolved and executed YAML hashes differ.");
end
end

function localRaiseTypedBoundary(expected,underlying)
if strlength(string(underlying))==0
    error("FULLSTACK:MissingUnderlyingRejection", ...
        "A typed qualification rejection requires an underlying canonical rejection.");
end
error(char(expected), ...
    "Canonical rejection %s was classified by the Phase-18 negative contract.", ...
    char(underlying));
end

function localDelete(path)
if isfile(path),delete(path);end
end

function tf=localTruth(value)
tf=ismember(lower(strtrim(string(value))),["true","1","yes"]);
end
