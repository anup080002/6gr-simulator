function [blk, err] = desegmentLDPC(cbs, bgnOrSeg, blklen)
%DESEGMENTLDPC LDPC code block desegmentation (code blocks -> TB).
%
%   [blk, err] = sixgr.phy.tb.desegmentLDPC(cbs, bgn, blklen) concatenates
%   the input code block segments cbs into a single output data block blk of
%   length blklen using nrCodeBlockDesegmentLDPC.
%
%   [blk, err] = sixgr.phy.tb.desegmentLDPC(cbs, seg) uses seg metadata
%   returned by sixgr.phy.tb.segmentLDPC (fields: bgn, blklen).
%
%   Inputs:
%     cbs      - Code block segments matrix (each column one code block).
%     bgnOrSeg - Base graph number (1/2) OR seg struct from segmentLDPC.
%     blklen   - (Required if bgnOrSeg is numeric) Original blk length.
%
%   Outputs:
%     blk - Concatenated data block with filler bits and CRC24B removed.
%     err - CRC error vector from CRC24B decoding (if applicable).

    if nargin < 2
        error('sixgr:desegmentLDPC:NotEnoughInputs', 'At least 2 inputs are required.');
    end

    if nargin == 2
        seg = bgnOrSeg;
        if ~builtin('isstruct', seg)
            error('sixgr:desegmentLDPC:BadSignature', 'Second input must be a seg struct when called with 2 inputs.');
        end
        if isfield(seg, "BaseGraph")
            bgn = double(seg.BaseGraph);
        else
            bgn = double(seg.bgn);
        end
        if isfield(seg, "TransportBlockLengthWithCRC")
            blklen = double(seg.TransportBlockLengthWithCRC);
        elseif isfield(seg, "B")
            blklen = double(seg.B);
        else
            blklen = double(seg.blklen);
        end
    else
        bgn = bgnOrSeg;
        if nargin < 3 || isempty(blklen)
            error('sixgr:desegmentLDPC:MissingBlkLen', 'blklen is required when bgn is provided.');
        end
    end

    [blk, err] = nrCodeBlockDesegmentLDPC(cbs, bgn, blklen);
end
