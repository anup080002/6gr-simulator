function [tbBits, decodedBits, grant] = validateExecutedHARQPayload(harqOut, row, direction)
% Validate retained PHY evidence before mutating shared scheduler/HARQ handles.
% This is not a decoder or a source of transport bits/coding layouts. An
% all-zero *transmitted* TB is valid; reconstructing one from a size is not.
direction = upper(string(direction));
if ~isscalar(direction) || ~any(direction == ["DL","UL"])
    error('sixgr:truth:ExecutedHARQBadDirection','Expected DL or UL.');
end
if ~isstruct(harqOut) || ~isscalar(harqOut) || ...
        ~isfield(harqOut,'TransportBlockBits') || isempty(harqOut.TransportBlockBits)
    error('sixgr:truth:MissingExecutedTransportBlock', ...
        '%s completion requires the actual transmitted transport-block bits.',direction);
end
tbBits = localBits(harqOut.TransportBlockBits,'TransportBlockBits');
nBits = numel(tbBits);
if mod(nBits,8) ~= 0
    error('sixgr:truth:ExecutedHARQNonByteAlignedTB', ...
        '%s transmitted transport block has %d bits, not a whole number of bytes.',direction,nBits);
end
if ~istable(row) || height(row) ~= 1 || ...
        ~ismember('TBSize_bits',row.Properties.VariableNames)
    error('sixgr:truth:ExecutedHARQMissingTrialSize', ...
        'Completion requires one measured trial row with TBSize_bits.');
end
localSize(row.TBSize_bits,nBits,'TrialTable.TBSize_bits');

context = sixgr.util.structGet(harqOut,'Context',struct());
if ~isstruct(context) || ~isscalar(context)
    error('sixgr:truth:ExecutedHARQInvalidContext','Retained HARQ context must be a scalar structure.');
end
grant = sixgr.util.structGet(harqOut,'GrantSnapshot', ...
    sixgr.util.structGet(context,'GrantSnapshot',struct()));
if ~isstruct(grant) || ~isscalar(grant) || isempty(fieldnames(grant))
    error(char("sixgr:truth:CoupledTruthRuntime:MissingExecuted"+direction+"GrantSnapshot"), ...
        '%s completion requires its immutable executed grant, not a configuration reconstruction.',direction);
end
localGrant(grant,nBits,direction,'GrantSnapshot');
if isfield(context,'GrantSnapshot')
    retained = context.GrantSnapshot;
    if ~isstruct(retained) || ~isscalar(retained)
        error('sixgr:truth:ExecutedHARQInvalidGrant','Context.GrantSnapshot must be a scalar executed grant.');
    end
    if ~isempty(fieldnames(retained))
        localGrant(retained,nBits,direction,'Context.GrantSnapshot');
    end
end
% Validate every retained layout/context alias. Do not conceal contradictory
% evidence by overwriting its size with the payload length before checking.
paths = ["TransportBlockContext","HARQTBContext", ...
    "Context.TransportBlockContext","Context.HARQTBContext", ...
    "GrantSnapshot.HARQTBContext","Context.GrantSnapshot.HARQTBContext"];
for path = paths
    ctx = sixgr.util.structGet(harqOut,path,struct());
    if ~isstruct(ctx) || ~isscalar(ctx)
        error('sixgr:truth:ExecutedHARQInvalidContext','%s must be a scalar structure.',path);
    end
    if isfield(ctx,'TBSBits')
        localSize(ctx.TBSBits,nBits,path+".TBSBits");
    end
end

decodedBits = int8([]);
if isfield(harqOut,'DecodedTransportBlockBits') && ~isempty(harqOut.DecodedTransportBlockBits)
    decodedBits = localBits(harqOut.DecodedTransportBlockBits,'DecodedTransportBlockBits');
    localSize(numel(decodedBits),nBits,'decoded transport-block length');
end
if ismember('CRCPass',row.Properties.VariableNames)
    crcPass = localFlag(row.CRCPass,'TrialTable.CRCPass');
else
    crcPass = false;
end
for field = ["CurrentDecodeOK","CombinedDecodeOK"]
    if isfield(harqOut,field)
        crcPass = localFlag(harqOut.(field),field) || crcPass;
    end
end
if crcPass && isempty(decodedBits)
    error('sixgr:truth:MissingDecodedTransportBlock', ...
        'A successful decoder outcome requires its actual decoded transport-block bits.');
end
% Do not demand identical TX/RX content for a CRC pass: undetected errors
% are possible. Payload integrity is measured from the actual two vectors.
end

function bits = localBits(value,label)
if ~(isnumeric(value) || islogical(value)) || ~isreal(value) || ...
        ~isvector(value) || any(~isfinite(value(:))) || ...
        any(value(:) ~= 0 & value(:) ~= 1)
    error('sixgr:truth:ExecutedHARQInvalidBits', ...
        '%s must be a finite binary vector; casting/rounding is not validation.',label);
end
bits = int8(value(:));
end

function localSize(value,expected,label)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ...
        ~isfinite(value) || double(value) ~= double(expected)
    error('sixgr:truth:ExecutedHARQSizeMismatch', ...
        '%s must equal the actual transmitted size (%d in the declared units).',label,expected);
end
end

function localGrant(grant,nBits,direction,label)
if ~isstruct(grant) || ~isscalar(grant)
    error('sixgr:truth:ExecutedHARQInvalidGrant','%s must be a scalar executed grant.',label);
end
if isfield(grant,'Direction') && ~isequal(upper(string(grant.Direction)),direction)
    error('sixgr:truth:ExecutedHARQGrantDirectionMismatch', ...
        '%s belongs to a different link direction.',label);
end
hasSize = false;
for field = ["TBSBits","TransportBlockSize","TBSBytes"]
    if isfield(grant,field)
        expected = nBits;
        if field == "TBSBytes", expected = nBits/8; end
        localSize(grant.(field),expected,label+"."+field);
        hasSize = true;
    end
end
coding = sixgr.util.structGet(grant,'PHYGrant.CodingLayout',struct());
for field = ["TBSBits","TBSBytes"]
    if isstruct(coding) && isfield(coding,field)
        expected = nBits;
        if field == "TBSBytes", expected = nBits/8; end
        localSize(coding.(field),expected,label+".PHYGrant.CodingLayout."+field);
        hasSize = true;
    end
end
if ~hasSize
    error('sixgr:truth:ExecutedHARQMissingGrantSize', ...
        '%s has no finalized transport-block size authority.',label);
end
% ScheduledTransportBlockSize is deliberately not rewritten or compared:
% a tentative scheduler allocation is distinct from the finalized PHY TB.
end

function value = localFlag(value,label)
if ~(isnumeric(value) || islogical(value)) || ~isreal(value) || ...
        ~isscalar(value) || ~isfinite(value) || (value ~= 0 && value ~= 1)
    error('sixgr:truth:ExecutedHARQInvalidDecodeFlag','%s must be a scalar boolean.',label);
end
value = logical(value);
end
