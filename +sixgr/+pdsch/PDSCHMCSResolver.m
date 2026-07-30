classdef PDSCHMCSResolver
    %PDSCHMCSResolver Fail-closed per-codeword Release-18 MCS resolution.

    methods (Static)
        function profiles = resolve(tableNames, indices, context)
            arguments
                tableNames
                indices (1,:) double
                context (1,1) struct
            end

            tableNames = string(tableNames);
            tableNames = tableNames(:).';
            indices = double(indices(:).');
            if isempty(tableNames)
                error("sixgr:pdsch:MissingMCSTable", ...
                    "An MCS table is required for every enabled PDSCH codeword.");
            end
            if numel(tableNames) ~= numel(indices)
                error("sixgr:pdsch:MissingCodewordSpecificMCS", ...
                    "MCS table and index vectors must contain one entry per codeword.");
            end
            if isfield(context, "NumCodewords") && ...
                    numel(indices) ~= double(context.NumCodewords)
                error("sixgr:pdsch:CodewordCountMismatch", ...
                    "Expected %d MCS entries, received %d.", ...
                    round(double(context.NumCodewords)), numel(indices));
            end

            template = struct( ...
                "Valid", false, "Table", "", "MCSIndex", NaN, "Qm", NaN, ...
                "Modulation", "", "TargetCodeRate", NaN, ...
                "SpectralEfficiency", NaN, "CapabilityCondition", "", ...
                "SelectionSource", "");
            profiles = repmat(template, 1, numel(indices));
            for cw = 1:numel(indices)
                codewordContext = context;
                codewordContext.CodewordIndex = cw - 1;
                profiles(cw) = sixgr.pdsch.PDSCHMCSResolver.resolveOne( ...
                    tableNames(cw), indices(cw), codewordContext);
            end
        end

        function profile = resolveOne(tableName, index, context)
            arguments
                tableName
                index (1,1) double
                context (1,1) struct
            end

            if ~isfinite(index) || index ~= fix(index) || index < 0
                error("sixgr:pdsch:MCSIndexOutOfRange", ...
                    "MCS index must be a finite nonnegative integer.");
            end
            token = lower(strtrim(string(tableName)));
            token = sixgr.pdsch.PDSCHMCSResolver.canonicalTable(token);
            if strlength(token) == 0
                error("sixgr:pdsch:MissingMCSTable", ...
                    "PDSCH MCS table is missing or unsupported.");
            end

            if token == "calibration_explicit"
                [modulation, qm, targetRate, se] = ...
                    sixgr.pdsch.PDSCHMCSResolver.calibrationEntry( ...
                    index, context);
            else
                [qm, r1024, se, reserved] = ...
                    sixgr.pdsch.PDSCHMCSResolver.tableEntry(token, index);
                if reserved
                    error("sixgr:pdsch:ReservedMCSEntry", ...
                        "MCS index %d is reserved in table '%s'.", index, token);
                end
                modulation = ...
                    sixgr.pdsch.PDSCHMCSResolver.modulationForQm(qm);
                targetRate = double(r1024) / 1024;
            end
            if token == "qam1024_table4" || modulation == "1024QAM"
                sixgr.pdsch.PDSCHMCSResolver.require1024QAMContext(context);
            end
            if modulation == "4096QAM"
                error("sixgr:pdsch:UnsupportedNRModulation", ...
                    "4096QAM is not a normative PDSCH modulation in this strict profile.");
            end

            profile = struct( ...
                "Valid", true, ...
                "Table", char(token), ...
                "MCSIndex", double(index), ...
                "Qm", double(qm), ...
                "Modulation", char(modulation), ...
                "TargetCodeRate", double(targetRate), ...
                "SpectralEfficiency", double(se), ...
                "CapabilityCondition", char( ...
                    sixgr.pdsch.PDSCHMCSResolver.capabilityText( ...
                        modulation, token)), ...
                "SelectionSource", char(string(sixgr.util.structGet( ...
                    context, "SelectionSource", "decoded_dci+rrc_context"))));
        end
    end

    methods (Static, Access = private)
        function token = canonicalTable(token)
            switch token
                case {"qam64","64qam","qam64_table1","table1"}
                    token = "qam64_table1";
                case {"qam256","256qam","qam256_table2","table2"}
                    token = "qam256_table2";
                case {"qam64lowse","64qamlowse","qam64lowse_table3","table3"}
                    token = "qam64lowse_table3";
                case {"qam1024","qam1024_table4","table4"}
                    token = "qam1024_table4";
                case {"calibration_explicit","explicit_calibration"}
                    token = "calibration_explicit";
                otherwise
                    token = "";
            end
        end

        function [modulation, qm, targetRate, spectralEfficiency] = ...
                calibrationEntry(index, context)
            profile = lower(strtrim(string(sixgr.util.structGet( ...
                context, "ExecutionProfile", ""))));
            if profile ~= "phy_calibration"
                error("sixgr:pdsch:CalibrationMCSOutsideCalibrationProfile", ...
                    char("The calibration_explicit MCS token is valid only for " + ...
                    "the phy_calibration execution profile."));
            end
            cw = double(sixgr.util.structGet( ...
                context, "CodewordIndex", NaN));
            if ~(isscalar(cw) && isfinite(cw) && cw == fix(cw) && cw >= 0)
                error("sixgr:pdsch:IncompleteCalibrationMCSContext", ...
                    "Calibration MCS resolution requires CodewordIndex.");
            end
            modulation = upper(strtrim(string( ...
                sixgr.pdsch.PDSCHMCSResolver.contextVectorValue( ...
                context, "CalibrationModulationPerCodeword", cw))));
            qm = double( ...
                sixgr.pdsch.PDSCHMCSResolver.contextVectorValue( ...
                context, "CalibrationQmPerCodeword", cw));
            targetRate = double( ...
                sixgr.pdsch.PDSCHMCSResolver.contextVectorValue( ...
                context, "CalibrationTargetCodeRatePerCodeword", cw));
            tokens = string(sixgr.util.structGet( ...
                context, "CalibrationTokenPerCodeword", strings(1,0)));
            tokens = tokens(:).';
            if numel(tokens) <= cw || ...
                    lower(strtrim(tokens(cw + 1))) ~= "calibration_explicit"
                error("sixgr:pdsch:IncompleteCalibrationMCSContext", ...
                    char("CalibrationTokenPerCodeword must explicitly select " + ...
                    "calibration_explicit for every calibration codeword."));
            end
            expectedQm = sixgr.pdsch.PDSCHMCSResolver.qmForModulation( ...
                modulation);
            if qm ~= expectedQm
                error("sixgr:pdsch:CalibrationMCSQmMismatch", ...
                    char("Calibration codeword %d selects %s but Qm=%g; " + ...
                    "expected Qm=%g."), cw, modulation, qm, expectedQm);
            end
            if ~(isscalar(targetRate) && isfinite(targetRate) ...
                    && targetRate > 0 && targetRate < 1)
                error("sixgr:pdsch:InvalidCalibrationTargetCodeRate", ...
                    char("Calibration codeword %d target rate must be a finite " + ...
                    "scalar strictly between zero and one."), cw);
            end
            if index ~= cw
                error("sixgr:pdsch:CalibrationMCSIndexMismatch", ...
                    char("calibration_explicit uses the typed zero-based " + ...
                    "codeword index; codeword %d received index %d."), ...
                    cw, index);
            end
            spectralEfficiency = qm * targetRate;
        end

        function value = contextVectorValue(context, fieldName, cw)
            raw = sixgr.util.structGet(context, fieldName, []);
            if iscell(raw)
                raw = string(raw);
            end
            raw = raw(:).';
            if numel(raw) <= cw
                error("sixgr:pdsch:IncompleteCalibrationMCSContext", ...
                    "%s requires one explicit value per codeword.", fieldName);
            end
            value = raw(cw + 1);
        end

        function [qm, r1024, se, reserved] = tableEntry(token, index)
            if exist("nrPDSCHMCSTables", "file") ~= 2
                error("sixgr:pdsch:MissingNormativeMCSTable", ...
                    "5G Toolbox nrPDSCHMCSTables is required for strict MCS resolution.");
            end
            catalog = nrPDSCHMCSTables;
            switch token
                case "qam64_table1"
                    tableData = catalog.QAM64Table;
                case "qam256_table2"
                    tableData = catalog.QAM256Table;
                case "qam64lowse_table3"
                    tableData = catalog.QAM64LowSETable;
                case "qam1024_table4"
                    tableData = catalog.QAM1024Table;
                otherwise
                    error("sixgr:pdsch:MissingMCSTable", ...
                        "Unsupported PDSCH MCS table '%s'.", token);
            end
            if index > 31
                qm = NaN; r1024 = NaN; se = NaN; reserved = true;
                return;
            end
            row = tableData(double(index) + 1, :);
            qm = double(row.Qm);
            rate = double(row.TargetCodeRate);
            se = double(row.SpectralEfficiency);
            r1024 = rate * 1024;
            reserved = ~isfinite(qm) || ~isfinite(rate) || ~isfinite(se);
        end

        function require1024QAMContext(context)
            required = [ ...
                "UECapability1024QAM","RRCEnabled1024QAM", ...
                "DCIEnabled1024QAM"];
            for idx = 1:numel(required)
                name = required(idx);
                if ~isfield(context, name) ...
                        || ~(islogical(context.(name)) ...
                        && isscalar(context.(name))) ...
                        || ~context.(name)
                    error("sixgr:pdsch:UnsupportedMCSContext", ...
                        "1024QAM requires %s=true.", name);
                end
            end

            frequencyRange = upper(strtrim(string( ...
                sixgr.util.structGet(context, "FrequencyRange", ""))));
            if ~isscalar(frequencyRange)
                error("sixgr:pdsch:Unsupported1024QAMFrequencyRange", ...
                    "FrequencyRange must be a text scalar.");
            end
            if strlength(frequencyRange) == 0
                error("sixgr:pdsch:Missing1024QAMFrequencyRangeContext", ...
                    "1024QAM requires an explicit FrequencyRange.");
            end
            if ~any(frequencyRange == ["FR1","FR2-1","FR2-2"])
                error("sixgr:pdsch:Unsupported1024QAMFrequencyRange", ...
                    "Unsupported 1024QAM frequency range '%s'.", ...
                    char(frequencyRange));
            end

            operatingBand = upper(strtrim(string( ...
                sixgr.util.structGet(context, "OperatingBand", ""))));
            if ~isscalar(operatingBand)
                error("sixgr:pdsch:Invalid1024QAMOperatingBand", ...
                    "OperatingBand must be a text scalar.");
            end
            if strlength(operatingBand) == 0
                error("sixgr:pdsch:Missing1024QAMBandContext", ...
                    "1024QAM requires an explicit NR OperatingBand.");
            end
            if isempty(regexp(char(operatingBand), ...
                    "^N[1-9][0-9]{0,3}$", "once"))
                error("sixgr:pdsch:Invalid1024QAMOperatingBand", ...
                    "OperatingBand '%s' is not a canonical NR band token.", ...
                    char(operatingBand));
            end

            deploymentClass = lower(strtrim(string( ...
                sixgr.util.structGet(context, "DeploymentClass", ""))));
            if ~isscalar(deploymentClass)
                error("sixgr:pdsch:Invalid1024QAMDeploymentClass", ...
                    "DeploymentClass must be a text scalar.");
            end
            if strlength(deploymentClass) == 0
                error("sixgr:pdsch:Missing1024QAMDeploymentClass", ...
                    "1024QAM requires an explicit DeploymentClass.");
            end
            if isempty(regexp(char(deploymentClass), ...
                    "^[a-z0-9][a-z0-9_-]*$", "once"))
                error("sixgr:pdsch:Invalid1024QAMDeploymentClass", ...
                    "DeploymentClass '%s' is not a canonical token.", ...
                    char(deploymentClass));
            end

            dciFormat = upper(strtrim(string( ...
                sixgr.util.structGet(context, "DCIFormat", ""))));
            if ~isscalar(dciFormat)
                error("sixgr:pdsch:QAM1024DCIFormatNotAllowed", ...
                    "DCIFormat must be a text scalar.");
            end
            if strlength(dciFormat) == 0
                error("sixgr:pdsch:Missing1024QAMDCIFormat", ...
                    "1024QAM requires the actual scheduling DCIFormat.");
            end

            capabilityVariant = lower(strtrim(string( ...
                sixgr.util.structGet( ...
                    context, "UECapability1024QAMVariant", ""))));
            if isempty(capabilityVariant) || all(strlength(capabilityVariant) == 0)
                error("sixgr:pdsch:Missing1024QAMCapabilityVariant", ...
                    char("1024QAM requires the exact per-band TS 38.306 " + ...
                    "capability variant."));
            end
            if ~isscalar(capabilityVariant)
                error("sixgr:pdsch:QAM1024CapabilityVariantsMutuallyExclusive", ...
                    char("pdsch-1024QAM-FR1-r17 and " + ...
                    "pdsch-1024QAM-2MIMO-FR1-r17 are mutually exclusive " + ...
                    "per band."));
            end
            if ~isfield(context, "MaxNumberMIMOLayersPDSCH") || ...
                    isempty(context.MaxNumberMIMOLayersPDSCH)
                error("sixgr:pdsch:Missing1024QAMMaxNumberMIMOLayersPDSCH", ...
                    char("1024QAM requires the per-band " + ...
                    "MaxNumberMIMOLayersPDSCH capability."));
            end
            if ~isfield(context, "NumLayers") || isempty(context.NumLayers)
                error("sixgr:pdsch:Missing1024QAMNumLayers", ...
                    "1024QAM resolution requires the scheduled NumLayers.");
            end

            sixgr.pdsch.PDSCHMCSResolver.requireEligibility( ...
                context, "FrequencyRangeAllows1024QAM", ...
                "Missing1024QAMFrequencyRangeEligibility", ...
                "QAM1024FrequencyRangeNotAllowed");
            sixgr.pdsch.PDSCHMCSResolver.requireEligibility( ...
                context, "BandAllows1024QAM", ...
                "Missing1024QAMBandEligibility", ...
                "QAM1024BandNotAllowed");
            sixgr.pdsch.PDSCHMCSResolver.requireEligibility( ...
                context, "DeploymentAllows1024QAM", ...
                "Missing1024QAMDeploymentEligibility", ...
                "QAM1024DeploymentClassNotAllowed");

            rntiType = upper(strtrim(string( ...
                sixgr.util.structGet(context, "RNTIType", ""))));
            sixgr.pdsch.PDSCH1024QAMApplicability.requireApplicable( ...
                frequencyRange, operatingBand, deploymentClass, ...
                dciFormat, rntiType, capabilityVariant, ...
                context.MaxNumberMIMOLayersPDSCH, context.NumLayers);
        end

        function requireEligibility(context, fieldName, missingToken, deniedToken)
            if ~isfield(context, fieldName) ...
                    || ~(islogical(context.(fieldName)) ...
                    && isscalar(context.(fieldName)))
                error(char("sixgr:pdsch:" + missingToken), ...
                    "%s must be present as an explicit logical scalar.", ...
                    fieldName);
            end
            if ~context.(fieldName)
                error(char("sixgr:pdsch:" + deniedToken), ...
                    "1024QAM is not allowed by %s.", fieldName);
            end
        end

        function value = modulationForQm(qm)
            switch double(qm)
                case 2
                    value = "QPSK";
                case 4
                    value = "16QAM";
                case 6
                    value = "64QAM";
                case 8
                    value = "256QAM";
                case 10
                    value = "1024QAM";
                otherwise
                    error("sixgr:pdsch:UnsupportedQm", ...
                        "PDSCH modulation order Qm=%g is unsupported.", qm);
            end
        end

        function qm = qmForModulation(modulation)
            switch upper(strtrim(string(modulation)))
                case "QPSK"
                    qm = 2;
                case "16QAM"
                    qm = 4;
                case "64QAM"
                    qm = 6;
                case "256QAM"
                    qm = 8;
                case "1024QAM"
                    qm = 10;
                otherwise
                    error("sixgr:pdsch:UnsupportedNRModulation", ...
                        "Unsupported explicit calibration modulation '%s'.", ...
                        modulation);
            end
        end

        function text = capabilityText(modulation, tableToken)
            if modulation == "1024QAM" || tableToken == "qam1024_table4"
                text = "per_band_UE_variant+layer_limit+RRC+" + ...
                    "DCI_1_1_1_2_or_1_3+C_RNTI+FR1+band+" + ...
                    "deployment_policy_enabled";
            else
                text = "baseline_nr_capability";
            end
        end
    end
end
