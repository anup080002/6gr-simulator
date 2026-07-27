classdef PDCPSecurity128
    %PDCPSECURITY128 128-NEA2 AES-CTR and 128-NIA2 AES-CMAC.

    methods (Static)
        function output = nea2(key, count, bearer, direction, message, bitLength)
            key = sixgr.l2.pdcp18.PDCPSecurity128.validateInputs( ...
                key, count, bearer, direction, message, bitLength);
            message = uint8(message(:).');
            prefix = [sixgr.l2.pdcp18.PDCPSecurity128.u32be(count), ...
                uint8(bitshift(uint8(bearer), 3) + ...
                bitshift(uint8(direction), 2)), uint8([0 0 0])];
            iv = [prefix, zeros(1, 8, "uint8")];
            cipher = javaMethod("getInstance", "javax.crypto.Cipher", ...
                "AES/CTR/NoPadding");
            keySpec = javaObject("javax.crypto.spec.SecretKeySpec", ...
                typecast(uint8(key(:)), "int8"), "AES");
            ivSpec = javaObject("javax.crypto.spec.IvParameterSpec", ...
                typecast(uint8(iv(:)), "int8"));
            cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, keySpec, ivSpec);
            encrypted = cipher.doFinal(typecast(message(:), "int8"));
            output = reshape(typecast(encrypted, "uint8"), 1, []);
            remainder = mod(bitLength, 8);
            if remainder ~= 0
                mask = bitshift(uint8(255), 8-remainder);
                output(end) = bitand(output(end), mask);
            end
        end

        function macI = nia2(key, count, bearer, direction, message, bitLength)
            key = sixgr.l2.pdcp18.PDCPSecurity128.validateInputs( ...
                key, count, bearer, direction, message, bitLength);
            prefix = [sixgr.l2.pdcp18.PDCPSecurity128.u32be(count), ...
                uint8(bitshift(uint8(bearer), 3) + ...
                bitshift(uint8(direction), 2)), uint8([0 0 0])];
            prefixBits = sixgr.l2.pdcp18.PDCPSecurity128.bytesToBits(prefix);
            messageBits = sixgr.l2.pdcp18.PDCPSecurity128.bytesToBits(message);
            bits = [prefixBits, messageBits(1:bitLength)];
            tag = sixgr.l2.pdcp18.PDCPSecurity128.cmacBits(key, bits);
            macI = tag(1:4);
        end

        function verifyNIA2(key, count, bearer, direction, message, ...
                bitLength, receivedMACI)
            actual = sixgr.l2.pdcp18.PDCPSecurity128.nia2( ...
                key, count, bearer, direction, message, bitLength);
            if ~isequal(uint8(actual(:)), uint8(receivedMACI(:)))
                error("sixgr:pdcp:IntegrityFailure", ...
                    "PDCP NIA2 integrity verification failed.");
            end
        end

        function value = hex(bytes)
            value = upper(string(reshape(dec2hex(uint8(bytes), 2).', 1, [])));
        end
    end

    methods (Static, Access = private)
        function key = validateInputs(key, count, bearer, direction, message, bitLength)
            key = uint8(key(:).');
            message = uint8(message(:).'); %#ok<NASGU>
            if numel(key) ~= 16
                error("sixgr:pdcp:SecurityContextMissing", ...
                    "128-NEA2/NIA2 requires a 128-bit key.");
            end
            if count < 0 || count ~= floor(count) || count > 4294967295 || ...
                    bearer < 0 || bearer ~= floor(bearer) || bearer > 31 || ...
                    ~ismember(direction, [0 1]) || bitLength < 0 || ...
                    bitLength ~= floor(bitLength) || ...
                    bitLength > 8 * numel(message)
                error("sixgr:pdcp:MalformedPDU", ...
                    "Security COUNT/bearer/direction/length is invalid.");
            end
        end

        function tag = cmacBits(key, bits)
            zero = zeros(1, 16, "uint8");
            l = sixgr.l2.pdcp18.PDCPSecurity128.aesBlock(key, zero);
            k1 = sixgr.l2.pdcp18.PDCPSecurity128.subkey(l);
            k2 = sixgr.l2.pdcp18.PDCPSecurity128.subkey(k1);
            n = max(1, ceil(numel(bits) / 128));
            complete = ~isempty(bits) && mod(numel(bits), 128) == 0;
            blocks = zeros(n, 128, "uint8");
            if n > 1
                blocks(1:n-1,:) = reshape(bits(1:(n-1)*128), 128, []).';
            end
            tail = bits((n-1)*128+1:end);
            if complete
                final = bitxor( ...
                    sixgr.l2.pdcp18.PDCPSecurity128.bitsToBytes(tail), k1);
            else
                padded = [tail, uint8(1), ...
                    zeros(1, 127-numel(tail), "uint8")];
                final = bitxor( ...
                    sixgr.l2.pdcp18.PDCPSecurity128.bitsToBytes(padded), k2);
            end
            x = zero;
            for index = 1:n-1
                block = sixgr.l2.pdcp18.PDCPSecurity128.bitsToBytes( ...
                    blocks(index,:));
                x = sixgr.l2.pdcp18.PDCPSecurity128.aesBlock( ...
                    key, bitxor(x, block));
            end
            tag = sixgr.l2.pdcp18.PDCPSecurity128.aesBlock( ...
                key, bitxor(x, final));
        end

        function value = aesBlock(key, block)
            cipher = javaMethod("getInstance", "javax.crypto.Cipher", ...
                "AES/ECB/NoPadding");
            keySpec = javaObject("javax.crypto.spec.SecretKeySpec", ...
                typecast(uint8(key(:)), "int8"), "AES");
            cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, keySpec);
            result = cipher.doFinal(typecast(uint8(block(:)), "int8"));
            value = reshape(typecast(result, "uint8"), 1, []);
        end

        function value = subkey(input)
            carry = bitget(input(1), 8);
            value = zeros(1, 16, "uint8");
            for index = 1:15
                value(index) = bitor(bitshift(input(index), 1), ...
                    bitget(input(index+1), 8));
            end
            value(16) = bitshift(input(16), 1);
            if carry
                value(16) = bitxor(value(16), uint8(135));
            end
        end

        function bits = bytesToBits(bytes)
            bytes = uint8(bytes(:));
            positions = repmat(8:-1:1, numel(bytes), 1);
            expanded = repmat(bytes, 1, 8);
            bits = reshape(bitget(expanded, positions).', 1, []);
            bits = uint8(bits);
        end

        function bytes = bitsToBytes(bits)
            matrix = reshape(uint8(bits), 8, []).';
            bytes = uint8(double(matrix) * double((2.^(7:-1:0)).'));
            bytes = bytes(:).';
        end

        function value = u32be(input)
            input = uint64(input);
            value = uint8([bitand(bitshift(input, -24), 255), ...
                bitand(bitshift(input, -16), 255), ...
                bitand(bitshift(input, -8), 255), ...
                bitand(input, 255)]);
        end
    end
end
