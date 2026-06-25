function [cbs, seg] = segmentLDPC(blk, bgn)
%SEGMENTLDPC LDPC code block segmentation (TB -> code blocks).
%
%   [cbs, seg] = sixgr.phy.tb.segmentLDPC(blk, bgn) segments the input data
%   block blk into LDPC code block segments using nrCodeBlockSegmentLDPC.
%
%   The input blk is typically the transport block after TB CRC attachment
%   (CRC24A/CRC24B). When segmentation occurs, the function appends a type-24B
%   CRC to each code block and may insert filler bits, per TS 38.212.
%
%   Inputs:
%     blk - Column vector of bits (0/1). Data types: double, int8, logical.
%     bgn - Base graph number for LDPC (1 or 2).
%
%   Outputs:
%     cbs - Matrix of code block segments. Each column is one code block.
%     seg - Struct with metadata needed for desegmentation:
%           .bgn      (int8)  Base graph number
%           .blklen   (int32) Original blk length (before segmentation)
%           .nCB      (int32) Number of code blocks
%           .cbLen    (int32) Length of each code block segment (rows of cbs)
%           .hasCBCRC (logical) True when nCB > 1 (CRC24B appended)

    if nargin < 2 || isempty(bgn)
        error('sixgr:segmentLDPC:MissingBGN', 'Base graph number bgn (1 or 2) is required.');
    end

    blk = blk(:);
    cbs = nrCodeBlockSegmentLDPC(blk, bgn);

    seg = struct();
    seg.bgn = int8(bgn);
    seg.blklen = int32(numel(blk));
    seg.nCB = int32(size(cbs, 2));
    seg.cbLen = int32(size(cbs, 1));
    seg.hasCBCRC = (seg.nCB > 1);
    seg.B = uint32(numel(blk));
    seg.C = uint16(size(cbs, 2));
    seg.K = uint32(size(cbs, 1));
    seg.CBCRCType = "";
    seg.CBCRCLength = uint16(0);
    if seg.nCB > 1
        seg.CBCRCType = "24B";
        seg.CBCRCLength = uint16(24);
    end
    fillerMask = cbs < 0;
    seg.FillerCount = uint32(nnz(fillerMask));
    seg.FillerPositions = cell(1, size(cbs, 2));
    for c = 1:size(cbs, 2)
        seg.FillerPositions{c} = uint32(find(fillerMask(:, c)));
    end
end
