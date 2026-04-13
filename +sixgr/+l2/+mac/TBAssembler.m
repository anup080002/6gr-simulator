classdef TBAssembler
% sixgr.l2.mac.TBAssembler
% MAC multiplexing and assembly for DL-SCH / UL-SCH (simplified but spec-aligned).
%
% This implements a pragmatic subset of 3GPP TS 38.321 MAC PDU building:
%  - Supports MAC SDUs (logical channel SDUs) and MAC CEs (e.g., BSR, PHR)
%  - Orders MAC CEs and MAC SDUs per TS 38.321:
%       DL: MAC CE(s) before MAC SDU(s)
%       UL: MAC CE(s) after  MAC SDU(s)
%  - Uses R/LCID subheader for fixed-size MAC CE and padding
%  - Uses R/F/LCID/L subheader for variable-size MAC CE and MAC SDU
%
% IMPORTANT: This is intended for simulator coherence, not conformance
% testing. It is "format-correct enough" to support debugging and KPI flow.
%
% Inputs to assemble()
%   tbSizeBytes : total TB payload capacity in bytes (from nrTBS/PHY)
%   sduList     : struct array with fields:
%                  .LCID    (0..63)
%                  .Payload (uint8 vector)
%                Optional fields:
%                  .Priority (lower is higher priority)
%   ceList      : struct array with fields:
%                  .LCID
%                  .Payload
%                  .IsFixed (logical)  % fixed-size CE => no L field
%                Optional:
%                  .Name
%   direction   : 'DL' or 'UL' (default 'DL')
%
% Outputs:
%   macPduBytes : uint8(tbSizeBytes,1) (padding included)
%   info        : struct with per-subPDU offsets, etc.
%
% Keep this file ASCII-only.

    methods(Static)
        function [macPduBytes, info] = assemble(tbSizeBytes, sduList, ceList, varargin)
            ip = inputParser;
            ip.addParameter('Direction','DL',@(x) ischar(x) || isstring(x));
            ip.addParameter('AllowDropLastSDU',true,@(x) islogical(x) && isscalar(x));
            ip.addParameter('Logger',[],@(x) true);
            ip.parse(varargin{:});
            opt = ip.Results;

            dir = upper(char(string(opt.Direction)));
            tbSizeBytes = double(tbSizeBytes);

            if nargin < 2 || isempty(sduList), sduList = struct([]); end
            if nargin < 3 || isempty(ceList),  ceList  = struct([]); end

            % Normalize SDUs
            sduList = sixgr.l2.mac.TBAssembler.normalizeSDUList(sduList);
            ceList  = sixgr.l2.mac.TBAssembler.normalizeCEList(ceList);

            % Sort SDUs by priority (optional)
            if ~isempty(sduList) && isfield(sduList,'Priority')
                [~,ord] = sort([sduList.Priority],'ascend');
                sduList = sduList(ord);
            end

            % Order: DL -> CEs then SDUs; UL -> SDUs then CEs
            if strcmp(dir,'DL')
                items = [sixgr.l2.mac.TBAssembler.wrapItems(ceList,'CE'), sixgr.l2.mac.TBAssembler.wrapItems(sduList,'SDU')];
            else
                items = [sixgr.l2.mac.TBAssembler.wrapItems(sduList,'SDU'), sixgr.l2.mac.TBAssembler.wrapItems(ceList,'CE')];
            end

            tbSizeBytes = max(0, round(tbSizeBytes));
            used = zeros(tbSizeBytes, 1, 'uint8');
            needManifest = (nargout > 1);
            info = struct();
            info.Direction = dir;
            if needManifest
                maxManifest = max(1, numel(items) + 1);
                itemTemplate = sixgr.l2.mac.TBAssembler.makePaddingItem(1, 1);
                manifestBuf = repmat(itemTemplate, maxManifest, 1);
            else
                manifestBuf = sixgr.l2.mac.TBAssembler.emptyManifest();
            end
            manifestCount = 0;
            offset = 0;
            writePos = 1;

            for i = 1:numel(items)
                it = items(i);
                lcid = double(it.LCID);
                payload = it.Payload;
                payloadLen = numel(payload);

                isFixed = false;
                if strcmp(it.Type,'CE')
                    isFixed = logical(it.IsFixed);
                end

                [hdr, hdrLen] = sixgr.l2.mac.TBAssembler.buildSubheader(lcid, payloadLen, isFixed, dir);

                need = hdrLen + payloadLen;
                if (offset + need) > tbSizeBytes
                    % Not enough space
                    if strcmp(it.Type,'SDU') && opt.AllowDropLastSDU
                        if needManifest
                            manifestCount = manifestCount + 1;
                            manifestBuf(manifestCount) = sixgr.l2.mac.TBAssembler.makeManifestItem( ...
                                it, lcid, payloadLen, hdrLen, offset, true, NaN, NaN);
                        end
                        continue;
                    else
                        % Stop building, go to padding
                        break;
                    end
                end

                if hdrLen > 0
                    used(writePos:writePos+hdrLen-1) = hdr(:);
                end
                if payloadLen > 0
                    used(writePos+hdrLen:writePos+need-1) = payload(:);
                end
                startByte = offset + 1;
                endByte = offset + need;
                if needManifest
                    manifestCount = manifestCount + 1;
                    manifestBuf(manifestCount) = sixgr.l2.mac.TBAssembler.makeManifestItem( ...
                        it, lcid, payloadLen, hdrLen, offset, false, startByte, endByte);
                end
                offset = offset + need;
                writePos = writePos + need;
            end

            % Padding: add padding subPDU with LCID=63 (TS 38.321)
            rem = tbSizeBytes - offset;
            if rem < 0
                rem = 0;
            end

            if rem > 0
                padLCID = 63;
                % padding subheader is fixed (R/LCID) and padding length is implicit; but
                % we include explicit zeros to fill TB.
                padHdr = sixgr.l2.mac.TBAssembler.buildFixedHeader(padLCID);
                if rem >= 1
                    used(writePos) = padHdr;
                    if needManifest
                        manifestCount = manifestCount + 1;
                        manifestBuf(manifestCount) = sixgr.l2.mac.TBAssembler.makePaddingItem(offset+1, offset+rem);
                    end
                    info.PaddingBytes = rem-1;
                    info.PaddingSubheader = true;
                else
                    % no room even for header (shouldn't happen)
                    if needManifest
                        manifestCount = manifestCount + 1;
                        manifestBuf(manifestCount) = sixgr.l2.mac.TBAssembler.makePaddingItem(offset+1, offset+rem);
                    end
                    info.PaddingBytes = rem;
                    info.PaddingSubheader = false;
                end
            else
                info.PaddingBytes = 0;
                info.PaddingSubheader = false;
            end

            if needManifest
                if manifestCount > 0
                    info.Items = manifestBuf(1:manifestCount);
                else
                    info.Items = sixgr.l2.mac.TBAssembler.emptyManifest();
                end
            end

            macPduBytes = used;
            info.TotalBytes = tbSizeBytes;
            info.UsedBytes  = offset;
        end

        function [sdus, ces, info] = disassemble(macPduBytes, varargin)
            % Disassemble a MAC PDU (best-effort, uses LCID heuristics for fixed-size CEs).
            ip = inputParser;
            ip.addParameter('Direction','UL',@(x) ischar(x) || isstring(x));
            ip.parse(varargin{:});
            dir = upper(char(string(ip.Results.Direction)));

            b = uint8(macPduBytes(:));
            n = numel(b);

            needCE = (nargout > 1);
            needInfo = (nargout > 2);
            sTemplate = struct('LCID',0,'Payload',uint8([]),'Meta',sixgr.l2.mac.TBAssembler.defaultTraceMeta());
            maxItems = max(1, n);
            sdusBuf = repmat(sTemplate, maxItems, 1);
            if needCE
                cesBuf = repmat(sTemplate, maxItems, 1);
            else
                cesBuf = struct('LCID',{},'Payload',{},'Meta',{});
            end
            nSDU = 0;
            nCE = 0;
            info = struct();
            info.Direction = dir;
            if needInfo
                iTemplate = sixgr.l2.mac.TBAssembler.makePaddingItem(1, 1);
                infoBuf = repmat(iTemplate, maxItems, 1);
            else
                infoBuf = sixgr.l2.mac.TBAssembler.emptyManifest();
            end
            nInfo = 0;

            ptr = 1;
            while ptr <= n
                hb = b(ptr);
                lcid = double(bitand(hb, uint8(63)));
                startPtr = ptr;

                if lcid == 63
                    % Padding: rest is padding
                    info.PaddingOffset = ptr;
                    info.PaddingBytes = n - ptr + 1;
                    if needInfo
                        nInfo = nInfo + 1;
                        infoBuf(nInfo) = sixgr.l2.mac.TBAssembler.makePaddingItem(ptr, n);
                    end
                    break;
                end

                if sixgr.l2.mac.TBAssembler.isFixedLCID(lcid, dir)
                    ptr = ptr + 1;
                    L = sixgr.l2.mac.TBAssembler.fixedPayloadLength(lcid, dir);
                    if ptr+L-1 > n
                        L = max(0, n-ptr+1);
                    end
                    payload = b(ptr:ptr+L-1);
                    ptr = ptr + L;
                    endPtr = ptr - 1;
                    m = sixgr.l2.mac.TBAssembler.defaultTraceMeta();
                    m.SegmentOffset = 0;
                    item = struct('Type',"SDU",'LCID',lcid,'Payload',payload,'IsFixed',true,'Meta',m);

                    if sixgr.l2.mac.TBAssembler.isCE_LCID(lcid, dir)
                        item.Type = "CE";
                        if needCE
                            nCE = nCE + 1;
                            cesBuf(nCE) = struct('LCID',lcid,'Payload',payload,'Meta',m);
                        end
                    else
                        nSDU = nSDU + 1;
                        sdusBuf(nSDU) = struct('LCID',lcid,'Payload',payload,'Meta',m);
                    end
                    if needInfo
                        nInfo = nInfo + 1;
                        infoBuf(nInfo) = sixgr.l2.mac.TBAssembler.makeManifestItem( ...
                            item, lcid, numel(payload), 1, startPtr-1, false, startPtr, endPtr);
                    end
                else
                    % Variable header: R/F/LCID then L (8 or 16 bits)
                    f = bitget(hb, 7); % F is bit6 => position7
                    ptr = ptr + 1;
                    hdrLen = 1;
                    if f == 0
                        if ptr > n, break; end
                        L = double(b(ptr));
                        ptr = ptr + 1;
                        hdrLen = hdrLen + 1;
                    else
                        if ptr+1 > n, break; end
                        L = double(b(ptr))*256 + double(b(ptr+1));
                        ptr = ptr + 2;
                        hdrLen = hdrLen + 2;
                    end
                    if ptr+L-1 > n
                        L = max(0, n-ptr+1);
                    end
                    payload = b(ptr:ptr+L-1);
                    ptr = ptr + L;
                    endPtr = ptr - 1;
                    m = sixgr.l2.mac.TBAssembler.defaultTraceMeta();
                    item = struct('Type',"SDU",'LCID',lcid,'Payload',payload,'IsFixed',false,'Meta',m);

                    if sixgr.l2.mac.TBAssembler.isCE_LCID(lcid, dir)
                        item.Type = "CE";
                        if needCE
                            nCE = nCE + 1;
                            cesBuf(nCE) = struct('LCID',lcid,'Payload',payload,'Meta',m);
                        end
                    else
                        nSDU = nSDU + 1;
                        sdusBuf(nSDU) = struct('LCID',lcid,'Payload',payload,'Meta',m);
                    end
                    if needInfo
                        nInfo = nInfo + 1;
                        infoBuf(nInfo) = sixgr.l2.mac.TBAssembler.makeManifestItem( ...
                            item, lcid, numel(payload), hdrLen, startPtr-1, false, startPtr, endPtr);
                    end
                end
            end

            if nSDU > 0
                sdus = sdusBuf(1:nSDU);
            else
                sdus = struct('LCID',{},'Payload',{},'Meta',{});
            end
            if needCE && nCE > 0
                ces = cesBuf(1:nCE);
            else
                ces = struct('LCID',{},'Payload',{},'Meta',{});
            end
            if needInfo
                if nInfo > 0
                    info.Items = infoBuf(1:nInfo);
                else
                    info.Items = sixgr.l2.mac.TBAssembler.emptyManifest();
                end
            end
        end

        function bits = bytesToBits(bytes)
            % bytesToBits Convert uint8 column to column bits (left-msb).
            b = uint8(bytes(:));
            if isempty(b)
                bits = int8([]);
                return;
            end
            if exist("sixgr_tb_bytes_to_bits_kernel_mex", "file") == 3
                try
                    bits = sixgr_tb_bytes_to_bits_kernel_mex(b);
                    return;
                catch
                end
            end
            bits = sixgr_tb_bytes_to_bits_kernel(b);
        end

        function bytes = bitsToBytes(bits)
            % bitsToBytes Convert column bits (0/1) to uint8 bytes (left-msb), truncating extra bits.
            v = bits(:);
            v = uint8(v ~= 0);
            n8 = floor(numel(v)/8);
            if n8 <= 0
                bytes = uint8([]);
                return;
            end
            if exist("sixgr_tb_bits_to_bytes_kernel_mex", "file") == 3
                try
                    bytes = sixgr_tb_bits_to_bytes_kernel_mex(v);
                    return;
                catch
                end
            end
            bytes = sixgr_tb_bits_to_bytes_kernel(v);
        end
    end

    methods(Static, Access=private)
        function sduList = normalizeSDUList(sduList)
            if isempty(sduList)
                sduList = struct('LCID',{},'Payload',{},'Priority',{},'Meta',{});
                return;
            end
            if ~isstruct(sduList)
                error('sixgr:TBAssembler:BadSDU','sduList must be a struct array.');
            end
            if ~isfield(sduList,'LCID') || ~isfield(sduList,'Payload')
                error('sixgr:TBAssembler:BadSDU','sduList must have fields LCID and Payload.');
            end
            for i = 1:numel(sduList)
                if ~isa(sduList(i).Payload,'uint8')
                    sduList(i).Payload = uint8(sduList(i).Payload(:));
                else
                    sduList(i).Payload = sduList(i).Payload(:);
                end
                if ~isfield(sduList(i),'Priority') || isempty(sduList(i).Priority)
                    sduList(i).Priority = 100;
                end
                if ~isfield(sduList(i),'Meta') || isempty(sduList(i).Meta)
                    sduList(i).Meta = sixgr.l2.mac.TBAssembler.defaultTraceMeta();
                else
                    sduList(i).Meta = sixgr.l2.mac.TBAssembler.normalizeTraceMeta(sduList(i).Meta);
                end
            end
        end

        function ceList = normalizeCEList(ceList)
            if isempty(ceList)
                ceList = struct('LCID',{},'Payload',{},'IsFixed',{},'Name',{},'Meta',{});
                return;
            end
            if ~isstruct(ceList)
                error('sixgr:TBAssembler:BadCE','ceList must be a struct array.');
            end
            if ~isfield(ceList,'LCID') || ~isfield(ceList,'Payload')
                error('sixgr:TBAssembler:BadCE','ceList must have fields LCID and Payload.');
            end
            if ~isfield(ceList,'IsFixed')
                for i = 1:numel(ceList)
                    ceList(i).IsFixed = false;
                end
            end
            for i = 1:numel(ceList)
                if ~isa(ceList(i).Payload,'uint8')
                    ceList(i).Payload = uint8(ceList(i).Payload(:));
                else
                    ceList(i).Payload = ceList(i).Payload(:);
                end
                if ~isfield(ceList(i),'Name') || isempty(ceList(i).Name)
                    ceList(i).Name = '';
                end
                if ~isfield(ceList(i),'Meta') || isempty(ceList(i).Meta)
                    ceList(i).Meta = sixgr.l2.mac.TBAssembler.defaultTraceMeta();
                else
                    ceList(i).Meta = sixgr.l2.mac.TBAssembler.normalizeTraceMeta(ceList(i).Meta);
                end
            end
        end

        function items = wrapItems(list, typeStr)
            items = struct('Type',{},'LCID',{},'Payload',{},'IsFixed',{},'Meta',{});
            if isempty(list), return; end
            n = numel(list);
            if n <= 0, return; end
            t = struct('Type',"",'LCID',0,'Payload',uint8([]),'IsFixed',false,'Meta',sixgr.l2.mac.TBAssembler.defaultTraceMeta());
            items = repmat(t, 1, n);
            for i = 1:numel(list)
                items(i).Type = typeStr;
                items(i).LCID = double(list(i).LCID);
                items(i).Payload = list(i).Payload(:);
                if strcmp(typeStr,'CE') && isfield(list(i),'IsFixed')
                    items(i).IsFixed = logical(list(i).IsFixed);
                else
                    items(i).IsFixed = false;
                end
                if isfield(list(i),'Meta')
                    items(i).Meta = sixgr.l2.mac.TBAssembler.normalizeTraceMeta(list(i).Meta);
                else
                    items(i).Meta = sixgr.l2.mac.TBAssembler.defaultTraceMeta();
                end
            end
        end

        function m = emptyManifest()
            m = struct('Type',{},'LCID',{},'PayloadLen',{},'HeaderLen',{},'Offset',{}, ...
                'StartByte',{},'EndByte',{},'Dropped',{},'IsCE',{},'IsSDU',{}, ...
                'PktId',{},'FlowId',{},'QFI',{},'PDCP_SN',{},'RLC_SN',{},'SegmentOffset',{}, ...
                'HARQProcess',{},'GrantSlot',{},'DeliverySlot',{},'DropCause',{},'Meta',{});
        end

        function item = makeManifestItem(it, lcid, payloadLen, hdrLen, offset, dropped, startByte, endByte)
            tr = sixgr.l2.mac.TBAssembler.defaultTraceMeta();
            if isstruct(it) && isfield(it,'Meta')
                tr = sixgr.l2.mac.TBAssembler.normalizeTraceMeta(it.Meta);
            end
            typ = string(sixgr.util.structGet(it, "Type", "SDU"));
            item = struct( ...
                'Type', typ, ...
                'LCID', double(lcid), ...
                'PayloadLen', double(payloadLen), ...
                'HeaderLen', double(hdrLen), ...
                'Offset', double(offset), ...
                'StartByte', double(startByte), ...
                'EndByte', double(endByte), ...
                'Dropped', logical(dropped), ...
                'IsCE', logical(typ == "CE"), ...
                'IsSDU', logical(typ == "SDU"), ...
                'PktId', double(tr.PktId), ...
                'FlowId', double(tr.FlowId), ...
                'QFI', double(tr.QFI), ...
                'PDCP_SN', double(tr.PDCP_SN), ...
                'RLC_SN', double(tr.RLC_SN), ...
                'SegmentOffset', double(tr.SegmentOffset), ...
                'HARQProcess', double(tr.HARQProcess), ...
                'GrantSlot', double(tr.GrantSlot), ...
                'DeliverySlot', double(tr.DeliverySlot), ...
                'DropCause', string(tr.DropCause), ...
                'Meta', tr);
        end

        function item = makePaddingItem(startByte, endByte)
            tr = sixgr.l2.mac.TBAssembler.defaultTraceMeta();
            item = struct( ...
                'Type', "PADDING", ...
                'LCID', 63, ...
                'PayloadLen', max(0, double(endByte - startByte)), ...
                'HeaderLen', 1, ...
                'Offset', double(startByte - 1), ...
                'StartByte', double(startByte), ...
                'EndByte', double(endByte), ...
                'Dropped', false, ...
                'IsCE', false, ...
                'IsSDU', false, ...
                'PktId', double(tr.PktId), ...
                'FlowId', double(tr.FlowId), ...
                'QFI', double(tr.QFI), ...
                'PDCP_SN', double(tr.PDCP_SN), ...
                'RLC_SN', double(tr.RLC_SN), ...
                'SegmentOffset', double(tr.SegmentOffset), ...
                'HARQProcess', double(tr.HARQProcess), ...
                'GrantSlot', double(tr.GrantSlot), ...
                'DeliverySlot', double(tr.DeliverySlot), ...
                'DropCause', "MAC_PADDING", ...
                'Meta', tr);
        end

        function tr = defaultTraceMeta()
            persistent trTemplate;
            if isempty(trTemplate)
                trTemplate = struct( ...
                    "PktId", NaN, ...
                    "FlowId", NaN, ...
                    "QFI", NaN, ...
                    "CreationSlot", NaN, ...
                    "CreationTime_s", NaN, ...
                    "PDCP_SN", NaN, ...
                    "RLC_SN", NaN, ...
                    "SegmentOffset", NaN, ...
                    "HARQProcess", NaN, ...
                    "GrantSlot", NaN, ...
                    "DeliverySlot", NaN, ...
                    "DropCause", "");
            end
            tr = trTemplate;
        end

        function tr = normalizeTraceMeta(in)
            tr = sixgr.l2.mac.TBAssembler.defaultTraceMeta();
            if isempty(in) || ~isstruct(in)
                return;
            end
            if isfield(in, "PktId"), tr.PktId = in.PktId; end
            if isfield(in, "FlowId"), tr.FlowId = in.FlowId; end
            if isfield(in, "QFI"), tr.QFI = in.QFI; end
            if isfield(in, "CreationSlot"), tr.CreationSlot = in.CreationSlot; end
            if isfield(in, "CreationTime_s"), tr.CreationTime_s = in.CreationTime_s; end
            if isfield(in, "PDCP_SN"), tr.PDCP_SN = in.PDCP_SN; end
            if isfield(in, "RLC_SN"), tr.RLC_SN = in.RLC_SN; end
            if isfield(in, "SegmentOffset"), tr.SegmentOffset = in.SegmentOffset; end
            if isfield(in, "HARQProcess"), tr.HARQProcess = in.HARQProcess; end
            if isfield(in, "GrantSlot"), tr.GrantSlot = in.GrantSlot; end
            if isfield(in, "DeliverySlot"), tr.DeliverySlot = in.DeliverySlot; end
            if isfield(in, "DropCause") && strlength(string(in.DropCause)) > 0
                tr.DropCause = in.DropCause;
            end
        end

        function [hdr, hdrLen] = buildSubheader(lcid, payloadLen, isFixed, direction)
            %#ok<INUSD> direction
            lcid = double(lcid);
            payloadLen = double(payloadLen);
            isFixed = logical(isFixed);

            if isFixed
                hdr = sixgr.l2.mac.TBAssembler.buildFixedHeader(lcid);
                hdrLen = 1;
                return;
            end

            % Variable: R/F/LCID + L
            if payloadLen <= 255
                F = 0;
                hdr = [sixgr.l2.mac.TBAssembler.buildVarHeader(lcid, F); uint8(payloadLen)];
                hdrLen = 2;
            else
                F = 1;
                L1 = floor(payloadLen/256);
                L2 = mod(payloadLen,256);
                hdr = [sixgr.l2.mac.TBAssembler.buildVarHeader(lcid, F); uint8(L1); uint8(L2)];
                hdrLen = 3;
            end
        end

        function hb = buildFixedHeader(lcid)
            % R/LCID header: [R R LCID] => reserved bits 0, LCID in low 6 bits
            hb = uint8(bitand(uint8(lcid), uint8(63)));
        end

        function hb = buildVarHeader(lcid, F)
            % R/F/LCID header: R=0, F in bit6 (position7), LCID in low 6 bits
            hb = bitor(uint8(bitand(uint8(lcid),uint8(63))), bitshift(uint8(F~=0),6));
        end

        function tf = isFixedLCID(lcid, direction)
            % LCIDs that are fixed-size and therefore use R/LCID header.
            tf = false;
            dir = upper(direction);
            if strcmp(dir,'UL')
                % TS 38.321 Table 6.2.1-2 includes:
                % 0 CCCH1 (64 bits), 57 PHR, 58 C-RNTI, 59/61 short BSRs, 63 padding.
                tf = ismember(lcid, [0 57 58 59 61 63]);
            else
                % Minimal DL set (extend later as needed).
                % Table 6.2.1-1: 60 DRX cmd (0 bits), 61 TA cmd (1 byte), 62 UE CR id (6 bytes), 63 padding.
                tf = ismember(lcid, [60 61 62 63]);
            end
        end

        function L = fixedPayloadLength(lcid, direction)
            dir = upper(direction);
            if strcmp(dir,'UL')
                switch lcid
                    case 0
                        L = 8;  % UL CCCH1 is 64 bits
                    case 57
                        L = 2;  % Single Entry PHR
                    case 58
                        L = 2;  % C-RNTI
                    case 59
                        L = 1;  % Short Truncated BSR
                    case 61
                        L = 1;  % Short BSR
                    otherwise
                        L = 0;
                end
            else
                switch lcid
                    case 60
                        L = 0;  % DRX command
                    case 61
                        L = 1;  % Timing Advance Command
                    case 62
                        L = 6;  % UE Contention Resolution Identity
                    otherwise
                        L = 0;
                end
            end
        end

        function tf = isCE_LCID(lcid, direction)
            dir = upper(direction);
            if strcmp(dir,'UL')
                tf = ismember(lcid, [57 58 59 60 61 62]);
            else
                tf = ismember(lcid, [59 60 61 62]);
            end
        end
    end
end

