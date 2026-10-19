function [T,ledger]=creditTransportGoodput(T,ledger)
%CREDITTRANSPORTGOODPUT Credit CRC-backed TB payload once, not each retry.
% Receiver completion accounting only. Does not alter PHY/CRC/HARQ decisions,
% create application delivery, or infer TB identity from an attempt/row index.
if nargin<2 || isempty(ledger)
    ledger=struct('Key',strings(0,1),'PayloadBits',zeros(0,1));
end
assert(istable(T),'sixgr:kpi:TransportGoodputTable','A receiver trial table is required.');
n=height(T);
T.UniqueDeliveredTBBits=nan(n,1);
T.FirstSuccessfulTBDelivery=false(n,1);
T.TransportGoodputKey=strings(n,1);
T.TransportGoodputStatus=repmat("unavailable_receiver_evidence",n,1);
T.TransportGoodputDefinition=repmat("unique_first_crc_success_TB_payload_not_application_delivery",n,1);
T.TransportGoodputContract=repmat("TransportGoodput/v1",n,1);
% Batch recomputation uses retained receiver-availability order when present.
% Streaming calls are made by the existing ordered completion owner.
order=(1:n)';
if ismember('DataDecodeAvailableAtSample',T.Properties.VariableNames)
    clock=double(T.DataDecodeAvailableAtSample);
    if all(isfinite(clock)), [~,order]=sort(clock,'ascend'); end
elseif ismember('Slot',T.Properties.VariableNames)
    clock=double(T.Slot);
    if all(isfinite(clock)), [~,order]=sort(clock,'ascend'); end
end
for i=order(:)'
    crc=localNumber(T,i,"CRCPass");
    if ~ismember(crc,[0 1]), continue; end
    if crc==0
        T.UniqueDeliveredTBBits(i)=0;
        T.TransportGoodputStatus(i)="crc_failure_no_delivery";
        continue;
    end
    bits=localNumber(T,i,"TBSize_bits");
    alternate=localNumber(T,i,"TBSBits");
    assert(~(isfinite(bits)&&isfinite(alternate)) || bits==alternate, ...
        'sixgr:kpi:TransportGoodputPayloadMismatch', ...
        'Populated actual TB-size aliases must agree.');
    if ~isfinite(bits), bits=alternate; end
    if ~(isfinite(bits) && bits>0 && bits==fix(bits))
        T.TransportGoodputStatus(i)="unavailable_actual_TB_size"; continue;
    end
    [key,status]=localKey(T,i);
    if strlength(key)==0, T.TransportGoodputStatus(i)=status; continue; end
    T.TransportGoodputKey(i)=key;
    prior=find(ledger.Key==key,1);
    if isempty(prior)
        ledger.Key(end+1,1)=key;
        ledger.PayloadBits(end+1,1)=bits;
        T.UniqueDeliveredTBBits(i)=bits;
        T.FirstSuccessfulTBDelivery(i)=true;
        T.TransportGoodputStatus(i)="first_crc_success";
    else
        assert(ledger.PayloadBits(prior)==bits,'sixgr:kpi:TransportGoodputPayloadMismatch', ...
            'One logical TB identity cannot acquire a different payload size.');
        T.UniqueDeliveredTBBits(i)=0;
        T.TransportGoodputStatus(i)="repeated_crc_success_no_new_payload";
    end
end
end

function [key,status]=localKey(T,i)
key=""; status="unavailable_logical_TB_identity"; id="";
direction=upper(localText(T,i,"Direction"));
if ~any(direction==["DL","UL"]), status="unavailable_direction_scope"; return; end
% The fixed-link Monte Carlo owner explicitly forbids HARQ and declares one
% independently generated TB per hierarchy entry. This is an execution
% identity, not permission to turn an arbitrary attempt number into a TB ID.
fixed=localNumber(T,i,"FixedLinkCampaign")==1;
if fixed
    if localText(T,i,"FixedLinkCampaignKind")~="fixed_link_monte_carlo"
        status="unavailable_fixed_link_execution_contract"; return;
    end
    scope=struct('Direction',direction,'IndependentTBContract',"fixed_link_monte_carlo");
    for field=["FixedLinkPointIndex","FixedLinkDropIndex","FixedLinkTrialIndex", ...
            "FixedLinkSeedIndex","FixedLinkSeedValue"]
        value=localNumber(T,i,field);
        if ~(isfinite(value)&&value==fix(value)&&value>=0) || ...
                (field~="FixedLinkSeedValue" && value<1)
            status="unavailable_"+field+"_scope"; return;
        end
        scope.(field)=value;
    end
    ue=localNumber(T,i,"UEIndex");
    if ~isfinite(ue), ue=localNumber(T,i,"UEID"); end
    if isfinite(ue), scope.UEIndex=ue; end
    for field=["RunId","RunID","ExecutionID","ConfigHash"]
        if ~ismember(field,string(T.Properties.VariableNames)), continue; end
        value=localText(T,i,field);
        if ~localPresent(value), status="unavailable_"+field+"_scope"; return; end
        scope.(field)=value;
    end
    key="FIXED|"+string(jsonencode(scope)); status=""; return;
end
for field=["LogicalTBID","TransportBlockId","TBId"]
    if ~ismember(field,string(T.Properties.VariableNames)), continue; end
    raw=T.(field)(i,:);
    if iscell(raw), raw=raw{1}; end
    % Historical numeric trial ordinals are not stable transport identities.
    if ~(isstring(raw)||ischar(raw)), continue; end
    candidate=strtrim(string(raw));
    if ~localPresent(candidate), continue; end
    assert(strlength(id)==0 || candidate==id,'sixgr:kpi:TransportGoodputIdentityMismatch', ...
        'Populated logical TB aliases disagree.');
    id=candidate;
end
if strlength(id)==0, return; end
ue=localNumber(T,i,"UEIndex");
if ~isfinite(ue), ue=localNumber(T,i,"UEID"); end
if ~(isfinite(ue)&&ue>=1&&ue==fix(ue)), status="unavailable_logical_UE_scope"; return; end
scope=struct('Direction',direction,'UEIndex',ue,'LogicalTBID',id);
% Use declared experiment/session scope. Never use mutable current RNTI or
% per-attempt slot/ID as the TB generation key.
for field=["RunId","RunID","SweepPointIndex","ConnectionEpoch","ConfigurationEpoch", ...
        "NDIEpoch","FixedLinkPointIndex","FixedLinkDropIndex","FixedLinkSeedIndex"]
    if ~ismember(field,string(T.Properties.VariableNames)), continue; end
    value=localText(T,i,field);
    if ~localPresent(value), status="unavailable_"+field+"_scope"; return; end
    scope.(field)=value;
end
key=string(jsonencode(scope)); status="";
end

function tf=localPresent(value)
tf=isscalar(value) && ~ismissing(value) && strlength(value)>0 && ...
    ~any(lower(value)==["nan","<missing>","unavailable"]);
end
function value=localText(T,i,name)
value="";
if ismember(name,string(T.Properties.VariableNames))
    raw=T.(name)(i,:); if iscell(raw), raw=raw{1}; end
    value=strtrim(string(raw));
end
end
function value=localNumber(T,i,name)
value=NaN;
if ismember(name,string(T.Properties.VariableNames))
    raw=T.(name)(i,:); if iscell(raw), raw=raw{1}; end
    if isnumeric(raw)||islogical(raw), candidate=double(raw); else, candidate=str2double(string(raw)); end
    if isscalar(candidate), value=candidate; end
end
end
