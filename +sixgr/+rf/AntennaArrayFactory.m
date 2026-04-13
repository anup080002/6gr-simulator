classdef AntennaArrayFactory
%ANTENNAARRAYFACTORY Build BS/UE antenna arrays using Phased Array Toolbox when available.
%
% This factory centralizes antenna/array construction so that Link/System/Hybrid
% simulation components reuse the same array definitions.
%
% Primary dependency (optional): Phased Array System Toolbox (phased.URA, etc.).
% If PHASED is not available, this factory returns numeric element positions only.
%
% Example:
%   cfg = sixgr.config.defaultConfig();
%   bsArr = sixgr.rf.AntennaArrayFactory.build(cfg,"bs");
%   ueArr = sixgr.rf.AntennaArrayFactory.build(cfg,"ue");
%
% Note: Keep ASCII only (avoid smart quotes / en-dash) to prevent "Invalid text character" errors.

    methods(Static)

        function arr = build(cfg, role, opts)
            arguments
                cfg (1,1) struct
                role (1,1) string
                opts.fc_Hz (1,1) double = NaN
                opts.arrayType (1,1) string = "URA"
                opts.elementSpacingLambda (1,2) double = [0.5 0.5]
                opts.usePhased (1,1) logical = true
            end

            roleL = lower(string(role));
            if roleL == "gnb"
                roleL = "bs";
            end
            if roleL ~= "bs" && roleL ~= "ue"
                error("AntennaArrayFactory:BadRole","role must be 'bs'/'gnb' or 'ue'.");
            end

            % Carrier frequency
            fc = opts.fc_Hz;
            if isnan(fc) || fc <= 0
                fc = sixgr.util.structGet(cfg, "channel.fc_Hz", NaN);
                if isnan(fc) || fc <= 0
                    fc = sixgr.util.structGet(cfg, "phy.fc_Hz", 4e9);
                end
            end

            c = physconst("LightSpeed");
            lambda = c / fc;

            % Array size from config
            if roleL == "bs"
                a = sixgr.util.structGet(cfg, "phy.bsArray", [8 8 1]);
            else
                a = sixgr.util.structGet(cfg, "phy.ueArray", [2 2 1]);
            end
            a = double(a(:).');
            if numel(a) < 2
                a = [a(1) 1];
            end
            if numel(a) < 3
                a(3) = 1;
            end
            nRow = max(1, round(a(1)));
            nCol = max(1, round(a(2)));
            nPol = max(1, round(a(3)));

            % Element spacing (meters)
            d = lambda .* opts.elementSpacingLambda(:).';
            if any(d <= 0)
                d = lambda .* [0.5 0.5];
            end

            % Compute numeric element positions (for codegen friendliness and plotting).
            % Call the private static helper as a plain method name to avoid
            % package/name-resolution issues on some MATLAB installations.
            % IMPORTANT:
            % In MATLAB, when calling a static helper from another static method,
            % use the fully-qualified class name to avoid package/function
            % resolution issues ("Unrecognized function or variable" at runtime).
            pos = sixgr.rf.AntennaArrayFactory.localURAElementPositions(nRow, nCol, d);

            % Build phased array object if available
            havePhased = (exist("phased.URA","class") == 8) && opts.usePhased;
            arrObj = [];
            elemObj = [];
            if havePhased
                try
                    elemObj = phased.IsotropicAntennaElement("FrequencyRange",[max(1,fc/10) 10*fc]);
                    if nRow >= 2 && nCol >= 2
                        arrObj = phased.URA("Size",[nRow nCol], "ElementSpacing", d, "Element", elemObj);
                    elseif nRow == 1 && nCol == 1
                        arrObj = phased.ULA("NumElements", 1, "ElementSpacing", d(1), "Element", elemObj);
                    elseif nRow == 1
                        arrObj = phased.ULA("NumElements", nCol, "ElementSpacing", d(2), "Element", elemObj);
                    else
                        arrObj = phased.ULA("NumElements", nRow, "ElementSpacing", d(1), "Element", elemObj);
                    end
                catch ME
                    % Fall back to numeric-only representation
                    havePhased = false;
                    arrObj = [];
                    elemObj = [];
                    warning("AntennaArrayFactory:PhasedFailed","PHASED array build failed: %s", ME.message);
                end
            end

            % Expand positions for polarization as a simple replication.
            % True dual-pol modeling will be handled in later RF modules.
            if nPol > 1
                pos = repmat(pos, nPol, 1);
            end

            arr = struct();
            arr.Role = char(roleL);
            arr.Type = char(opts.arrayType);
            arr.Fc_Hz = fc;
            arr.Lambda_m = lambda;
            arr.Size = [nRow nCol];
            arr.NPol = nPol;
            arr.ElementSpacing_m = d;
            arr.ElementPositions_m = pos;           % [Nant x 3]
            arr.Nant = size(pos,1);
            arr.HasPhased = havePhased;
            arr.ArrayObj = arrObj;                 % phased.URA or []
            arr.ElementObj = elemObj;              % phased element or []
        end

        function cb = dftCodebookURA(nRow, nCol, nBeamsRow, nBeamsCol)
            %DFTCODEBOOKURA Simple DFT beam codebook for a URA.
            %
            % Returns cb: [Nant x Nbeams] complex weights, unit-norm columns.

            arguments
                nRow (1,1) double {mustBeInteger,mustBePositive}
                nCol (1,1) double {mustBeInteger,mustBePositive}
                nBeamsRow (1,1) double {mustBeInteger,mustBePositive} = nRow
                nBeamsCol (1,1) double {mustBeInteger,mustBePositive} = nCol
            end

            % Call helpers directly for robustness.
            % Fully-qualified helper call (static method lookup inside package)
            wr = sixgr.rf.AntennaArrayFactory.localDFT(nRow, nBeamsRow); % [nRow x nBeamsRow]
            wc = sixgr.rf.AntennaArrayFactory.localDFT(nCol, nBeamsCol); % [nCol x nBeamsCol]

            nBeams = nBeamsRow * nBeamsCol;
            cb = complex(zeros(nRow*nCol, nBeams));

            b = 1;
            for ir = 1:nBeamsRow
                for ic = 1:nBeamsCol
                    w = kron(wc(:,ic), wr(:,ir));
                    cb(:,b) = w ./ norm(w);
                    b = b + 1;
                end
            end
        end

    end

    methods(Static, Access=private)

        function pos = localURAElementPositions(nRow, nCol, d)
            % localURAElementPositions URA positions centered at origin.
            dy = d(1);
            dz = d(2);

            y = ((0:nRow-1) - (nRow-1)/2) * dy;
            z = ((0:nCol-1) - (nCol-1)/2) * dz;

            [Y,Z] = ndgrid(y, z);
            X = zeros(size(Y));

            pos = [X(:) Y(:) Z(:)];
        end

        function W = localDFT(N, K)
            % localDFT K columns of an NxK DFT matrix (unit-norm columns)
            n = (0:N-1).';
            k = 0:K-1;
            W = exp(-1j*2*pi*(n*k)/K) ./ sqrt(N);
        end

    end
end
