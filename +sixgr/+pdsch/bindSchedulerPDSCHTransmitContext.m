function request = bindSchedulerPDSCHTransmitContext(request, cfg, grant, absoluteSlot, phyGrant)
%BINDSCHEDULERPDSCHTRANSMITCONTEXT Validate authored DCI, never a UE decode.
% Parsing the transmitter's bits verifies schedule consistency. It is NOT
% PDCCH reception: no CRC, channel, measurement, or receiver authority is
% produced here. PDSCH_Rx independently requires its decoded-grant binding.
arguments
    request (1,1) struct
    cfg (1,1) struct
    grant (1,1) struct
    absoluteSlot (1,1) double {mustBeInteger,mustBeNonnegative}
    phyGrant (1,1) struct
end
if ~isequal(sixgr.util.structGet(phyGrant,'IsFrozen',false),true)
    error('sixgr:pdsch:UnfrozenSchedulerTruthPHYGrant', ...
        'Authored scheduler DCI binding requires the executed frozen PHY grant.');
end
dci = sixgr.util.structGet(grant, 'DCI', struct());
bits = sixgr.util.structGet(dci, 'Bits', []);
if ~(isstruct(dci) && isscalar(dci) && ...
        (isnumeric(bits) || islogical(bits)) && isreal(bits) && ...
        isvector(bits) && ~isempty(bits) && all(bits(:) == 0 | bits(:) == 1) && ...
        isfield(dci, 'ContextData') && isfield(dci, 'Format'))
    error('sixgr:pdsch:MissingAuthoredSchedulerDCI', ...
        'PDSCH transmission requires actual binary DCI payload and its serialization context.');
end
format = string(dci.Format);
if ~isscalar(format)
    error('sixgr:pdsch:InvalidAuthoredSchedulerDCI', ...
        'PDSCH transmission requires a supported DL assignment DCI format.');
end
format = sixgr.phy.pdcch.normalizeDCIFormat(format);
if ~any(format == ["1_0", "1_1"])
    error('sixgr:pdsch:InvalidAuthoredSchedulerDCI', ...
        'PDSCH transmission requires a supported DL assignment DCI format.');
end
context = sixgr.phy.pdcch.DCIContext(dci.ContextData);
active = sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg, grant, format);
if context.Digest ~= active.Digest || ...
        string(sixgr.util.structGet(dci, 'ContextDigest', "")) ~= context.Digest
    error('sixgr:pdsch:StaleAuthoredSchedulerDCIContext', ...
        'Authored DCI must use the active RNTI/BWP/TDRA/configuration epoch.');
end
authored = sixgr.phy.pdcch.decodeDCIPayload(bits, format, context);
if string(sixgr.util.structGet(dci, 'PayloadHash', "")) ~= authored.PayloadHash
    error('sixgr:pdsch:AuthoredSchedulerDCIPayloadMismatch', ...
        'Authored DCI payload identity differs from its actual bits.');
end
fields = authored.Fields;
timing = sixgr.pdsch.resolveSchedulerPDSCHTiming(grant, absoluteSlot);
% The current contextual DCI schema has one TB's MCS/NDI/RV. Do not silently
% duplicate those values across two codewords to claim unsupported signaling.
if request.NumCodewords ~= 1
    error('sixgr:pdsch:UnsupportedSchedulerDCICodewordScope', ...
        'The active scheduler DCI schema does not signal two transport blocks.');
end
localEqual(context.Data.RNTIValue, request.RNTI, 'RNTI');
localEqual(fields.prb_start + (0:fields.num_prb-1), ...
    request.PRBSetBWPRelative, 'PRB allocation');
localEqual([fields.symbol_start fields.num_symbols], ...
    request.SymbolAllocation, 'symbol allocation');
localEqual(fields.timing_offset_slots, timing.K0, 'TDRA K0');
localEqual(fields.mcs, request.MCSIndexPerCodeword, 'MCS');
localEqual(fields.rv, request.RVPerCodeword, 'RV');
localEqual(fields.harq_process, localRequiredAlias(grant, ...
    ["HARQ.HarqID", "HARQ.HARQProcess", "HARQProcess", "HarqID"], 'HARQ process'), 'HARQ process');
localEqual(fields.ndi, localRequiredAlias(grant, ...
    ["HARQ.NDI", "NDI"], 'NDI'), 'NDI');
localEqual(fields.harq_process, ...
    sixgr.util.structGet(phyGrant,'HARQProcessKey.HARQProcess',NaN), 'frozen HARQ process');
localEqual(fields.ndi, ...
    sixgr.util.structGet(phyGrant,'HARQProcessKey.NDI',NaN), 'frozen NDI');
localEqual(context.Data.RNTIValue, ...
    sixgr.util.structGet(phyGrant,'HARQProcessKey.RNTI',NaN), 'frozen HARQ RNTI');

request.UEId = double(sixgr.util.structGet(grant, 'UEIndex', ...
    sixgr.util.structGet(grant, 'UEID', request.UEId)));
request.RNTIType = string(context.Data.RNTIType);
request.ServingCellId = double(sixgr.util.structGet(grant, 'ServingCell', request.ServingCellId));
request.SchedulingCellId = double(sixgr.util.structGet(grant, 'SchedulingCell', request.ServingCellId));
request.CCId = double(sixgr.util.structGet(grant, 'CCId', request.CCId));
request.BWPId = double(context.Data.ScheduledBWP);
request.ConfigurationEpoch = double(context.Data.ConfigurationEpoch);
request.HARQProcessId = double(fields.harq_process);
request.NDIPerCodeword = double(fields.ndi);
request.ScheduledDCIId = authored.PayloadHash;
request.DCIFormat = format;
request.SearchSpaceId = double(context.Data.SearchSpaceID);
request.CORESETId = double(context.Data.CORESETID);
request.PDCCHAbsoluteSlot = timing.PDCCHAbsoluteSlot;
request.K0 = timing.K0;
end

function localEqual(actual, expected, name)
if ~isequal(double(actual(:).'), double(expected(:).'))
    error('sixgr:pdsch:AuthoredSchedulerDCIAllocationMismatch', ...
        'Authored DCI %s=%s differs from materialized scheduler PDSCH %s.', ...
        name,mat2str(actual),mat2str(expected));
end
end

function value = localRequiredAlias(grant, paths, name)
value = [];
for path = paths
    candidate = sixgr.util.structGet(grant, path, []);
    if isempty(candidate), continue; end
    if ~((isnumeric(candidate) || islogical(candidate)) && isscalar(candidate) && ...
            isreal(candidate) && isfinite(candidate) && candidate == fix(candidate))
        error('sixgr:pdsch:InvalidSchedulerHARQContext', ...
            'Scheduler %s must be an explicit finite integer.', name);
    end
    if ~isempty(value), localEqual(candidate, value, name + " aliases"); end
    value = double(candidate);
end
if isempty(value)
    error('sixgr:pdsch:InvalidSchedulerHARQContext', ...
        'Scheduler transmission requires explicit %s authority.', name);
end
end
