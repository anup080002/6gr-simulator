classdef RLCStatusCodec
    %RLCSTATUSCODEC TS38.322 6.2.2.5 actual ACK/NACK STATUS octets.

    methods (Static)
        function result=encodeReport(snBits,ackSN,nacks)
            % NACK identities/byte intervals must come from received state.
            sixgr.l2.rlc18.RLCStatusCodec.validateReport(snBits,ackSN,nacks);
            bits=zeros(1,24,'uint8');
            bits(5:4+snBits)=sixgr.l2.rlc18.RLCStatusCodec.toBits(ackSN,snBits);
            bits(5+snBits)=~isempty(nacks);
            alignment=4+2*double(snBits==18);
            for k=1:numel(nacks)
                n=nacks(k); so=~isempty(n.SOstart); range=~isempty(n.NACKRange);
                entry=[sixgr.l2.rlc18.RLCStatusCodec.toBits(n.NACKSN,snBits) ...
                    uint8([k<numel(nacks) so range]) zeros(1,alignment-3,'uint8')];
                if so
                    entry=[entry sixgr.l2.rlc18.RLCStatusCodec.toBits(n.SOstart,16) ...
                        sixgr.l2.rlc18.RLCStatusCodec.toBits(n.SOend,16)]; %#ok<AGROW>
                end
                if range,entry=[entry sixgr.l2.rlc18.RLCStatusCodec.toBits(n.NACKRange,8)];end %#ok<AGROW>
                bits=[bits entry]; %#ok<AGROW>
            end
            result=struct('ACKSN',ackSN,'NACKs',nacks,'Bits',bits, ...
                'Bytes',sixgr.l2.rlc18.RLCStatusCodec.pack(bits), ...
                'BitCount',numel(bits),'ByteCount',numel(bits)/8);
        end
        function report=decodeReport(bytes,snBits)
            assert(ismember(snBits,[12 18]),'sixgr:rlc:InvalidSNLength','AM STATUS requires12 or18-bit SN.');
            assert(isnumeric(bytes)&&isreal(bytes)&&all(isfinite(bytes(:)))&& ...
                all(bytes(:)==fix(bytes(:)) & bytes(:)>=0 & bytes(:)<=255), ...
                'sixgr:rlc:StatusEncodingFailed','Require original STATUS octets.');
            bytes=uint8(bytes(:).');
            assert(numel(bytes)>=3,'sixgr:rlc:StatusEncodingFailed','Truncated STATUS header.');
            bits=zeros(1,8*numel(bytes),'uint8');
            for k=1:8,bits(k:8:end)=uint8(bitget(bytes,9-k));end
            assert(~any(bits(1:4)),'sixgr:rlc:StatusEncodingFailed','D/C=0 and CPT=000 required; reserved CPT is discarded.');
            ack=sixgr.l2.rlc18.RLCStatusCodec.fromBits(bits(5:4+snBits));
            more=logical(bits(5+snBits)); cursor=25;
            nacks=repmat(struct('NACKSN',0,'SOstart',[],'SOend',[],'NACKRange',[]),1,0);
            alignment=4+2*double(snBits==18);
            while more
                assert(cursor+snBits+alignment-1<=numel(bits), ...
                    'sixgr:rlc:StatusEncodingFailed','Truncated NACK entry.');
                n=struct('NACKSN',sixgr.l2.rlc18.RLCStatusCodec.fromBits(bits(cursor:cursor+snBits-1)), ...
                    'SOstart',[],'SOend',[],'NACKRange',[]);
                cursor=cursor+snBits; more=logical(bits(cursor));
                so=logical(bits(cursor+1)); range=logical(bits(cursor+2)); cursor=cursor+alignment;
                if so
                    assert(cursor+31<=numel(bits),'sixgr:rlc:StatusEncodingFailed','Truncated NACK byte offsets.');
                    n.SOstart=sixgr.l2.rlc18.RLCStatusCodec.fromBits(bits(cursor:cursor+15));
                    n.SOend=sixgr.l2.rlc18.RLCStatusCodec.fromBits(bits(cursor+16:cursor+31));cursor=cursor+32;
                end
                if range
                    assert(cursor+7<=numel(bits),'sixgr:rlc:StatusEncodingFailed','Truncated NACK range.');
                    n.NACKRange=sixgr.l2.rlc18.RLCStatusCodec.fromBits(bits(cursor:cursor+7));cursor=cursor+8;
                end
                nacks(end+1)=n; %#ok<AGROW>
            end
            assert(cursor==numel(bits)+1,'sixgr:rlc:StatusEncodingFailed','Trailing bytes are not part of this STATUS PDU.');
            sixgr.l2.rlc18.RLCStatusCodec.validateReport(snBits,ack,nacks);
            report=struct('ACKSN',ack,'NACKs',nacks,'Bytes',bytes,'ByteCount',numel(bytes));
        end
        function result = encode(snBits, ackSN, nackCount, segmentNACK, nackRange)
            % Legacy size-vector fixture ONLY. Does not model received loss.
            % Runtime producers must use encodeReport with actual NACKs.
            arguments
                snBits (1,1) double
                ackSN (1,1) double
                nackCount (1,1) double
                segmentNACK (1,1) logical
                nackRange (1,1) logical
            end
            if ~ismember(snBits, [12 18])
                error("sixgr:rlc:InvalidSNLength", ...
                    "AM STATUS SN length must be 12 or 18 bits.");
            end
            if ackSN < 0 || ackSN ~= floor(ackSN) || ackSN >= 2^snBits || ...
                    nackCount < 0 || nackCount ~= floor(nackCount)
                error("sixgr:rlc:StatusEncodingFailed", ...
                    "ACK_SN/NACK count is outside the bounded STATUS profile.");
            end
            baseBits = 24;
            if snBits == 12
                entryControlBits = 4;
            else
                entryControlBits = 6;
            end
            nackBits = snBits + entryControlBits;
            if segmentNACK
                nackBits = nackBits + 32;
            end
            if nackRange
                nackBits = nackBits + 8;
            end
            bitCount = baseBits + nackCount * nackBits;
            bits = zeros(1, bitCount, "uint8");
            % D/C=0, CPT=000. ACK_SN begins after those four bits.
            bits(5:4+snBits) = sixgr.l2.rlc18.RLCStatusCodec.toBits( ...
                ackSN, snBits);
            if nackCount > 0
                bits(5+snBits) = 1;
            end
            cursor = baseBits + 1;
            for index = 1:nackCount
                nackSN = mod(ackSN + index, 2^snBits);
                bits(cursor:cursor+snBits-1) = ...
                    sixgr.l2.rlc18.RLCStatusCodec.toBits(nackSN, snBits);
                cursor = cursor + snBits;
                bits(cursor) = double(index < nackCount);
                bits(cursor+1) = uint8(segmentNACK);
                bits(cursor+2) = uint8(nackRange);
                % Advance over E1/E2/E3 and the reserved alignment bits.
                cursor = cursor + entryControlBits;
                if segmentNACK
                    bits(cursor:cursor+15) = ...
                        sixgr.l2.rlc18.RLCStatusCodec.toBits(0, 16);
                    bits(cursor+16:cursor+31) = ...
                        sixgr.l2.rlc18.RLCStatusCodec.toBits(65535, 16);
                    cursor = cursor + 32;
                end
                if nackRange
                    bits(cursor:cursor+7) = ...
                        sixgr.l2.rlc18.RLCStatusCodec.toBits(1, 8);
                    cursor = cursor + 8;
                end
            end
            result = struct("Bits", bits, ...
                "Bytes", sixgr.l2.rlc18.RLCStatusCodec.pack(bits), ...
                "BitCount", bitCount, "ByteCount", bitCount / 8);
        end
    end

    methods (Static, Access = private)
        function validateReport(snBits,ack,nacks)
            assert(ismember(snBits,[12 18]) && isscalar(ack) && isfinite(ack) && ...
                ack==fix(ack) && ack>=0 && ack<2^snBits && isstruct(nacks), ...
                'sixgr:rlc:StatusEncodingFailed','Invalid ACK/SN configuration.');
            priorStart=-inf;
            for k=1:numel(nacks)
                n=nacks(k);
                assert(all(isfield(n,{'NACKSN','SOstart','SOend','NACKRange'})), ...
                    'sixgr:rlc:StatusEncodingFailed','NACK requires explicit original identity and optional interval/range.');
                v=n.NACKSN;
                assert(isscalar(v)&&isfinite(v)&&v==fix(v)&&v>=0&&v<2^snBits, ...
                    'sixgr:rlc:StatusEncodingFailed','Invalid NACK_SN.');
                behind=mod(ack-v,2^snBits);
                assert(behind>0&&behind<=2^(snBits-1),'sixgr:rlc:StatusEncodingFailed','NACK must precede ACK within receiving window.');
                start=-behind;
                assert(start>=priorStart,'sixgr:rlc:StatusEncodingFailed','NACK list is not ordered.');priorStart=start;
                assert(isempty(n.SOstart)==isempty(n.SOend),'sixgr:rlc:StatusEncodingFailed','Both segment offsets are required.');
                range=1;
                if ~isempty(n.NACKRange)
                    range=n.NACKRange;
                    assert(isscalar(range)&&isfinite(range)&&range==fix(range)&&range>=1&&range<=255, ...
                        'sixgr:rlc:StatusEncodingFailed','NACK range must be1..255.');
                end
                assert(range<=behind,'sixgr:rlc:StatusEncodingFailed','NACK range crosses ACK_SN.');
                if ~isempty(n.SOstart)
                    so=[n.SOstart n.SOend];
                    assert(numel(so)==2&&all(isfinite(so)&so==fix(so)&so>=0&so<=65535) && ...
                        (range>1 || n.SOstart<=n.SOend), ...
                        'sixgr:rlc:StatusEncodingFailed','Invalid original missing-byte interval.');
                end
            end
        end
        function v=fromBits(bits)
            v=sum(double(bits).*2.^((numel(bits)-1):-1:0));
        end
        function bits = toBits(value, n)
            bits = uint8(bitget(uint64(value), n:-1:1));
        end

        function bytes = pack(bits)
            bits = reshape(uint8(bits), 8, []).';
            weights = uint16(2 .^ (7:-1:0));
            bytes = uint8(double(bits) * double(weights(:)));
            bytes = bytes(:).';
        end
    end
end
