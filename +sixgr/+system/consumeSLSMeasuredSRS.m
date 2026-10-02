function [ueOut,decision]=consumeSLSMeasuredSRS(ue,row,cfg,context)
%CONSUMESLSMEASUREDSRS Bind completed UL receiver evidence to future grants.
% Slot/ObservationDeliverySlot are one-based runtime slots, as in the coupled
% SRS completion table. ConsumerRuntimeSlot is the target scheduling slot;
% KnownAtRuntimeSlot is the actual decision clock (may precede a future UL).
% This consumer neither executes SRS nor establishes shared-channel ownership.
arguments
    ue (1,1) struct
    row
    cfg (1,1) struct
    context (1,1) struct
end
required={'ConsumerRuntimeSlot','KnownAtRuntimeSlot','MaxRank', ...
    'ExpectedReceiveDimensions','SlotDuration_s','PhysicalExecutionID','ChannelOwnerID'};
assert(all(isfield(context,required)) && all(isfield(ue,{'UEIndex','ServingCell'})), ...
    'sixgr:system:SRSConsumerContext','Explicit clocks, capabilities and UE/cell identity required.');
now=double(context.ConsumerRuntimeSlot); known=double(context.KnownAtRuntimeSlot);
cap=double(context.MaxRank); dimensions=double(context.ExpectedReceiveDimensions);
validateattributes([now known cap dimensions ue.UEIndex ue.ServingCell], ...
    {'numeric'},{'real','finite','integer','positive'});
validateattributes(context.SlotDuration_s,{'numeric'},{'real','finite','scalar','positive'});
assert(known<=now,'sixgr:system:SRSConsumerClock','Knowledge cannot be from after the target grant.');
maxAge=double(sixgr.util.structGet(cfg,'phy.mimo.measurementMaxAgeSlots',NaN));
validateattributes(maxAge,{'numeric'},{'real','finite','scalar','integer','nonnegative'});
ueOut=ue; ueOut.MUMIMOSpatialSignatureValid=false;
ueOut.SRSValid=false;
ueOut.SRSCausalUsable=false;
ueOut.SRSCausalStatus="no_current_usable_completed_srs";
ueOut.SRSRankUpdateApplied=false;
ueOut.SRSRankUpdateStatus="not_remeasured_no_current_usable_srs";
decision=struct('Applied',false,'Usable',false,'Status',"no_completed_srs", ...
    'UEIndex',double(ue.UEIndex),'ServingCell',double(ue.ServingCell), ...
    'SourceRuntimeSlot',NaN,'DeliveryRuntimeSlot',NaN,'ConsumerRuntimeSlot',now, ...
    'KnownAtRuntimeSlot',known,'AgeSlots',NaN,'MeasuredRI',NaN,'SelectedRank',NaN, ...
    'SignatureSHA256',"",'Source',"completed_measured_srs_consumer");
if isempty(row), return; end
if isstruct(row) && isscalar(row), row=struct2table(row,'AsArray',true); end
assert(istable(row) && height(row)==1,'sixgr:system:SRSCompletionRow','Supply one completed SRS row.');
names=string(row.Properties.VariableNames);
required=["Slot","ObservationDeliverySlot","RuntimeTransportMode", ...
    "PhysicalExecutionID","ChannelOwnerID", ...
    "ProxyUsed","Skipped","ToolboxMissing","Crash","UsedOracleFields", ...
    "DetectionAttempted","DetectionSuccess","ResourceExtractionAttempted", ...
    "ResourceExtractionAvailable","ChannelEstimateAttempted", ...
    "SRSChannelEstimateAvailable","SRSRuntimeEvidenceUsable", ...
    "SpatialSignatureToken","SpatialSignatureSHA256","SpatialSignatureSource"];
assert(all(ismember(required,names)),'sixgr:system:SRSCompletionSchema', ...
    'Completed receiver row must retain clocks, receiver usability and spatial evidence.');
for field=["PhysicalExecutionID","ChannelOwnerID"]
    expected=string(context.(field)); actual=string(row.(field));
    assert(isscalar(expected) && isscalar(actual) && strlength(strtrim(expected))>0 && actual==expected, ...
        'sixgr:system:SRSPhysicalOwnerMismatch','SRS evidence and scheduled data must share execution and channel-owner identity.');
end
source=double(row.Slot); delivery=double(row.ObservationDeliverySlot);
validateattributes([source delivery],{'numeric'},{'real','finite','integer','positive'});
assert(delivery>source,'sixgr:system:SRSCompletionClock','SRS samples must complete before a later slot boundary consumes them.');
decision.SourceRuntimeSlot=source; decision.DeliveryRuntimeSlot=delivery; decision.AgeSlots=now-source;
if localIdentity(row,["UEIndex","UE"])~=double(ue.UEIndex) || ...
        localIdentity(row,["ServingCell","CellID","BaseStationID"])~=double(ue.ServingCell)
    decision.Status="srs_identity_mismatch"; return;
end
assert(string(row.RuntimeTransportMode)=="shared_physical_stream_SRS_received_completion", ...
    'sixgr:system:SRSSharedCompletionRequired','Component or isolated SRS trials cannot masquerade as shared runtime completions.');
% Reuse the canonical received-window completion/delivery validator. Its
% CurrentSlot is the original delivery event, not this later consumer slot.
clock=struct('CurrentSlot',delivery,'SlotDuration_s',double(context.SlotDuration_s));
sixgr.truth.srsResultDeliverySlot(clock,row);
if delivery>known
    decision.Status="srs_not_delivered_at_decision_clock"; return;
end
if decision.AgeSlots>maxAge
    decision.Status="srs_stale_for_target_slot"; return;
end
% Match CoupledTruthRuntime.srsRuntimeEvidenceComplete receiver usability;
% simulator-truth NMSE PASS is deliberately not a scheduling authority.
for name=["ProxyUsed","Skipped","ToolboxMissing","Crash"]
    if ~localBoolean(row.(name),false)
        decision.Status="srs_nonphysical_or_failed_completion"; return;
    end
end
if strlength(strtrim(string(row.UsedOracleFields)))>0
    decision.Status="srs_oracle_fields_rejected"; return;
end
for name=["DetectionAttempted","DetectionSuccess","ResourceExtractionAttempted", ...
        "ResourceExtractionAvailable","ChannelEstimateAttempted", ...
        "SRSChannelEstimateAvailable","SRSRuntimeEvidenceUsable"]
    if ~localBoolean(row.(name),true)
        decision.Status="srs_receiver_evidence_unusable"; return;
    end
end
ri=localRank(row);
decision.MeasuredRI=ri;
if ~isfinite(ri)
    decision.Status="srs_measured_rank_unavailable"; return;
end
if ri>cap
    decision.Status="srs_rank_above_installed_capability"; return;
end
spatialSource=lower(strtrim(string(row.SpatialSignatureSource)));
assert(startsWith(spatialSource,"measured_srs_receiver_channel_estimate") && ...
    ~any(contains(spatialSource,["oracle","geometry","proxy","synthetic","fallback"])), ...
    'sixgr:system:SRSSpatialAuthority','Spatial signature must come from the measured SRS receiver channel estimate.');
digest=lower(strtrim(string(row.SpatialSignatureSHA256)));
assert(isscalar(digest) && ~ismissing(digest) && ...
    ~isempty(regexp(char(digest),'^[0-9a-f]{64}$','once')), ...
    'sixgr:system:SRSSpatialDigest','An explicit SHA256 of the measured spatial signature is required.');
signature=sixgr.phy.mimo.MatrixContract.deserialize(string(row.SpatialSignatureToken),'ExpectedDigest',digest);
assert(size(signature,1)==dimensions && norm(signature,'fro')>0, ...
    'sixgr:system:SRSSpatialDimensions','Measured signature must match installed gNB receive dimensions and be nonzero.');
% A rank-only update is not sufficient authority for a strict codebook
% grant. Retain the receiver's TPMI and the independently installed SRI
% binding, rather than clearing PMI and leaving grant freezing to fail.
codebook=strcmpi(string(sixgr.util.structGet(cfg,'phy.pusch.transmissionScheme','')),"codebook");
if codebook
    required=["ObservationID","SRSResourceIndicator","TPMIEstimate"];
    assert(all(ismember(required,names)) && isfield(context,'ExpectedTransmitPorts'), ...
        'sixgr:system:SRSCodebookAuthority', ...
        'Codebook scheduling requires completed observation identity, installed SRI, measured TPMI and transmit-port capability.');
    observationID=string(row.ObservationID);
    tpmi=double(row.TPMIEstimate); sri=double(row.SRSResourceIndicator);
    ports=double(context.ExpectedTransmitPorts);
    assert(isscalar(observationID) && ~ismissing(observationID) && strlength(strtrim(observationID))>0, ...
        'sixgr:system:SRSCodebookAuthority','A completed receive-window identity is required.');
    validateattributes([tpmi sri],{'numeric'},{'real','finite','integer','nonnegative'});
    validateattributes(ports,{'numeric'},{'scalar','real','finite','integer','positive','>=',ri});
    W=nrPUSCHCodebook(ri,ports,tpmi);
    % nrPUSCHCodebook maps layer rows to antenna-port columns.
    assert(isequal(size(W),[ri ports]),'sixgr:system:SRSCodebookDimensions', ...
        'The measured TPMI must select a legal codebook for the installed ports and received rank.');
end
ueOut.RI=ri; ueOut.NumLayers=ri;
ueOut.RankAuthority="completed_measured_srs_ri";
ueOut.SRSRankUpdateApplied=true; ueOut.SRSRankUpdateStatus="completed_measured_srs_ri";
ueOut.MUMIMOSpatialSignature=signature;
ueOut.MUMIMOSpatialSignatureSHA256=char(digest);
ueOut.MUMIMOSpatialSignatureSource=char(spatialSource);
ueOut.MUMIMOSpatialSignatureSourceSlot=source;
ueOut.MUMIMOSpatialSignatureMeasurementDirection='UL';
ueOut.MUMIMOSpatialSignatureReciprocityMode='direct_ul_srs';
ueOut.MUMIMOSpatialSignatureAgeSlots=now-source;
ueOut.MUMIMOSpatialSignatureConsumerRuntimeSlot=now;
ueOut.MUMIMOSpatialSignatureValid=true;
ueOut.SRSFeedbackSourceSlot=source; ueOut.SRSFeedbackDeliveredSlot=delivery;
% This helper does not select codebook TPMI or alter SINR/CQI/MCS/OLLA.
% Clear a prior rank-owned PMI instead of carrying it into a new measured RI.
ueOut.PMI=NaN;
if codebook
    ueOut.PMI=tpmi; ueOut.TPMI=tpmi; ueOut.SRI=sri;
    ueOut.SRSValid=true; ueOut.SRSCausalUsable=true;
    ueOut.SRSCausalMeasurementId=char(observationID);
    ueOut.LastSuccessfulSRSSlot=source;
    ueOut.SRSAgeSlots=now-source; ueOut.SRSCausalAgeSlots=now-source;
    ueOut.SRSCausalStatus="valid_completed_srs_codebook_feedback";
end
decision.Applied=true; decision.Usable=true; decision.Status="causal_completed_srs_applied";
decision.SelectedRank=ri; decision.SignatureSHA256=digest;
end

function rank=localRank(row)
aliases=["RIEstimate","RankEstimate","EstimatedRI","RI"];
present=aliases(ismember(aliases,string(row.Properties.VariableNames)));
values=[];
for k=1:numel(present)
    raw=row.(present(k));
    assert(isnumeric(raw) && isreal(raw) && isscalar(raw), ...
        'sixgr:system:SRSCompletionRank','SRS rank must be a scalar receiver estimate.');
    if isnan(raw), continue; end
    validateattributes(raw,{'numeric'},{'finite','integer','positive'});
    values(end+1)=double(raw); %#ok<AGROW>
end
rank=NaN;
if isempty(values), return; end
assert(all(values==values(1)),'sixgr:system:SRSCompletionRank','Conflicting measured SRS rank aliases.');
rank=values(1);
end

function value=localIdentity(row,aliases)
present=aliases(ismember(aliases,string(row.Properties.VariableNames)));
assert(~isempty(present),'sixgr:system:SRSCompletionIdentity','Missing explicit SRS identity/rank.');
values=zeros(1,numel(present));
for k=1:numel(present)
    raw=row.(present(k));
    validateattributes(raw,{'numeric'},{'real','scalar','finite','integer','positive'});
    values(k)=double(raw);
end
assert(all(values==values(1)),'sixgr:system:SRSCompletionIdentity','Conflicting SRS identity/rank aliases.');
value=values(1);
end
function tf=localBoolean(value,expected)
tf=(isnumeric(value)||islogical(value)) && isscalar(value) && ...
    isreal(value) && isfinite(value) && double(value)==double(expected);
end
