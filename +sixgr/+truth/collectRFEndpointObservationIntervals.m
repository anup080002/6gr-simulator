function [observations,intervals,coverage]=collectRFEndpointObservationIntervals(raw)
%COLLECTRFENDPOINTOBSERVATIONINTERVALS Union actual RF observation coverage.
% These are executed operator intervals, NOT radio power-state transitions,
% measured watts, sleep intervals or proof of signal transmission. Multiple
% decoded channels/beams may observe the same physical operator interval.
observations=struct2table(repmat(localRow(),0,1));
coverage=table('Size',[0 5],'VariableTypes',{'string','double','string','string','string'}, ...
    'VariableNames',{'SourceTable','SourceRow','Endpoint','Status','Reason'});
executionConfigs=containers.Map('KeyType','char','ValueType','char');
for domain=["DL","UL","PBCH","PRACH","PDCCH","PUCCH","SRS","CSIRS","TRS"]
    T=sixgr.util.structGet(raw,domain,table());
    if ~istable(T)||isempty(T), continue; end
    for i=1:height(T)
        for endpoint=["TX","RX"]
            prefix="Tx"; if endpoint=="RX", prefix="Rx"; end
            field=prefix+"RFEndpointMetadataAuditJSON";
            value=localText(T,i,field);
            if ~localPresent(value)
                coverage(end+1,:)={domain,i,endpoint,"MISSING","no_retained_endpoint_audit"}; %#ok<AGROW>
                continue;
            end
            audit=jsondecode(value);
            if ~isfield(audit,'Contract') || string(audit.Contract)~="shared_rf_endpoint_observation/v2"
                coverage(end+1,:)={domain,i,endpoint,"LEGACY","no_self_contained_execution_clock_contract"}; %#ok<AGROW>
                continue;
            end
            localValidate(audit,endpoint);
            scope=localScope(T,i);
            if isfield(scope,'ExecutionID') && isfield(scope,'ConfigHash')
                key=char(scope.ExecutionID); value=char(scope.ConfigHash);
                assert(~isKey(executionConfigs,key) || strcmp(executionConfigs(key),value), ...
                    'sixgr:truth:RFIntervalExecutionConfigMismatch', ...
                    'One immutable execution cannot claim different configuration hashes.');
                executionConfigs(key)=value;
            end
            scopeJSON=string(jsonencode(scope));
            for k=1:numel(audit.StageCountIntervals)
                segment=audit.StageCountIntervals(k); r=localRow();
                r.ScopeJSON=scopeJSON; r.NodeID=string(audit.NodeID); r.Endpoint=endpoint;
                r.ConfigurationEpoch=double(segment.ConfigurationEpoch);
                r.SampleRateHz=double(audit.SampleRateHz);
                r.PhysicalPortCount=double(audit.PhysicalPortCount);
                r.StartSample=double(segment.StartSample);
                r.EndSampleExclusive=double(segment.EndSampleExclusive);
                r.StartTime_s=r.StartSample/r.SampleRateHz;
                r.EndTimeExclusive_s=r.EndSampleExclusive/r.SampleRateHz;
                r.Duration_s=(r.EndSampleExclusive-r.StartSample)/r.SampleRateHz;
                r.SourceTable=domain; r.SourceRow=i;
                r.SourceAuditField=field; r.SourceAuditSHA256=string( ...
                    sixgr.util.sha256Hex(uint8(unicode2native(char(value),'UTF-8'))));
                observations=[observations;struct2table(r)]; %#ok<AGROW>
            end
            coverage(end+1,:)={domain,i,endpoint,"BOUND","actual_completed_endpoint_observation"}; %#ok<AGROW>
        end
    end
end
intervals=localUnion(observations);
end

function scope=localScope(T,i)
% The execution identity owns the physical clock. Optional display/run
% aliases must not split overlapping PBCH/CSI-RS/TRS windows from that clock.
% Old categorical RunUUID placeholders are not independent executions.
scope=struct(); names=string(T.Properties.VariableNames);
if ismember("ExecutionID",names)
    value=localText(T,i,"ExecutionID");
    assert(localPresent(value),'sixgr:truth:MissingRFIntervalScope', ...
        'A declared physical ExecutionID must contain actual execution evidence.');
    scope.ExecutionID=value;
else
    % Isolated component observations may declare only a real run identity.
    % A component raw set without any run-ID fields stays explicitly unbound.
    aliases=["RunUUID","RunID","RunId"]; declared=any(ismember(aliases,names));
    for name=aliases
        value=localText(T,i,name);
        if localPresent(value)
            scope.RunIdentity=value; scope.RunIdentityField=name; break;
        end
    end
    assert(~declared || isfield(scope,'RunIdentity'), ...
        'sixgr:truth:MissingRFIntervalScope','No actual declared run identity exists.');
end
for name=["ConfigHash","SweepPointIndex","FixedLinkPointIndex","FixedLinkDropIndex", ...
        "FixedLinkTrialIndex","FixedLinkSeedIndex","FixedLinkSeedValue"]
    if ~ismember(name,names), continue; end
    value=localText(T,i,name);
    assert(localPresent(value),'sixgr:truth:MissingRFIntervalScope', ...
        'A declared %s cannot be missing when joining endpoint observation intervals.',name);
    scope.(name)=value;
end
end

function localValidate(a,endpoint)
required={'Source','NodeID','Endpoint','SampleRateHz','PhysicalPortCount','ClockDomain', ...
    'CaptureStartSample','CaptureEndSampleExclusive','StageCountIntervals'};
assert(isstruct(a)&&isscalar(a)&&all(isfield(a,required)) && ...
    string(a.Source)=="actual_retained_RF_endpoint_execution_only" && ...
    string(a.Endpoint)==endpoint && localPresent(string(a.NodeID)) && ...
    string(a.ClockDomain)=="shared_physical_absolute_sample_clock_zero_based", ...
    'sixgr:truth:InvalidRFIntervalAudit','Use the completed actual endpoint audit, not a planned slot.');
validateattributes(a.SampleRateHz,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(a.PhysicalPortCount,{'numeric'},{'scalar','real','finite','integer','positive'});
validateattributes([a.CaptureStartSample a.CaptureEndSampleExclusive], ...
    {'numeric'},{'real','finite','integer','nonnegative','numel',2});
assert(a.CaptureEndSampleExclusive>a.CaptureStartSample && ...
    isstruct(a.StageCountIntervals)&&~isempty(a.StageCountIntervals) && ...
    all(isfield(a.StageCountIntervals,{'StartSample','EndSampleExclusive','ConfigurationEpoch'})), ...
    'sixgr:truth:InvalidRFIntervalAudit','Actual nonempty execution intervals are required.');
next=double(a.CaptureStartSample);
for k=1:numel(a.StageCountIntervals)
    s=a.StageCountIntervals(k);
    validateattributes([s.StartSample s.EndSampleExclusive s.ConfigurationEpoch], ...
        {'numeric'},{'real','finite','integer','nonnegative','numel',3});
    assert(s.StartSample==next && s.EndSampleExclusive>s.StartSample && ...
        s.EndSampleExclusive<=a.CaptureEndSampleExclusive, ...
        'sixgr:truth:RFIntervalCoverageMismatch','Do not invent gaps or overlap within one completed observation.');
    next=double(s.EndSampleExclusive);
end
assert(next==a.CaptureEndSampleExclusive,'sixgr:truth:RFIntervalCoverageMismatch', ...
    'All samples of the observation must have retained RF execution coverage.');
end

function U=localUnion(T)
U=table('Size',[0 12], ...
    'VariableTypes',{'string','string','string','double','double','double','double','double','double','double','string','string'}, ...
    'VariableNames',{'ScopeJSON','NodeID','Endpoint','ConfigurationEpoch','SampleRateHz', ...
    'PhysicalPortCount','StartSample','EndSampleExclusive','Duration_s', ...
    'SourceObservationCount','SourceTablesJSON','IntervalMeaning'});
if isempty(T), return; end
keys=strings(height(T),1);
for k=1:height(T)
    keys(k)=string(jsonencode(struct('Scope',T.ScopeJSON(k),'Node',T.NodeID(k), ...
        'Endpoint',T.Endpoint(k),'Epoch',T.ConfigurationEpoch(k))));
end
for key=unique(keys,'stable')'
    G=sortrows(T(keys==key,:),{'StartSample','EndSampleExclusive'});
    assert(all(G.SampleRateHz==G.SampleRateHz(1)) && ...
        all(G.PhysicalPortCount==G.PhysicalPortCount(1)), ...
        'sixgr:truth:RFIntervalClockOrPortMismatch', ...
        'One physical endpoint/epoch cannot change sample rate or physical port count.');
    first=G.StartSample(1); stop=G.EndSampleExclusive(1); source=G.SourceTable(1);
    owners=localOwner(G,1);
    for k=2:height(G)
        if G.StartSample(k)<=stop
            stop=max(stop,G.EndSampleExclusive(k));
            source(end+1,1)=G.SourceTable(k); owners(end+1,1)=localOwner(G,k); %#ok<AGROW>
        else
            U(end+1,:)=localUnionRow(G,first,stop,source,owners); %#ok<AGROW>
            first=G.StartSample(k); stop=G.EndSampleExclusive(k);
            source=G.SourceTable(k); owners=localOwner(G,k);
        end
    end
    U(end+1,:)=localUnionRow(G,first,stop,source,owners); %#ok<AGROW>
end
end
function v=localOwner(T,i)
v=string(jsonencode(struct('Table',T.SourceTable(i),'Row',T.SourceRow(i))));
end
function values=localUnionRow(G,first,stop,source,owners)
values={G.ScopeJSON(1),G.NodeID(1),G.Endpoint(1),G.ConfigurationEpoch(1), ...
    G.SampleRateHz(1),G.PhysicalPortCount(1),first,stop,(stop-first)/G.SampleRateHz(1), ...
    numel(unique(owners)),string(jsonencode(unique(source,'stable'))), ...
    "union_of_executed_RF_observation_coverage_not_radio_power_state_or_sleep"};
end
function r=localRow()
r=struct('ScopeJSON',"",'NodeID',"",'Endpoint',"",'ConfigurationEpoch',NaN, ...
    'SampleRateHz',NaN,'PhysicalPortCount',NaN,'StartSample',NaN, ...
    'EndSampleExclusive',NaN,'StartTime_s',NaN,'EndTimeExclusive_s',NaN, ...
    'Duration_s',NaN,'SourceTable',"",'SourceRow',NaN,'SourceAuditField',"", ...
    'SourceAuditSHA256',"",'IntervalMeaning', ...
    "executed_RF_observation_coverage_not_radio_power_state_or_sleep");
end
function v=localText(T,i,name)
v="";
if ismember(name,string(T.Properties.VariableNames))
    raw=T.(name)(i,:); if iscell(raw), raw=raw{1}; end
    v=strtrim(string(raw));
end
end
function yes=localPresent(v)
yes=isscalar(v) && sixgr.truth.measurementValuePresent(v) && ...
    ~any(lower(v)==["n/a","none","null"]);
end
