function evidence=validateHARQCurrentAttempt(original,currentGrant,currentBits,varargin)
% Validate a current frozen attempt against the original HARQ-owned TB.
% original is the unmodified HARQEntity.peekRetx record, or a faithful
% adapter of its TB/TBContext/LastGrant/next-HARQ records. No state mutation,
% precoder substitution, coding execution or received-control claim occurs.
% Frozen PHY CodingLayout is a preparation schema, not native LDPC evidence.
p=inputParser;
p.addParameter('CurrentCodingLayout',struct(),@(v)isstruct(v)&&isscalar(v));
p.parse(varargin{:});
native=p.Results.CurrentCodingLayout;
localStruct(original,{'TB','TBContext','LastGrant','HARQ'});
localStruct(currentGrant,{'PHYGrant','HARQ','Direction','RNTI','UEIndex','ServingCell', ...
    'TransportBlockId','TBSBits','NumLayers'});
tb=original.TBContext; prior=original.LastGrant; next=original.HARQ;
localStruct(tb,{'ContractVersion','Direction','CellId','UeId','RNTI','HARQProcessId', ...
    'NDIEpoch','NDI','TBId','CodewordId','TBSBits','OriginalNumLayers'});
localStruct(prior,{'Direction','RNTI','UEIndex','ServingCell','TransportBlockId','HARQ','TBSBits'});
localStruct(next,{'HarqID','NDI','NDIEpoch','RV','IsRetransmission'});
localRequire(localText(tb.ContractVersion)=="HARQTransportBlockContext/v1",'Schema', ...
    'Use the original canonical HARQ TB context.');
phy=currentGrant.PHYGrant;
localStruct(phy,{'IsFrozen','Immutable','Direction','GrantContextId','CodingLayout', ...
    'AntennaArchitecture','HARQProcessKey','ChannelStateKey','PrecodingState'});
localRequire(isequal(phy.IsFrozen,true)&&islogical(phy.IsFrozen)&& ...
    isequal(phy.Immutable,true)&&islogical(phy.Immutable),'Schema', ...
    'The current attempt must already own an immutable frozen PHY grant.');
sixgr.phy.grant.assertPHYGrantDimensions(phy,'validate_harq_current_attempt');
sixgr.phy.grant.assertGrantTimingIdentity(currentGrant,currentGrant.Direction);
localRequire(islogical(next.IsRetransmission)&&isscalar(next.IsRetransmission)&&next.IsRetransmission && ...
    islogical(phy.HARQProcessKey.IsRetransmission)&&isscalar(phy.HARQProcessKey.IsRetransmission)&& ...
    phy.HARQProcessKey.IsRetransmission && ...
    sixgr.phy.grant.isExplicitHARQRetransmission(currentGrant),'Identity', ...
    'Only an outstanding original HARQ retry can reuse this TB.');

bits=localBits(original.TB); attempted=localBits(currentBits);
tbs=localInteger(tb.TBSBits,1);
localRequire(numel(bits)==tbs && isequal(bits,attempted),'TransportBlock', ...
    'The current attempt must retain every original TB bit, not merely its size.');
direction=localText(tb.Direction);
localRequire(any(direction==["DL","UL"]) && localText(prior.Direction)==direction && ...
    localText(currentGrant.Direction)==direction && localText(phy.Direction)==direction && ...
    localText(phy.HARQProcessKey.Direction)==direction,'Identity','HARQ direction changed.');
for row={ 'CellId','ServingCell','ServingCell'; 'UeId','UEIndex','UEIndex'; 'RNTI','RNTI','RNTI' }.'
    expected=localInteger(tb.(row{1}),1);
    localSame(prior.(row{2}),expected,'Identity');
    localSame(currentGrant.(row{2}),expected,'Identity');
    localSame(phy.ChannelStateKey.(row{3}),expected,'Identity');
end
localSame(phy.HARQProcessKey.RNTI,tb.RNTI,'Identity');
pid=localInteger(tb.HARQProcessId,0); epoch=localInteger(tb.NDIEpoch,0);
localSame(next.HarqID,pid,'Identity'); localSame(next.NDIEpoch,epoch,'Identity');
for h={prior.HARQ,currentGrant.HARQ}
    localStruct(h{1},{'HarqID','NDI','NDIEpoch','RV'});
    localSame(h{1}.HarqID,pid,'Identity'); localSame(h{1}.NDIEpoch,epoch,'Identity');
    if isfield(h{1},'HARQProcess'), localSame(h{1}.HARQProcess,pid,'Identity'); end
    localRequire(localBit(h{1}.NDI)==localBit(tb.NDI),'Identity','HARQ NDI changed.');
end
localSame(phy.HARQProcessKey.HARQProcess,pid,'Identity');
localRequire(localBit(next.NDI)==localBit(tb.NDI) && ...
    localBit(phy.HARQProcessKey.NDI)==localBit(tb.NDI),'Identity','Frozen HARQ NDI changed.');
rv=localInteger(next.RV,0); localRequire(rv<=3,'Identity','RV must remain in [0,3].');
localSame(currentGrant.HARQ.RV,rv,'Identity'); localSame(phy.HARQProcessKey.RV,rv,'Identity');
tbID=localText(tb.TBId);
localRequire(strlength(tbID)>0 && localText(prior.TransportBlockId)==tbID && ...
    localText(currentGrant.TransportBlockId)==tbID,'Identity','Original TB identity changed.');
for g={prior,currentGrant}
    for name=["TBSBits","TransportBlockSize","TBSize_bits"]
        if isfield(g{1},name), localSame(g{1}.(name),tbs,'TransportBlock'); end
    end
    if isfield(g{1},'TBId')
        localRequire(localText(g{1}.TBId)==tbID,'Identity','TB identity aliases disagree.');
    end
    for name=["Codeword","CodewordIndex"]
        if isfield(g{1},name), localSame(g{1}.(name),tb.CodewordId,'Identity'); end
    end
end
localSame(phy.CodingLayout.TBSBits,tbs,'TransportBlock');
% Current repository execution policy is one original codeword and fixed
% layers for this HARQ replay path. This is not a universal NR rank rule.
localRequire(localInteger(tb.CodewordId,0)==0 && phy.CodingLayout.NumCodewords==1, ...
    'UnsupportedCodewordPolicy','This current-attempt adapter supports one TB/codeword.');
layers=localInteger(tb.OriginalNumLayers,1);
localSame(currentGrant.NumLayers,layers,'FixedRankPolicy');
localSame(phy.CodingLayout.NumLayers,layers,'FixedRankPolicy');
if isfield(currentGrant,'Layers'), localSame(currentGrant.Layers,layers,'FixedRankPolicy'); end
if isfield(currentGrant,'HARQTBContext') && ~isempty(fieldnames(currentGrant.HARQTBContext))
    localRequire(isequaln(currentGrant.HARQTBContext,tb),'OriginalContext', ...
        'Preparation must retain the exact original TB/coding context, not a rewritten old PHY.');
end
% The current frozen contract owns spatial coefficients and architecture.
% Only aliases supplied by this attempt are compared; none are filled from
% the old grant or used to overwrite current coefficients.
for name=["NumElements","NumLogicalPorts","NumRFChains","NumTxRUs","NumRxAntennas"]
    if isfield(currentGrant,name)
        localSame(currentGrant.(name),phy.AntennaArchitecture.(name),'SpatialAlias');
    end
end
for row={'PrecodingMatrix','MatrixPhysicalPorts'; ...
        'PrecodingMatrixLogicalPorts','MatrixLogicalPorts'; ...
        'LogicalPrecodingMatrix','MatrixLogicalPorts'; ...
        'HybridElementToPortMatrix','HybridElementToPortMatrix'}.'
    if isfield(currentGrant,row{1}) && ~isempty(currentGrant.(row{1}))
        localRequire(isnumeric(currentGrant.(row{1})) && ...
            isequaln(double(currentGrant.(row{1})),double(phy.PrecodingState.(row{2}))), ...
            'SpatialAlias','Current matrix aliases must equal the current frozen operator.');
    end
end
for name=["PMI","AppliedPrecoderPMI","TPMI"]
    if ~isfield(currentGrant,name) || isempty(currentGrant.(name)), continue; end
    value=currentGrant.(name);
    localRequire(isnumeric(value)&&isreal(value)&&isscalar(value),'SpatialAlias','Malformed spatial selector.');
    if isnan(value), continue; end
    expected="PMI"; if name=="TPMI", expected="TPMI"; end
    localSame(value,phy.PrecodingState.(expected),'SpatialAlias');
end
if isfield(currentGrant,'CRI') && isfield(phy.PrecodingState,'CSIRSPortBasisApplied') && ...
        phy.PrecodingState.CSIRSPortBasisApplied
    localSame(currentGrant.CRI,phy.PrecodingState.CSIResourceIndex,'SpatialAlias');
end
nativeValidated=false;
if ~isempty(fieldnames(native))
    localStruct(native,{'ContractVersion','Immutable','A','Direction','TBCRCType','BaseGraph', ...
        'C','K','N','Zc','NumLayers','Modulation','RV','RateMatchedBitCount','E_r','CodingLayoutHash','CombineSignature'});
    localRequire(localText(native.ContractVersion)=="CodingLayout/v2" && ...
        islogical(native.Immutable)&&isscalar(native.Immutable)&&native.Immutable, ...
        'NativeCoding','Use an original native CodingLayout/v2 operand.');
    localSame(native.A,tbs,'NativeCoding'); localSame(native.NumLayers,layers,'NativeCoding');
    localSame(native.RV,rv,'NativeCoding');
    localRequire(localText(native.Direction)==direction && ...
        localText(native.Modulation)==localText(phy.CodingLayout.Modulation), ...
        'NativeCoding','Native coding direction/modulation changed.');
    % Reuse the canonical context producer for field projection, without
    % a PreviousContext that could copy missing native operands from history.
    meta=struct('Grant',currentGrant,'PHYGrant',phy,'CodingLayout',native, ...
        'Direction',direction,'TBSBits',tbs,'RV',rv,'IsRetransmission',true);
    now=sixgr.harq.createTBContext(meta);
    for name=["LDPCBaseGraph","LiftingSizeZc","NumCodeBlocks"]
        localRequire(isfield(tb,name),'NativeCoding','Original native coding operand missing.');
        localSame(now.(name),localInteger(tb.(name),1),'NativeCoding');
    end
    for name=["CodeBlockSizes","FillerBits","NcbPerCodeBlock"]
        localRequire(isfield(tb,name),'NativeCoding','Original native coding operand missing.');
        value=tb.(name);
        localRequire(isnumeric(value) && isreal(value) && ~isempty(value) && ...
            all(isfinite(value(:))) && isequal(double(now.(name)),double(value)),'NativeCoding', ...
            'Original native segmentation/buffer operands changed or are unavailable.');
    end
    localRequire(isfield(tb,'TBCRCType') && localText(now.TBCRCType)==localText(tb.TBCRCType) && ...
        isfield(tb,'CodeBlockLayoutHash') && strlength(localText(tb.CodeBlockLayoutHash))>0 && ...
        localText(native.CodingLayoutHash)==localText(tb.CodeBlockLayoutHash) && ...
        localText(native.CombineSignature)==localText(tb.CodeBlockLayoutHash), ...
        'NativeCoding','Original native CRC/combining signature changed or is unavailable.');
    meta.PreviousContext=tb; meta.TransportBlockContext=tb;
    meta.ExpectedTBSBits=tbs;
    meta.SoftCombiningEvidenceAvailable=sixgr.util.structGet(currentGrant,'HARQSoftCombiningEvidenceAvailable',false);
    [~,status]=sixgr.harq.validateTBContextForTransmission(meta);
    localRequire(status.IsRetransmission,'NativeCoding','Native validation must retain the original TB.');
    nativeValidated=true;
end
evidence=struct('ContractVersion',"sixgr_harq_current_attempt_validation/v1", ...
    'Source',"original_HARQ_owner_and_current_frozen_attempt_not_received_control", ...
    'Direction',direction,'OriginalTBId',tbID,'CurrentGrantContextID',localText(phy.GrantContextId), ...
    'TransportBlockSHA256',string(sixgr.util.sha256Hex(uint8(bits))), ...
    'OriginalTBSBits',tbs,'CurrentRV',rv,'OriginalPayloadAndProcessValidated',true, ...
    'FixedRankImplementationPolicyApplied',true,'OriginalNumLayers',layers, ...
    'CurrentFrozenSpatialDimensionsValidated',true,'OriginalSpatialStateSubstituted',false, ...
    'NativeCodingOperandsValidated',nativeValidated,'IndependentExecutionAttested',false);
end

function localStruct(value,names)
localRequire(isstruct(value)&&isscalar(value)&&all(isfield(value,names)), ...
    'Schema','Required original/current scalar schema is incomplete.');
end
function value=localBits(raw)
localRequire((isnumeric(raw)||islogical(raw))&&isreal(raw)&&isvector(raw)&&~isempty(raw)&& ...
    all(raw(:)==0|raw(:)==1),'TransportBlock','Retain a nonempty original binary TB.');
value=uint8(raw(:));
end
function value=localInteger(raw,minimum)
localRequire(isnumeric(raw)&&isreal(raw)&&isscalar(raw)&&isfinite(raw)&& ...
    raw==fix(raw)&&raw>=minimum&&double(raw)<=flintmax,'Scalar','Expected exact finite integer operand.');
value=double(raw);
end
function value=localBit(raw)
localRequire((isnumeric(raw)||islogical(raw))&&isreal(raw)&&isscalar(raw)&& ...
    isfinite(raw)&&any(raw==[0 1]),'Identity','Expected original NDI bit.');
value=logical(raw);
end
function value=localText(raw)
localRequire((ischar(raw)&&isrow(raw))||(isstring(raw)&&isscalar(raw)&&~ismissing(raw)), ...
    'Schema','Expected original scalar text.');
value=string(raw);
end
function localSame(actual,expected,kind)
localRequire(isnumeric(actual)&&isreal(actual)&&isscalar(actual)&&isfinite(actual)&& ...
    isnumeric(expected)&&isreal(expected)&&isscalar(expected)&&isfinite(expected)&& ...
    double(actual)==double(expected),kind,'Original/current numeric operands disagree.');
end
function localRequire(condition,kind,message)
assert(condition,char("sixgr:phy:grant:HARQCurrentAttempt"+kind),message);
end
