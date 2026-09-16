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
                            validateattributes(val,{'numeric'},{'scalar','real','finite','integer','>=',1,'<=',8});
                            obj.NumLCG = double(val);
                        otherwise
                            error('sixgr:BSR_PHR:BadNV','Unknown option %s.',string(key));
                    end
                end
            end
            obj.LCGBufferBytes = zeros(1, obj.NumLCG);
        end

        function setLCGBuffer(obj, lcgId, bytes)
            validateattributes(lcgId,{'numeric'},{'scalar','real','finite','integer','>=',0,'<',obj.NumLCG});
            validateattributes(bytes,{'numeric'},{'scalar','real','finite','integer','nonnegative','<=',flintmax});
            obj.LCGBufferBytes(lcgId+1) = double(bytes);
        end

        function addLCGBuffer(obj, lcgId, bytesDelta)
            validateattributes(lcgId,{'numeric'},{'scalar','real','finite','integer','>=',0,'<',obj.NumLCG});
            validateattributes(bytesDelta,{'numeric'},{'scalar','real','finite','integer'});
            obj.setLCGBuffer(lcgId, obj.LCGBufferBytes(lcgId+1) + double(bytesDelta));
        end

        function ce = makeBSR(obj, varargin)
            % makeBSR Build a BSR MAC CE struct suitable for TBAssembler.
            %
            % Name-Value:
            %  'Format'    : 'short'|'long'|'auto' (default 'auto')
            %  Truncation requires buildBSR's explicit budget and priorities.
            ip = inputParser;
            ip.addParameter('Format','auto',@(x) ischar(x) || isstring(x));
            ip.addParameter('Truncated',false,@(x) islogical(x) && isscalar(x));
            ip.parse(varargin{:});
            opt = ip.Results;

            fmt = lower(char(string(opt.Format)));
            assert(~opt.Truncated,'sixgr:mac:MissingBSRPaddingContext', ...
                'Use buildBSR with a byte budget and logical-channel priorities for truncation.');

            lcgBytes=sixgr.l2.mac.BSR_PHR.localLCGBufferVector(obj.LCGBufferBytes);
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
                    assert(numel(active)==1,'sixgr:mac:InvalidShortBSRSelection', ...
                        'A full Short BSR cannot silently omit other active LCGs.');
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
        function ce = buildBSR(lcgBufferMap,maxPaddingBytes,priorities)
            % Padding BSR (38.321 5.4.5): budget INCLUDES the MAC subheader.
            % LCP priorities use LCGID+1 indexing (lower number is higher).
            % HighestPriorityWithData and HighestPriorityConfigured differ
            % when the highest-priority logical channel has an empty queue.
            if nargin<3, priorities=struct(); end
            validateattributes(maxPaddingBytes,{'numeric'}, ...
                {'scalar','real','finite','integer','nonnegative'});
            lcgBytes = sixgr.l2.mac.BSR_PHR.localLCGBufferVector(lcgBufferMap);
            active = find(lcgBytes > 0);
            if isempty(active) || maxPaddingBytes<2
                ce = struct([]);
                return;
            end
            selected=active;
            if numel(active) == 1
                fmt = "short";
                lcgId = active(1) - 1;
                payload = sixgr.l2.mac.BSR_PHR.encodeShortBSR(lcgId, lcgBytes(active(1)));
                lcid = 61;
            else
                fmt = "long";
                payload = sixgr.l2.mac.BSR_PHR.encodeLongBSR(lcgBytes);
                lcid = 62;
                fullHeader=sixgr.l2.mac.MACSubheaderCodec.encode('UL',lcid,numel(payload));
                if maxPaddingBytes<numel(fullHeader)+numel(payload)
                    if maxPaddingBytes==2
                        order=sixgr.l2.mac.BSR_PHR.priorityOrder( ...
                            priorities,'HighestPriorityWithData',active);
                        selected=order(1);
                        payload=sixgr.l2.mac.BSR_PHR.encodeShortBSR( ...
                            selected-1,lcgBytes(selected));
                        lcid=59; fmt="short_truncated";
                    else
                        lcid=60; fmt="long_truncated";
                        emptyHeader=sixgr.l2.mac.MACSubheaderCodec.encode('UL',lcid,1);
                        count=maxPaddingBytes-numel(emptyHeader)-1;
                        selected=[]; % A bitmap with zero size fields is legal.
                        if count>0
                            order=sixgr.l2.mac.BSR_PHR.priorityOrder( ...
                                priorities,'HighestPriorityConfigured',active);
                            selected=sort(order(1:count));
                        end
                        payload=sixgr.l2.mac.BSR_PHR.longPayload(lcgBytes,selected);
                    end
                end
            end
            schema=sixgr.l2.mac.MACCESchemaRegistry.resolve('UL',lcid);
            header=sixgr.l2.mac.MACSubheaderCodec.encode('UL',lcid,numel(payload));
            total=numel(header)+numel(payload);
            assert(total<=maxPaddingBytes,'sixgr:mac:MACPDUCapacityExceeded', ...
                'BSR including its subheader exceeds the supplied padding.');
            ce = struct('LCID', lcid, 'Payload', uint8(payload(:)), ...
                'IsFixed',schema.SizeType=="fixed",'Name',char(schema.Name), ...
                'Format',char(fmt),'Truncated',ismember(lcid,[59 60]), ...
                'ActiveLCGCount',double(numel(active)), ...
                'ReportedLCGIDs',reshape(selected-1,1,[]),'MACSubPDUBytes',total);
        end

        function payload = encodeShortBSR(lcgId, bufferBytes)
            % Short BSR MAC CE payload (1 octet):
            %   bits[7:5] LCG ID (3 bits)
            %   bits[4:0] Buffer Size index (5 bits)
            validateattributes(lcgId,{'numeric'},{'scalar','real','finite','integer','>=',0,'<=',7});
            idx = sixgr.l2.mac.BSR_PHR.bufferSizeIndex5bit(bufferBytes);
            b = bitshift(uint8(lcgId),5) + uint8(idx);
            payload = uint8(b);
        end

        function [lcgId,upperInclusive,lowerExclusive,index] = decodeShortBSR(payload)
            % Quantization bounds, not an exact queue-byte measurement.
            b=sixgr.l2.mac.BSR_PHR.octets(payload);
            assert(numel(b)==1,'sixgr:mac:InvalidBSRPayloadLength','Short BSR needs exactly one payload octet.');
            lcgId = double(bitshift(b,-5));
            index = double(bitand(b,uint8(31)));
            [upperInclusive,lowerExclusive]=sixgr.l2.mac.BSR_PHR.bufferSizeFromIndex5bit(index);
        end

        function payload = encodeLongBSR(lcgBytes)
            % Long BSR payload (variable):
            %   Oct1: bitmap LCG7..LCG0 (bit=1 => include buffer size field)
            %   Then: Buffer Size fields (8-bit indices) for each LCGi=1 in ascending i.
            lcgBytes=sixgr.l2.mac.BSR_PHR.localLCGBufferVector(lcgBytes);
            payload=sixgr.l2.mac.BSR_PHR.longPayload(lcgBytes,find(lcgBytes>0));
        end

        function [upperInclusive,lowerExclusive,indices] = decodeLongBSR(payload)
            % Unreported LCGs remain NaN, never silently empty queues.
            report=sixgr.l2.mac.BSR_PHR.decodeBSR(62,payload);
            upperInclusive=report.UpperInclusive;
            lowerExclusive=report.LowerExclusive;
            indices=report.BufferSizeIndices;
        end

        function report=decodeBSR(lcid,payload,priorities)
            if nargin<3, priorities=struct(); end
            validateattributes(lcid,{'numeric'},{'scalar','real','finite','integer','>=',59,'<=',62});
            b=sixgr.l2.mac.BSR_PHR.octets(payload);
            report=struct('LCID',lcid,'BufferSizeIndices',nan(1,8), ...
                'LowerExclusive',nan(1,8),'UpperInclusive',nan(1,8), ...
                'BufferSizeFieldPresent',false(1,8),'LCGBitmap',NaN, ...
                'BitmapMeaning',"not_present");
            if ismember(lcid,[59 61])
                [id,upper,lower,index]=sixgr.l2.mac.BSR_PHR.decodeShortBSR(b);
                selected=id+1; indices=index; tableID="5bit";
            else
                assert(~isempty(b),'sixgr:mac:InvalidBSRPayloadLength','Long BSR needs a bitmap.');
                active=find(bitget(b(1),1:8));
                count=numel(b)-1;
                if lcid==62
                    assert(count==numel(active),'sixgr:mac:InvalidBSRPayloadLength', ...
                        'Long BSR payload length must exactly match its bitmap.');
                    selected=active;
                    report.BitmapMeaning="buffer_size_field_present";
                else
                    assert(count<=numel(active),'sixgr:mac:InvalidBSRPayloadLength', ...
                        'Long Truncated BSR has more fields than active LCGs.');
                    selected=[];
                    if count==numel(active), selected=active;
                    elseif count>0
                        order=sixgr.l2.mac.BSR_PHR.priorityOrder( ...
                            priorities,'HighestPriorityConfigured',active);
                        selected=sort(order(1:count));
                    end
                    report.BitmapMeaning="data_available";
                end
                report.LCGBitmap=double(b(1));
                indices=double(b(2:end)).'; tableID="8bit";
                upper=zeros(size(indices)); lower=upper;
                for k=1:numel(indices)
                    [upper(k),lower(k)]=sixgr.l2.mac.BSR_PHR.indexBounds(indices(k),tableID);
                end
            end
            report.BufferSizeIndices(selected)=indices;
            report.UpperInclusive(selected)=upper;
            report.LowerExclusive(selected)=lower;
            report.BufferSizeFieldPresent(selected)=true;
            report.TableID=tableID;
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
            validateattributes(bufferBytes,{'numeric'},{'scalar','real','finite','integer','nonnegative','<=',flintmax});
            idx=sixgr.l2.mac.BSRTableR18.indexForBytes(bufferBytes,"5bit");
        end

        function [upperInclusive,lowerExclusive] = bufferSizeFromIndex5bit(idx)
            [upperInclusive,lowerExclusive]=sixgr.l2.mac.BSR_PHR.indexBounds(idx,"5bit");
        end

        function idx = bufferSizeIndex8bit(bufferBytes)
            validateattributes(bufferBytes,{'numeric'},{'scalar','real','finite','integer','nonnegative','<=',flintmax});
            idx=sixgr.l2.mac.BSRTableR18.indexForBytes(bufferBytes,"8bit");
        end

        function [upperInclusive,lowerExclusive] = bufferSizeFromIndex8bit(idx)
            [upperInclusive,lowerExclusive]=sixgr.l2.mac.BSR_PHR.indexBounds(idx,"8bit");
        end

        function levels = table5bitLevels()
            levels=sixgr.l2.mac.BSRTableR18.upperBounds("5bit");
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

        function lcgBytes = localLCGBufferVector(lcgBufferMap)
            lcgBytes = zeros(1, 8);
            if isnumeric(lcgBufferMap) && isempty(lcgBufferMap)
                return;
            end
            if isnumeric(lcgBufferMap)
                validateattributes(lcgBufferMap,{'numeric'}, ...
                    {'vector','real','finite','integer','nonnegative','<=',flintmax});
                assert(numel(lcgBufferMap)<=8,'sixgr:mac:InvalidLCGBufferMap','Non-extended BSR supports eight LCGs.');
                vals = double(lcgBufferMap(:).');
                lcgBytes(1:numel(vals)) = vals;
            elseif isa(lcgBufferMap, 'containers.Map')
                keysList = keys(lcgBufferMap);
                for i = 1:numel(keysList)
                    key=keysList{i}; value=lcgBufferMap(key);
                    validateattributes(key,{'numeric'},{'scalar','real','finite','integer','>=',0,'<=',7});
                    validateattributes(value,{'numeric'},{'scalar','real','finite','integer','nonnegative','<=',flintmax});
                    lcgBytes(key+1)=double(value);
                end
            elseif isstruct(lcgBufferMap) && isscalar(lcgBufferMap)
                names = fieldnames(lcgBufferMap);
                for i = 1:numel(names)
                    tok=regexp(names{i},'^LCG([0-7])$','tokens','once');
                    assert(~isempty(tok),'sixgr:mac:InvalidLCGBufferMap','Expected exact LCG0 through LCG7 field names.');
                    value=lcgBufferMap.(names{i});
                    validateattributes(value,{'numeric'},{'scalar','real','finite','integer','nonnegative','<=',flintmax});
                    lcgBytes(str2double(tok{1})+1)=double(value);
                end
            else
                error('sixgr:mac:InvalidLCGBufferMap','Provide a numeric LCG vector, numeric-key map or scalar LCG structure.');
            end
        end
    end

    methods (Static,Access=private)
        function bytes=octets(input)
            assert(isnumeric(input) && isreal(input) && (isvector(input) || isempty(input)) && ...
                all(isfinite(input(:))) && all(input(:)==fix(input(:))) && ...
                all(input(:)>=0 & input(:)<=255), ...
                'sixgr:mac:InvalidBSROctet','BSR payload must contain integer octets before uint8 conversion.');
            bytes=uint8(input(:));
        end

        function [upper,lower]=indexBounds(index,tableID)
            bounds=sixgr.l2.mac.BSRTableR18.upperBounds(tableID);
            validateattributes(index,{'numeric'}, ...
                {'scalar','real','finite','integer','>=',0,'<',numel(bounds)});
            upper=bounds(index+1);
            assert(~isnan(upper),'sixgr:mac:ReservedBSRIndex','Reserved BSR index cannot become a queue estimate.');
            lower=NaN;
            if index>0, lower=bounds(index); end
        end

        function payload=longPayload(buffers,selected)
            bitmap=uint8(0);
            for id=find(buffers>0)
                bitmap=bitor(bitmap,bitshift(uint8(1),id-1));
            end
            indices=arrayfun(@(id)sixgr.l2.mac.BSR_PHR.bufferSizeIndex8bit(buffers(id)),selected);
            payload=[bitmap;uint8(indices(:))];
        end

        function ordered=priorityOrder(priorities,field,active)
            assert(isstruct(priorities) && isscalar(priorities) && isfield(priorities,field), ...
                'sixgr:mac:MissingBSRPriority','Truncated BSR requires LCP-derived %s by LCG.',field);
            values=priorities.(field);
            validateattributes(values,{'numeric'},{'vector','real','numel',8});
            validateattributes(values(active),{'numeric'},{'real','finite','integer','positive'});
            weights=reshape(double(values(active)),[],1);
            [~,order]=sortrows([weights active(:)],[1 2]);
            ordered=reshape(active(order),1,[]);
        end
    end
end
