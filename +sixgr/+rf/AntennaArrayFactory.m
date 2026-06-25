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
                opts.signal (1,1) string = ""
                opts.numPorts (1,1) double = NaN
                opts.numRFChains (1,1) double = NaN
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
            arch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg, roleL, ...
                "NumElements", arr.Nant, ...
                "Signal", opts.signal, ...
                "NumPorts", opts.numPorts, ...
                "NumRFChains", opts.numRFChains);
            arr.NumElements = arch.NumElements;
            arr.NumPorts = arch.NumPorts;
            arr.NumRFChains = arch.NumRFChains;
            arr.PortArchitecture = arch.Architecture;
            arr.PortCountSource = arch.PortCountSource;
            arr.RFChainCountSource = arch.RFChainCountSource;
            arr.PortToElementMatrix = arch.PortToElementMatrix;
            arr.ElementToPortMatrix = arch.ElementToPortMatrix;
            arr.PortToRFChainMatrix = arch.PortToRFChainMatrix;
            arr.RFChainToPortMatrix = arch.RFChainToPortMatrix;
            arr.ElementsPerPort = arch.ElementsPerPort;
            arr.HasPhased = havePhased;
            arr.ArrayObj = arrObj;                 % phased.URA or []
            arr.ElementObj = elemObj;              % phased element or []
        end


        function arch = resolvePortArchitecture(cfg, role, opts)
            arguments
                cfg (1,1) struct
                role (1,1) string
                opts.NumElements (1,1) double = NaN
                opts.Signal (1,1) string = ""
                opts.NumPorts (1,1) double = NaN
                opts.NumRFChains (1,1) double = NaN
                opts.MinimumPorts (1,1) double = 1
            end

            roleL = lower(string(role));
            if roleL == "gnb"
                roleL = "bs";
            end
            if roleL ~= "bs" && roleL ~= "ue"
                error("AntennaArrayFactory:BadRole","role must be 'bs'/'gnb' or 'ue'.");
            end

            numElements = sixgr.rf.AntennaArrayFactory.localPositiveIntegerOrNaN(opts.NumElements);
            if ~isfinite(numElements)
                numElements = sixgr.rf.AntennaArrayFactory.localResolveConfiguredElementCount(cfg, roleL);
            end
            numElements = max(1, round(double(numElements)));

            minimumPorts = sixgr.rf.AntennaArrayFactory.localPositiveIntegerOrNaN(opts.MinimumPorts);
            if ~isfinite(minimumPorts)
                minimumPorts = 1;
            end
            minimumPorts = max(1, round(double(minimumPorts)));

            [numPorts, portSource] = sixgr.rf.AntennaArrayFactory.localResolvePortCount(cfg, roleL, opts.Signal, opts.NumPorts);
            if ~isfinite(numPorts)
                if strlength(strtrim(opts.Signal)) == 0
                    numPorts = numElements;
                    portSource = "generic_runtime_full_element_ports";
                else
                    numPorts = min(max(minimumPorts, 1), numElements);
                    portSource = "default_signal_logical_ports";
                end
            end
            numPorts = max(minimumPorts, round(double(numPorts)));
            if numPorts > numElements
                error("AntennaArrayFactory:PortElementMismatch", ...
                    "%s logical port count %d exceeds %d configured antenna element(s).", ...
                    upper(char(roleL)), numPorts, numElements);
            end

            [numRFChains, rfSource] = sixgr.rf.AntennaArrayFactory.localResolveRFChainCount(cfg, roleL, opts.Signal, opts.NumRFChains);
            if ~isfinite(numRFChains)
                numRFChains = numPorts;
                rfSource = "default_equal_logical_ports";
            end
            numRFChains = max(1, round(double(numRFChains)));
            if numRFChains < numPorts
                error("AntennaArrayFactory:RFChainsLessThanPorts", ...
                    "%s RF chain count %d is smaller than logical port count %d for the current port-domain architecture.", ...
                    upper(char(roleL)), numRFChains, numPorts);
            end

            [portToElement, elementsPerPort] = sixgr.rf.AntennaArrayFactory.localPortToElementMatrix(numElements, numPorts);
            portToRF = sixgr.rf.AntennaArrayFactory.localRectIdentity(numRFChains, numPorts);
            rfToPort = portToRF.';

            arch = struct( ...
                "Role", char(roleL), ...
                "Signal", char(string(opts.Signal)), ...
                "Architecture", "port_domain_logical_ports_with_element_mapping", ...
                "NumElements", double(numElements), ...
                "NumPorts", double(numPorts), ...
                "NumRFChains", double(numRFChains), ...
                "PortCountSource", char(string(portSource)), ...
                "RFChainCountSource", char(string(rfSource)), ...
                "PortToElementMatrix", portToElement, ...
                "ElementToPortMatrix", portToElement', ...
                "PortToRFChainMatrix", portToRF, ...
                "RFChainToPortMatrix", rfToPort, ...
                "ElementsPerPort", double(elementsPerPort(:).'));
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


        function count = localResolveConfiguredElementCount(cfg, roleL)
            if roleL == "bs"
                shape = double(sixgr.util.structGet(cfg, "phy.bsArray", [8 8 1]));
                fallbackPaths = ["antenna.bs.numElements", "scenario.bs.nTxAnt", "mimo.n_tx_ant", "phy.nTxAnt"];
            else
                shape = double(sixgr.util.structGet(cfg, "phy.ueArray", [2 2 1]));
                fallbackPaths = ["antenna.ue.numElements", "scenario.ue.nTxAnt", "scenario.ue.nRxAnt", "mimo.n_rx_ant", "phy.nRxAnt"];
            end
            count = sixgr.rf.AntennaArrayFactory.localProductCount(shape);
            explicit = sixgr.rf.AntennaArrayFactory.localFirstConfiguredCount(cfg, fallbackPaths);
            if isfinite(explicit)
                count = explicit;
            end
            if ~isfinite(count)
                count = 1;
            end
        end

        function [count, source] = localResolvePortCount(cfg, roleL, signal, override)
            count = sixgr.rf.AntennaArrayFactory.localPositiveIntegerOrNaN(override);
            if isfinite(count)
                source = "explicit_build_option";
                return;
            end
            signal = upper(strtrim(string(signal)));
            paths = strings(0, 1);
            if roleL == "bs"
                if signal == "PDSCH" || strlength(signal) == 0
                    paths = [paths; "phy.pdsch.numPorts"; "phy.pdsch.nPorts"; "phy.pdsch.NumAntennaPorts"; "phy.pdsch.numAntennaPorts"];
                end
                if strlength(signal) == 0
                    paths = [paths; "phy.csirs.numPorts"; "phy.trs.numPorts"];
                end
                paths = [paths; "antenna.bs.numPorts"; "rf.bs.numPorts"; "scenario.bs.numPorts"];
            else
                if signal == "PUSCH" || strlength(signal) == 0
                    paths = [paths; "phy.pusch.NumAntennaPorts"; "phy.pusch.numAntennaPorts"; "phy.pusch.numPorts"; "phy.pusch.nPorts"];
                end
                paths = [paths; "antenna.ue.numPorts"; "rf.ue.numPorts"; "scenario.ue.numPorts"];
            end
            [count, source] = sixgr.rf.AntennaArrayFactory.localFirstConfiguredCountWithSource(cfg, paths);
        end

        function [count, source] = localResolveRFChainCount(cfg, roleL, signal, override)
            count = sixgr.rf.AntennaArrayFactory.localPositiveIntegerOrNaN(override);
            if isfinite(count)
                source = "explicit_build_option";
                return;
            end
            signal = lower(strtrim(string(signal)));
            paths = strings(0, 1);
            if roleL == "bs"
                if strlength(signal) > 0
                    paths = [paths; "phy." + signal + ".numRFChains"];
                end
                paths = [paths; "rf.bs.numRFChains"; "antenna.bs.numRFChains"; "scenario.bs.numRFChains"];
            else
                if strlength(signal) > 0
                    paths = [paths; "phy." + signal + ".numRFChains"];
                end
                paths = [paths; "rf.ue.numRFChains"; "antenna.ue.numRFChains"; "scenario.ue.numRFChains"];
            end
            [count, source] = sixgr.rf.AntennaArrayFactory.localFirstConfiguredCountWithSource(cfg, paths);
        end

        function [count, source] = localFirstConfiguredCountWithSource(cfg, paths)
            count = NaN;
            source = "";
            for i = 1:numel(paths)
                path = char(paths(i));
                raw = sixgr.util.structGet(cfg, path, NaN);
                value = sixgr.rf.AntennaArrayFactory.localPositiveIntegerOrNaN(raw);
                if isfinite(value)
                    count = value;
                    source = string(path);
                    return;
                end
            end
        end

        function count = localFirstConfiguredCount(cfg, paths)
            [count, ~] = sixgr.rf.AntennaArrayFactory.localFirstConfiguredCountWithSource(cfg, paths);
        end

        function count = localPositiveIntegerOrNaN(raw)
            count = NaN;
            if isempty(raw) || ~isnumeric(raw)
                return;
            end
            raw = double(raw(1));
            if isfinite(raw) && raw >= 1
                count = max(1, round(raw));
            end
        end

        function count = localProductCount(shape)
            count = NaN;
            if isempty(shape) || ~isnumeric(shape)
                return;
            end
            shape = double(shape(:).');
            shape = shape(isfinite(shape) & shape >= 1);
            if isempty(shape)
                return;
            end
            if numel(shape) >= 3
                shape = shape(1:3);
            end
            count = prod(max(1, round(shape)));
        end

        function [M, elementsPerPort] = localPortToElementMatrix(numElements, numPorts)
            numElements = max(1, round(double(numElements)));
            numPorts = max(1, round(double(numPorts)));
            M = zeros(numElements, numPorts);
            edges = round(linspace(0, numElements, numPorts + 1));
            elementsPerPort = zeros(1, numPorts);
            for p = 1:numPorts
                idx = (edges(p) + 1):edges(p + 1);
                if isempty(idx)
                    idx = min(numElements, p);
                end
                elementsPerPort(p) = numel(idx);
                M(idx, p) = 1 ./ sqrt(max(1, numel(idx)));
            end
        end

        function M = localRectIdentity(nRows, nCols)
            M = zeros(max(1, round(double(nRows))), max(1, round(double(nCols))));
            for ii = 1:min(size(M, 1), size(M, 2))
                M(ii, ii) = 1;
            end
        end
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
