classdef BSR_PHR < handle
% sixgr.l2.mac.BSR_PHR
% Buffer Status Report (BSR) and Power Headroom Report (PHR) helper.
%
% This class provides:
%  - UE-side state for UL buffer occupancy per Logical Channel Group (LCG)
%  - Encoding of Short BSR (fixed size) and Long BSR (variable size)
%  - Encoding of Single Entry PHR (fixed size, 2 octets)
%  - Decoding helpers for gNB-side parsing
%
% It follows TS 38.321 high-level structure:
%  - Short BSR: fixed size, includes 3-bit LCG ID and 5-bit Buffer Size index
%  - Long BSR: variable size, includes LCG bitmap and 8-bit Buffer Size indices
%  - PHR: 2 octets with 6-bit PH plus flags (simplified quantization)
%
% IMPORTANT: Exact dB mapping for PH/PCMAX indices is defined in TS 38.133.
% For simulation coherence we use a common 1 dB quantization mapping:
%   PH_index = clamp(round(PH_dB) + 23, 0, 63)
% This matches the typical LTE/NR representation range [-23..40] dB.
%
% Keep this file ASCII-only.

    properties
        NumLCG (1,1) double = 8
        LCGBufferBytes (1,:) double = zeros(1,8) % bytes per LCG
        LastPH_dB (1,1) double = 0
        LastPCMAX_dBm (1,1) double = 23
    end

    methods
        function obj = BSR_PHR(varargin)
            % Optional name-value:
            %   'NumLCG' : number of LCGs (default 8)
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:BSR_PHR:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    key = varargin{i};
                    val = varargin{i+1};
                    if isstring(key), key = char(key); end
                    switch lower(char(key))
                        case 'numlcg'
                            obj.NumLCG = double(val);
                    end
                end
            end
            obj.NumLCG = max(1, min(8, round(obj.NumLCG)));
            obj.LCGBufferBytes = zeros(1, obj.NumLCG);
        end

        function setLCGBuffer(obj, lcgId, bytes)
            lcgId = double(lcgId);
            if lcgId < 0 || lcgId > obj.NumLCG-1
                error('sixgr:BSR_PHR:BadLCG','LCG ID must be in [0..%d].', obj.NumLCG-1);
            end
            obj.LCGBufferBytes(lcgId+1) = max(0, double(bytes));
        end

        function addLCGBuffer(obj, lcgId, bytesDelta)
            lcgId = double(lcgId);
            obj.setLCGBuffer(lcgId, obj.LCGBufferBytes(lcgId+1) + double(bytesDelta));
        end

        function ce = makeBSR(obj, varargin)
            % makeBSR Build a BSR MAC CE struct suitable for TBAssembler.
            %
            % Name-Value:
            %  'Format'    : 'short'|'long'|'auto' (default 'auto')
            %  'Truncated' : true/false (default false)  (reserved)
            ip = inputParser;
            ip.addParameter('Format','auto',@(x) ischar(x) || isstring(x));
            ip.addParameter('Truncated',false,@(x) islogical(x) && isscalar(x));
            ip.parse(varargin{:});
            opt = ip.Results;

            fmt = lower(char(string(opt.Format)));
            %#ok<NASGU> truncated = logical(opt.Truncated); % reserved

            lcgBytes = obj.LCGBufferBytes;
            active = find(lcgBytes > 0);
            if isempty(active)
                % Nothing to report; return empty
                ce = struct([]);
                return;
            end

            if strcmp(fmt,'auto')
                if numel(active) == 1
                    fmt = 'short';
                else
                    fmt = 'long';
                end
            end

            switch fmt
                case 'short'
                    lcgId = active(1)-1;
                    payload = sixgr.l2.mac.BSR_PHR.encodeShortBSR(lcgId, lcgBytes(active(1)));
                    ce = struct('LCID',61,'Payload',payload,'IsFixed',true,'Name','ShortBSR'); % LCID 61
                case 'long'
                    payload = sixgr.l2.mac.BSR_PHR.encodeLongBSR(lcgBytes);
                    ce = struct('LCID',62,'Payload',payload,'IsFixed',false,'Name','LongBSR'); % LCID 62 (variable size)
                otherwise
                    error('sixgr:BSR_PHR:BadFormat','Unknown BSR format: %s', fmt);
            end
        end

        function ce = makePHR(obj, ph_dB, pcmax_dBm, varargin)
            % makePHR Build a Single Entry PHR MAC CE (2 octets).
            %
            % Inputs:
            %   ph_dB      : power headroom in dB (Pmax - Ptx), Type1
            %   pcmax_dBm  : nominal max UE tx power used (approx)
            %
            % Name-Value:
            %   'PowerBackoff' : logical (P field). default false.
            ip = inputParser;
            ip.addParameter('PowerBackoff',false,@(x) islogical(x) && isscalar(x));
            ip.parse(varargin{:});
            opt = ip.Results;

            obj.LastPH_dB = double(ph_dB);
            obj.LastPCMAX_dBm = double(pcmax_dBm);

            payload = sixgr.l2.mac.BSR_PHR.encodeSingleEntryPHR(ph_dB, pcmax_dBm, opt.PowerBackoff);
            ce = struct('LCID',57,'Payload',payload,'IsFixed',true,'Name','PHR_SingleEntry'); % LCID 57
        end
    end

    methods(Static)
        function payload = encodeShortBSR(lcgId, bufferBytes)
            % Short BSR MAC CE payload (1 octet):
            %   bits[7:5] LCG ID (3 bits)
            %   bits[4:0] Buffer Size index (5 bits)
            lcgId = double(lcgId);
            if lcgId < 0 || lcgId > 7
                error('sixgr:BSR_PHR:BadLCG','LCG ID must be 0..7 for short BSR.');
            end
            idx = sixgr.l2.mac.BSR_PHR.bufferSizeIndex5bit(bufferBytes);
            b = bitshift(uint8(lcgId),5) + uint8(idx);
            payload = uint8(b);
        end

        function [lcgId, bufferBytesEst] = decodeShortBSR(payload)
            b = uint8(payload(1));
            lcgId = double(bitshift(b,-5));
            idx = double(bitand(b, uint8(31)));
            bufferBytesEst = sixgr.l2.mac.BSR_PHR.bufferSizeFromIndex5bit(idx);
        end

        function payload = encodeLongBSR(lcgBytes)
            % Long BSR payload (variable):
            %   Oct1: bitmap LCG7..LCG0 (bit=1 => include buffer size field)
            %   Then: Buffer Size fields (8-bit indices) for each LCGi=1 in ascending i.
            lcgBytes = double(lcgBytes(:).');
            nLCG = min(numel(lcgBytes), 8);
            lcgBytes = [lcgBytes(1:nLCG) zeros(1,8-nLCG)];

            bitmap = uint8(0);
            for i = 0:7
                if lcgBytes(i+1) > 0
                    bitmap = bitor(bitmap, bitshift(uint8(1), i));
                end
            end

            fields = uint8([]);
            for i = 0:7
                if bitand(bitmap, bitshift(uint8(1),i)) ~= 0
                    idx8 = sixgr.l2.mac.BSR_PHR.bufferSizeIndex8bit(lcgBytes(i+1));
                    fields(end+1,1) = uint8(idx8); %#ok<AGROW>
                end
            end

            payload = [bitmap; fields];
        end

        function lcgBytesEst = decodeLongBSR(payload)
            b = uint8(payload(:));
            if isempty(b)
                lcgBytesEst = zeros(1,8);
                return;
            end
            bitmap = b(1);
            ptr = 2;
            lcgBytesEst = zeros(1,8);
            for i = 0:7
                if bitand(bitmap, bitshift(uint8(1),i)) ~= 0
                    if ptr > numel(b)
                        break;
                    end
                    idx8 = double(b(ptr));
                    ptr = ptr + 1;
                    lcgBytesEst(i+1) = sixgr.l2.mac.BSR_PHR.bufferSizeFromIndex8bit(idx8);
                end
            end
        end

        function payload = encodeSingleEntryPHR(ph_dB, pcmax_dBm, powerBackoff)
            % Single Entry PHR MAC CE (2 octets) per TS 38.321 Figure 6.1.3.8-1.
            %
            % We encode:
            %  - PH: 6 bits (index 0..63), approx mapping [-23..40] dB.
            %  - P : 1 bit (power backoff flag)
            %  - PCMAX,f,c: 6 bits (index 0..63), approximate mapping to dBm
            %  - Remaining bits: set to 0 (R bits / MPE not modelled here)
            phIdx = sixgr.l2.mac.BSR_PHR.quantizePH(ph_dB);
            pcIdx = sixgr.l2.mac.BSR_PHR.quantizePCMAX(pcmax_dBm);
            P = uint8(powerBackoff ~= 0);

            % Octet1: [R(1)=0 | PH(6) | P(1)]
            oct1 = bitshift(uint8(phIdx),1) + uint8(P);

            % Octet2: [R(1)=0 | PCMAX(6) | R(1)=0] (we ignore MPE)
            oct2 = bitshift(uint8(pcIdx),1);

            payload = uint8([oct1; oct2]);
        end

        function [ph_dB_est, pcmax_dBm_est, P] = decodeSingleEntryPHR(payload)
            b = uint8(payload(:));
            if numel(b) < 2
                ph_dB_est = NaN;
                pcmax_dBm_est = NaN;
                P = false;
                return;
            end
            oct1 = b(1);
            oct2 = b(2);

            P = logical(bitand(oct1,1));
            phIdx = double(bitshift(oct1,-1));
            pcIdx = double(bitshift(oct2,-1));

            ph_dB_est = sixgr.l2.mac.BSR_PHR.dequantizePH(phIdx);
            pcmax_dBm_est = sixgr.l2.mac.BSR_PHR.dequantizePCMAX(pcIdx);
        end

        function idx = bufferSizeIndex5bit(bufferBytes)
            % Table 6.1.3.1-1 (5-bit buffer size levels, bytes).
            levels = sixgr.l2.mac.BSR_PHR.table5bitLevels();
            x = double(bufferBytes);
            if ~isfinite(x) || x <= 0
                idx = 0;
                return;
            end
            k = find(x <= levels, 1, 'first');
            if isempty(k)
                idx = 31;
            else
                idx = k-1;
            end
        end

        function bytes = bufferSizeFromIndex5bit(idx)
            levels = sixgr.l2.mac.BSR_PHR.table5bitLevels();
            idx = max(0, min(31, round(double(idx))));
            if idx == 31
                bytes = levels(end);
            else
                bytes = levels(idx+1);
            end
        end

        function idx = bufferSizeIndex8bit(bufferBytes)
            % 8-bit buffer size index (Table 6.1.3.1-2).
            % For simulator coherence we implement a smooth approximation:
            %  - Map bytes to a monotonic index in [0..255] using log scaling.
            % If you need strict conformance, replace this with the exact table.
            x = double(bufferBytes);
            if ~isfinite(x) || x <= 0
                idx = 0;
                return;
            end
            % log-scale mapping roughly spanning [10..~2e6] bytes typical table.
            idx = round(64 * log10(max(x,1)));
            idx = max(0, min(255, idx));
        end

        function bytes = bufferSizeFromIndex8bit(idx)
            % Inverse of bufferSizeIndex8bit approximation.
            idx = max(0, min(255, round(double(idx))));
            bytes = 10^(idx/64);
        end

        function levels = table5bitLevels()
            % Upper bounds (bytes) for indices 0..31 (index 31 is ">150000").
            levels = [ ...
                0, 10, 14, 20, 28, 38, 53, 74, ...
                102, 142, 198, 276, 384, 535, 745, 1038, ...
                1446, 2014, 2806, 3909, 5446, 7587, 10570, 14726, ...
                20516, 28581, 39818, 55474, 77284, 107669, 150000, 150000];
        end

        function phIdx = quantizePH(ph_dB)
            % Common 1 dB quantizer with range [-23..40] -> [0..63]
            x = double(ph_dB);
            if ~isfinite(x), x = -23; end
            phIdx = round(x + 23);
            phIdx = max(0, min(63, phIdx));
        end

        function ph_dB = dequantizePH(phIdx)
            phIdx = max(0, min(63, round(double(phIdx))));
            ph_dB = phIdx - 23;
        end

        function pcIdx = quantizePCMAX(pcmax_dBm)
            % Approx map of PCMAX to 6-bit index. We assume a nominal range
            % [-30..33] dBm mapped to [0..63]. Adjust if you use different
            % PCMAX modeling.
            x = double(pcmax_dBm);
            if ~isfinite(x), x = 23; end
            pcIdx = round(x + 30);
            pcIdx = max(0, min(63, pcIdx));
        end

        function pc_dBm = dequantizePCMAX(pcIdx)
            pcIdx = max(0, min(63, round(double(pcIdx))));
            pc_dBm = pcIdx - 30;
        end
    end
end
