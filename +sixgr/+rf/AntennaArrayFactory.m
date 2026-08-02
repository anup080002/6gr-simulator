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
            [panelRows, panelCols, panelSource] = sixgr.rf.AntennaArrayFactory.localResolvePanelShape(cfg, roleL, a);

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

            [pos, polIndex, panelIndex] = sixgr.rf.AntennaArrayFactory.localExpandPositionsForPolarizationAndPanels( ...
                pos, nRow, nCol, nPol, panelRows, panelCols, d);
            polModel = sixgr.rf.AntennaArrayFactory.localResolvePolarizationModel(cfg, roleL, nPol);
            polAngles = sixgr.rf.AntennaArrayFactory.localResolvePolarizationAngles(cfg, roleL, nPol);
            xprDb = sixgr.rf.AntennaArrayFactory.localResolveXPRdB(cfg, roleL);

            arr = struct();
            arr.Role = char(roleL);
            arr.Type = char(opts.arrayType);
            arr.Fc_Hz = fc;
            arr.Lambda_m = lambda;
            arr.Size = [nRow nCol];
            arr.ArraySize5D = [nRow nCol nPol panelRows panelCols];
            arr.NPol = nPol;
            arr.PanelRows = panelRows;
            arr.PanelCols = panelCols;
            arr.PanelCount = panelRows * panelCols;
            arr.PanelShapeSource = char(string(panelSource));
            arr.ElementSpacing_m = d;
            arr.ElementPositions_m = pos;           % [Nant x 3]
            arr.PolarizationModel = char(polModel);
            arr.PolarizationAngles_deg = double(polAngles(:).');
            arr.CrossPolarizationPowerRatio_dB = double(xprDb);
            arr.PolarizationIndexByElement = double(polIndex(:).');
            arr.PanelIndexByElement = double(panelIndex(:).');
            arr.Nant = size(pos,1);
            arch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg, roleL, ...
                "NumElements", arr.Nant, ...
                "Signal", opts.signal, ...
                "NumPorts", opts.numPorts, ...
                "NumRFChains", opts.numRFChains);
            arr.NumElements = arch.NumElements;
            arr.NumPorts = arch.NumPorts;
            arr.NumLogicalPorts = arch.NumLogicalPorts;
            arr.NumWaveformColumns = arch.NumWaveformColumns;
            arr.NumRFChains = arch.NumRFChains;
            arr.PortArchitecture = arch.Architecture;
            arr.WaveformDomain = arch.WaveformDomain;
            arr.PortCountSource = arch.PortCountSource;
            arr.RFChainCountSource = arch.RFChainCountSource;
            arr.PortToElementMatrix = arch.PortToElementMatrix;
            arr.ElementToPortMatrix = arch.ElementToPortMatrix;
            arr.PortToRFChainMatrix = arch.PortToRFChainMatrix;
            arr.RFChainToPortMatrix = arch.RFChainToPortMatrix;
            arr.AnalogPrecoderMatrix = arch.AnalogPrecoderMatrix;
            arr.DigitalPortToRFChainMatrix = arch.DigitalPortToRFChainMatrix;
            arr.HybridElementToPortMatrix = arch.HybridElementToPortMatrix;
            arr.HybridBeamformingEnabled = arch.HybridBeamformingEnabled;
            arr.HybridPowerNormalization = arch.HybridPowerNormalization;
            arr.ElementsPerPort = arch.ElementsPerPort;
            arr.HasPhased = havePhased;
            arr.ArrayObj = arrObj;                 % phased.URA or []
            arr.ElementObj = elemObj;              % phased element or []
        end


        function [arr, meta] = logicalPortView(arr, meta, numPorts, sourceToken)
            %LOGICALPORTVIEW Return a signal-specific logical-port view.
            % The element geometry is preserved, while the baseband waveform
            % contract is specialized to the signal's actual port columns.
            if nargin < 2 || ~isstruct(meta)
                meta = struct();
            end
            if nargin < 3 || ~(isnumeric(numPorts) && isscalar(numPorts) && isfinite(numPorts) && numPorts >= 1)
                error("AntennaArrayFactory:InvalidLogicalPortView", ...
                    "A finite positive logical-port count is required.");
            end
            if nargin < 4 || strlength(strtrim(string(sourceToken))) == 0
                sourceToken = "signal_specific_logical_port_view";
            end

            numPorts = max(1, round(double(numPorts)));
            numElements = sixgr.rf.AntennaArrayFactory.localPositiveIntegerOrNaN( ...
                sixgr.util.structGet(arr, "NumElements", NaN));
            if ~isfinite(numElements)
                numElements = sixgr.rf.AntennaArrayFactory.localPositiveIntegerOrNaN( ...
                    sixgr.util.structGet(arr, "Nant", NaN));
            end
            if ~isfinite(numElements)
                numElements = sixgr.rf.AntennaArrayFactory.localPositiveIntegerOrNaN( ...
                    sixgr.util.structGet(meta, "NumElements", NaN));
            end
            if ~isfinite(numElements)
                numElements = numPorts;
            end
            numElements = max(1, round(double(numElements)));
            if numPorts > numElements
                error("AntennaArrayFactory:PortElementMismatch", ...
                    "Signal logical-port count %d exceeds %d runtime antenna element(s).", ...
                    numPorts, numElements);
            end

            numRFChains = sixgr.rf.AntennaArrayFactory.localPositiveIntegerOrNaN( ...
                sixgr.util.structGet(arr, "NumRFChains", NaN));
            if ~isfinite(numRFChains)
                numRFChains = sixgr.rf.AntennaArrayFactory.localPositiveIntegerOrNaN( ...
                    sixgr.util.structGet(meta, "NumRFChains", NaN));
            end
            if ~isfinite(numRFChains) || numRFChains < numPorts
                numRFChains = numPorts;
            end

            [portToElement, elementsPerPort] = sixgr.rf.AntennaArrayFactory.localPortToElementMatrix(numElements, numPorts);
            portToRF = sixgr.rf.AntennaArrayFactory.localRectIdentity(numRFChains, numPorts);

            arr.NumElements = double(numElements);
            arr.Nant = double(sixgr.util.structGet(arr, "Nant", numElements));
            arr.NumPorts = double(numPorts);
            arr.NumLogicalPorts = double(numPorts);
            arr.NumWaveformColumns = double(numPorts);
            arr.NumRFChains = double(numRFChains);
            arr.WaveformDomain = "logical_port";
            arr.PortArchitecture = "signal_specific_logical_port_view";
            arr.PortCountSource = char(string(sourceToken));
            arr.RFChainCountSource = "signal_specific_logical_port_view";
            arr.PortToElementMatrix = portToElement;
            arr.ElementToPortMatrix = portToElement';
            arr.PortToRFChainMatrix = portToRF;
            arr.RFChainToPortMatrix = portToRF.';
            arr.DigitalPortToRFChainMatrix = portToRF;
            arr.HybridElementToPortMatrix = portToElement;
            arr.HybridBeamformingEnabled = false;
            arr.ElementsPerPort = double(elementsPerPort(:).');

            meta.NumElements = double(numElements);
            meta.NumPorts = double(numPorts);
            meta.NumLogicalPorts = double(numPorts);
            meta.NumWaveformColumns = double(numPorts);
            meta.NumRFChains = double(numRFChains);
            meta.WaveformDomain = "logical_port";
            meta.PortCountSource = char(string(sourceToken));
            meta.RuntimeObjectSource = "AntennaArrayFactory.logicalPortView";
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
                opts.MatrixAuthorityScope (1,1) string = "signal_then_role"
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
            hybridEnabled = sixgr.rf.AntennaArrayFactory.localResolveHybridBeamformingEnabled(cfg, roleL, opts.Signal);
            if numRFChains < numPorts
                error("AntennaArrayFactory:RFChainsLessThanPorts", ...
                    "%s RF chain count %d is smaller than logical port count %d. The implemented hybrid path still requires one RF chain per logical baseband port.", ...
                    upper(char(roleL)), numRFChains, numPorts);
            end

            [analogPrecoder, rfElementsPerChain] = sixgr.rf.AntennaArrayFactory.localPortToElementMatrix(numElements, numRFChains);
            digitalPortToRF = sixgr.rf.AntennaArrayFactory.localRectIdentity(numRFChains, numPorts);
            portToElement = analogPrecoder * digitalPortToRF;
            configuredElementToPort = [];
            configuredElementToPortSource = "";
            signalL = lower(strtrim(string(opts.Signal)));
            matrixAuthorityScope = lower(strtrim(string(opts.MatrixAuthorityScope)));
            if ~ismember(matrixAuthorityScope, ["signal_then_role", "role_only"])
                error("AntennaArrayFactory:InvalidMatrixAuthorityScope", ...
                    "MatrixAuthorityScope must be signal_then_role or role_only.");
            end
            configuredMatrixPaths = strings(0, 1);
            if matrixAuthorityScope == "signal_then_role" && strlength(signalL) > 0
                configuredMatrixPaths = [configuredMatrixPaths; ...
                    "phy." + signalL + ".hybridElementToPortMatrix"];
            end
            configuredMatrixPaths = [configuredMatrixPaths; ...
                "rf." + roleL + ".hybridElementToPortMatrix"; ...
                "antenna." + roleL + ".hybridElementToPortMatrix"];
            for matrixPath = configuredMatrixPaths.'
                candidate = sixgr.util.structGet(cfg, matrixPath, []);
                if ~isempty(candidate)
                    configuredElementToPort = double(candidate);
                    configuredElementToPortSource = string(matrixPath);
                    break;
                end
            end
            if ~isempty(configuredElementToPort)
                if ~hybridEnabled
                    error("AntennaArrayFactory:ConfiguredHybridMatrixWithoutHybridMode", ...
                        "Configured %s requires hybrid beamforming to be enabled.", ...
                        char(configuredElementToPortSource));
                end
                if ~ismatrix(configuredElementToPort) || ...
                        ~isequal(size(configuredElementToPort), [numElements numPorts]) || ...
                        any(~isfinite(real(configuredElementToPort(:)))) || ...
                        any(~isfinite(imag(configuredElementToPort(:))))
                    error("AntennaArrayFactory:ConfiguredHybridMatrixShapeMismatch", ...
                        "Configured %s must be a finite %dx%d element-by-logical-port matrix.", ...
                        char(configuredElementToPortSource), numElements, numPorts);
                end
                if any(sum(abs(configuredElementToPort).^2, 1) <= eps)
                    error("AntennaArrayFactory:ConfiguredHybridMatrixZeroColumn", ...
                        "Configured %s contains an all-zero logical-port column.", ...
                        char(configuredElementToPortSource));
                end
                % This path carries the already selected combined RF/baseband
                % beam. More RF chains than logical ports is a valid hybrid
                % architecture. Split each logical beam deterministically over
                % its RF chains while preserving the combined matrix exactly.
                [analogPrecoder, digitalPortToRF] = ...
                    sixgr.rf.AntennaArrayFactory.localFactorCombinedHybridMatrix( ...
                    configuredElementToPort, numRFChains);
                factorResidual = norm(analogPrecoder * digitalPortToRF - ...
                    configuredElementToPort, "fro");
                factorTolerance = 1e-12 * max(1, norm(configuredElementToPort, "fro"));
                if ~(isfinite(factorResidual) && factorResidual <= factorTolerance)
                    error("AntennaArrayFactory:ConfiguredHybridMatrixFactorizationMismatch", ...
                        "Exact hybrid factorization residual %.17g exceeds tolerance %.17g for %d RF chains and %d logical ports.", ...
                        factorResidual, factorTolerance, numRFChains, numPorts);
                end
                % Keep the submitted combined matrix bit-for-bit so selected
                % and applied SHA-256 identities remain stable across replay.
                portToElement = configuredElementToPort;
                rfElementsPerChain = sum(abs(analogPrecoder) > 0, 1);
                rfSource = "configured_combined_matrix:" + configuredElementToPortSource;
            end
            [~, elementsPerPort] = sixgr.rf.AntennaArrayFactory.localPortToElementMatrix(numElements, numPorts);
            portToRF = digitalPortToRF;
            rfToPort = portToRF.';
            waveformColumns = numPorts;
            waveformDomain = "logical_port";
            architecture = "port_domain_logical_ports_with_element_mapping";
            if hybridEnabled
                waveformColumns = numElements;
                waveformDomain = "element";
                architecture = "hybrid_rf_bb_element_domain_precoding";
            end

            arch = struct( ...
                "Role", char(roleL), ...
                "Signal", char(string(opts.Signal)), ...
                "Architecture", char(architecture), ...
                "NumElements", double(numElements), ...
                "NumPorts", double(numPorts), ...
                "NumLogicalPorts", double(numPorts), ...
                "NumWaveformColumns", double(waveformColumns), ...
                "NumRFChains", double(numRFChains), ...
                "WaveformDomain", char(waveformDomain), ...
                "PortCountSource", char(string(portSource)), ...
                "RFChainCountSource", char(string(rfSource)), ...
                "PortToElementMatrix", portToElement, ...
                "ElementToPortMatrix", portToElement', ...
                "PortToRFChainMatrix", portToRF, ...
                "RFChainToPortMatrix", rfToPort, ...
                "AnalogPrecoderMatrix", analogPrecoder, ...
                "DigitalPortToRFChainMatrix", digitalPortToRF, ...
                "HybridElementToPortMatrix", portToElement, ...
                "HybridBeamformingEnabled", logical(hybridEnabled), ...
                "HybridPowerNormalization", "unit_norm_rf_chain_columns_trace_preserved_after_baseband_precoding", ...
                "HybridElementToPortMatrixSource", char(configuredElementToPortSource), ...
                "MatrixAuthorityScope", char(matrixAuthorityScope), ...
                "RFElementsPerChain", double(rfElementsPerChain(:).'), ...
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
            [panelRows, panelCols] = sixgr.rf.AntennaArrayFactory.localResolvePanelShape(cfg, roleL, shape);
            count = sixgr.rf.AntennaArrayFactory.localProductCount(shape) * panelRows * panelCols;
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
                if signal == "PDSCH"
                    paths = [paths; "phy.pdsch.numPorts"; "phy.pdsch.nPorts"; "phy.pdsch.NumAntennaPorts"; "phy.pdsch.numAntennaPorts"];
                end
                if strlength(signal) == 0
                    paths = [paths; "phy.csirs.numPorts"; "phy.trs.numPorts"];
                end
                if strlength(signal) == 0
                    paths = [paths; "scenario.bs.nTxAnt"; "mimo.n_tx_ant"; "phy.nTxAnt"];
                end
                paths = [paths; "antenna.bs.numPorts"; "rf.bs.numPorts"; "scenario.bs.numPorts"];
            else
                if signal == "PUSCH"
                    paths = [paths; "phy.pusch.NumAntennaPorts"; "phy.pusch.numAntennaPorts"; "phy.pusch.numPorts"; "phy.pusch.nPorts"];
                end
                if strlength(signal) == 0
                    paths = [paths; "scenario.ue.nRxAnt"; "mimo.n_rx_ant"; "phy.nRxAnt"];
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

        function enabled = localResolveHybridBeamformingEnabled(cfg, roleL, signal)
            signal = lower(strtrim(string(signal)));
            paths = strings(0, 1);
            if strlength(signal) > 0
                paths = [paths; "phy." + signal + ".hybridBeamformingEnabled"; ...
                    "phy." + signal + ".hybridBeamforming"];
            end
            paths = [paths; ...
                "rf." + roleL + ".hybridBeamformingEnabled"; ...
                "rf." + roleL + ".hybridBeamforming"; ...
                "antenna." + roleL + ".hybridBeamformingEnabled"; ...
                "antenna." + roleL + ".hybridBeamforming"; ...
                "phy.beamManagement.hybridBeamformingEnabled"; ...
                "mimo.hybrid_beamforming_flag"; ...
                "mimo.hybridBeamformingEnabled"];
            enabled = false;
            for i = 1:numel(paths)
                [tf, ok] = sixgr.rf.AntennaArrayFactory.localParseLogical(sixgr.util.structGet(cfg, paths(i), []));
                if ok
                    enabled = tf;
                    return;
                end
            end
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

        function [panelRows, panelCols, source] = localResolvePanelShape(cfg, roleL, shape)
            panelRows = NaN;
            panelCols = NaN;
            source = "";
            shape = double(shape(:).');
            if numel(shape) >= 5 && all(isfinite(shape(4:5))) && all(shape(4:5) >= 1)
                panelRows = max(1, round(shape(4)));
                panelCols = max(1, round(shape(5)));
                source = "phy_array_shape_5d";
            elseif numel(shape) >= 4 && isfinite(shape(4)) && shape(4) >= 1
                panelRows = max(1, round(shape(4)));
                panelCols = 1;
                source = "phy_array_shape_4d_panel_count";
            end
            if ~(isfinite(panelRows) && isfinite(panelCols))
                rowPaths = ["antenna." + roleL + ".panelRows", "rf." + roleL + ".panelRows", "scenario." + roleL + ".panelRows"];
                colPaths = ["antenna." + roleL + ".panelCols", "rf." + roleL + ".panelCols", "scenario." + roleL + ".panelCols"];
                panelRows = sixgr.rf.AntennaArrayFactory.localFirstConfiguredCount(cfg, rowPaths);
                panelCols = sixgr.rf.AntennaArrayFactory.localFirstConfiguredCount(cfg, colPaths);
                if isfinite(panelRows) || isfinite(panelCols)
                    if ~isfinite(panelRows), panelRows = 1; end
                    if ~isfinite(panelCols), panelCols = 1; end
                    source = "configured_panel_rows_cols";
                end
            end
            if ~(isfinite(panelRows) && isfinite(panelCols))
                countPaths = ["antenna." + roleL + ".panelCount", "rf." + roleL + ".panelCount", ...
                    "scenario." + roleL + ".panelCount", "phy.beamManagement.panelCount", "mimo.panel_count"];
                panelCount = sixgr.rf.AntennaArrayFactory.localFirstConfiguredCount(cfg, countPaths);
                if isfinite(panelCount)
                    panelRows = panelCount;
                    panelCols = 1;
                    source = "configured_panel_count";
                end
            end
            if ~(isfinite(panelRows) && panelRows >= 1), panelRows = 1; end
            if ~(isfinite(panelCols) && panelCols >= 1), panelCols = 1; end
            panelRows = max(1, round(panelRows));
            panelCols = max(1, round(panelCols));
            if strlength(string(source)) == 0
                source = "default_single_panel";
            end
        end

        function model = localResolvePolarizationModel(cfg, roleL, nPol)
            paths = ["antenna." + roleL + ".polarization", "rf." + roleL + ".polarization", ...
                "antenna_and_array.polarization", "mimo.polarization"];
            model = "";
            for i = 1:numel(paths)
                raw = string(sixgr.util.structGet(cfg, paths(i), ""));
                if strlength(strtrim(raw)) > 0
                    model = lower(strtrim(raw));
                    return;
                end
            end
            if nPol >= 2
                model = "cross_pol";
            else
                model = "single";
            end
        end

        function angles = localResolvePolarizationAngles(cfg, roleL, nPol)
            paths = ["antenna." + roleL + ".polarizationAngles_deg", "rf." + roleL + ".polarizationAngles_deg", ...
                "antenna_and_array.polarizationAngles_deg"];
            angles = [];
            for i = 1:numel(paths)
                raw = sixgr.util.structGet(cfg, paths(i), []);
                if isnumeric(raw) && ~isempty(raw)
                    angles = double(raw(:).');
                    break;
                end
            end
            if isempty(angles)
                if nPol >= 2
                    angles = [45 -45];
                else
                    angles = 0;
                end
            end
            if numel(angles) < nPol
                angles = repmat(angles(1), 1, nPol);
                if nPol == 2 && numel(angles) >= 2
                    angles = [angles(1) -angles(1)];
                end
            end
            angles = angles(1:nPol);
        end

        function xprDb = localResolveXPRdB(cfg, roleL)
            paths = ["antenna." + roleL + ".xpr_dB", "rf." + roleL + ".xpr_dB", ...
                "channel.xpr_dB", "antenna_and_array.xpr_dB"];
            xprDb = NaN;
            for i = 1:numel(paths)
                raw = sixgr.util.structGet(cfg, paths(i), NaN);
                if isnumeric(raw) && isscalar(raw) && isfinite(double(raw))
                    xprDb = double(raw);
                    return;
                end
            end
        end

        function [posOut, polIndex, panelIndex] = localExpandPositionsForPolarizationAndPanels(pos, nRow, nCol, nPol, panelRows, panelCols, d)
            base = double(pos);
            nBase = size(base, 1);
            nPol = max(1, round(double(nPol)));
            panelRows = max(1, round(double(panelRows)));
            panelCols = max(1, round(double(panelCols)));
            posOut = zeros(nBase * nPol * panelRows * panelCols, 3);
            polIndex = zeros(size(posOut, 1), 1);
            panelIndex = zeros(size(posOut, 1), 1);
            rowAperture = max(1, nRow) * d(1);
            colAperture = max(1, nCol) * d(2);
            writeIdx = 1;
            for pr = 1:panelRows
                for pc = 1:panelCols
                    pIdx = (pr - 1) * panelCols + pc;
                    panelOffset = [0, (pr - (panelRows + 1) / 2) * rowAperture, ...
                        (pc - (panelCols + 1) / 2) * colAperture];
                    for pp = 1:nPol
                        rows = writeIdx:(writeIdx + nBase - 1);
                        posOut(rows, :) = base + panelOffset;
                        polIndex(rows) = pp;
                        panelIndex(rows) = pIdx;
                        writeIdx = writeIdx + nBase;
                    end
                end
            end
        end

        function [tf, ok] = localParseLogical(raw)
            tf = false;
            ok = false;
            if islogical(raw) && isscalar(raw)
                tf = logical(raw);
                ok = true;
                return;
            end
            if isnumeric(raw) && isscalar(raw) && isfinite(double(raw))
                tf = double(raw) ~= 0;
                ok = true;
                return;
            end
            if ischar(raw) || isstring(raw)
                token = lower(strtrim(char(string(raw))));
                if any(strcmp(token, {"true","t","yes","y","on","enabled","enable","1"}))
                    tf = true;
                    ok = true;
                elseif any(strcmp(token, {"false","f","no","n","off","disabled","disable","0"}))
                    tf = false;
                    ok = true;
                end
            end
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

        function [F_RF, F_BB] = localFactorCombinedHybridMatrix(combinedMatrix, numRFChains)
            %LOCALFACTORCOMBINEDHYBRIDMATRIX Exact deterministic RF/BB split.
            W = double(combinedMatrix);
            nPorts = size(W, 2);
            numRFChains = max(1, round(double(numRFChains)));
            if numRFChains < nPorts
                error("AntennaArrayFactory:RFChainsLessThanPorts", ...
                    "RF chain count %d is smaller than logical port count %d.", ...
                    numRFChains, nPorts);
            end
            columnNorms = sqrt(sum(abs(W).^2, 1));
            if any(~isfinite(columnNorms)) || any(columnNorms <= eps)
                error("AntennaArrayFactory:ConfiguredHybridMatrixZeroColumn", ...
                    "Configured combined hybrid matrix contains an invalid or all-zero logical-port column.");
            end
            normalizedColumns = W ./ columnNorms;
            assignments = mod(0:(numRFChains - 1), nPorts) + 1;
            assignmentCounts = accumarray(assignments(:), 1, [nPorts 1]).';
            F_RF = zeros(size(W, 1), numRFChains, "like", W);
            F_BB = zeros(numRFChains, nPorts, "like", W);
            for rfIdx = 1:numRFChains
                portIdx = assignments(rfIdx);
                F_RF(:, rfIdx) = normalizedColumns(:, portIdx);
                F_BB(rfIdx, portIdx) = columnNorms(portIdx) ./ assignmentCounts(portIdx);
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
