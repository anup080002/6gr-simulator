classdef TimingPolicyCatalog
    %TIMINGPOLICYCATALOG Pinned Release-18 production timing capability data.
    %
    % K0 and K2 are selected from configured PDSCH/PUSCH TDRA rows and K1
    % is selected from the configured PDSCH-to-HARQ_feedback timing list.
    % They are therefore configuration data, not universal constants.  This
    % catalog validates the provenance-bearing configured rows and supplies
    % the UE processing-time capability values that are normative constants.

    properties (Constant)
        StandardRelease = "3GPP Release 18"
        SpecificationVersion = "V18.8.0"
        CapabilityProfileBase = ...
            "38.214-v18.8.0-cap1-dmrs-pos0"
        PDSCHProcessingReference = ...
            "3GPP TS 38.214 V18.8.0 Table 5.3-1"
        PUSCHProcessingReference = ...
            "3GPP TS 38.214 V18.8.0 Table 6.4-1"
        K0Reference = ...
            "3GPP TS 38.214 V18.8.0 clause 5.1.2.1"
        K1Reference = ...
            "3GPP TS 38.213 V18.8.0 clause 9.2.3"
        K2Reference = ...
            "3GPP TS 38.214 V18.8.0 clause 6.1.2.1"
    end

    methods (Static)
        function ticks = processingSymbolTicks(symbols, mu)
            % TS 38.214 5.3/6.4 processing-time units, also for extended CP.
            % These are NOT durations obtained by counting waveform CPs.
            mu=localMu(mu);
            assert(mu<=6 && isnumeric(symbols) && isreal(symbols) && ...
                isscalar(symbols) && isfinite(symbols) && symbols>=0, ...
                'sixgr:phy:frame:InvalidProcessingSymbolDuration', ...
                'Processing duration requires finite nonnegative symbols and supported NR numerology.');
            value=double(symbols)*(2048+144)*64/2^mu;
            assert(isfinite(value) && value==fix(value) && value<=flintmax, ...
                'sixgr:phy:frame:InvalidProcessingSymbolDuration', ...
                'Processing duration must be an exactly representable integer number of Tc ticks.');
            ticks=int64(value);
        end

        function result = capability1ProcessingBase(procedure, numerologies)
            % Base N1/N2 budget only. Allocation-dependent d terms, switching
            % delays and the additional UCI multiplexing budget are separate.
            procedure=upper(string(procedure));
            assert(isscalar(procedure) && any(procedure==["HARQ_ACK","PUSCH"]) && ...
                isnumeric(numerologies) && isreal(numerologies) && ...
                isvector(numerologies) && ~isempty(numerologies), ...
                'sixgr:phy:frame:InvalidProcessingCapabilityRequest', ...
                'N1/N2 selection requires an explicit procedure and all participating numerologies.');
            result=struct('Ticks',int64(-1),'Mu',NaN,'Symbols',NaN, ...
                'Unit',"nr_nominal_symbol_duration", ...
                'Scope',"capability1_base_N1_N2_not_complete_UCI_budget");
            for mu=reshape(numerologies,1,[])
                row=sixgr.phy.frame.TimingPolicyCatalog.capability1(mu);
                if procedure=="HARQ_ACK", symbols=row.PDSCHN1Symbols;
                else, symbols=row.PUSCHN2Symbols; end
                ticks=sixgr.phy.frame.TimingPolicyCatalog.processingSymbolTicks(symbols,mu);
                if ticks>result.Ticks
                    result.Ticks=ticks; result.Mu=double(mu); result.Symbols=symbols;
                end
            end
        end

        function row = capability1(mu)
            %CAPABILITY1 Processing values for DM-RS additional position 0.
            %
            % Release-18 data-channel timing tables define rows for
            % mu={0,1,2,3,5,6}.  mu=4 is intentionally not invented.
            supportedMu = [0, 1, 2, 3, 5, 6];
            n1 = [8, 10, 17, 20, 80, 160];
            n2 = [10, 12, 23, 36, 144, 288];
            mu = localMu(mu);
            index = find(supportedMu == mu, 1);
            if isempty(index)
                error("sixgr:phy:frame:UnsupportedProductionTimingNumerology", ...
                    "The pinned capability-1 timing catalog has no " + ...
                    "production data-channel row for mu=%d.", mu);
            end
            row = struct( ...
                "CapabilityProfileBase", ...
                    sixgr.phy.frame.TimingPolicyCatalog.CapabilityProfileBase, ...
                "Mu", mu, ...
                "PDSCHN1Symbols", n1(index), ...
                "PUSCHN2Symbols", n2(index), ...
                "PDSCHProcessingTimeReference", "SOURCE", ...
                "PUSCHProcessingTimeReference", "TARGET", ...
                "PDSCHStandardReference", ...
                    sixgr.phy.frame.TimingPolicyCatalog.PDSCHProcessingReference, ...
                "PUSCHStandardReference", ...
                    sixgr.phy.frame.TimingPolicyCatalog.PUSCHProcessingReference, ...
                "StandardRelease", ...
                    sixgr.phy.frame.TimingPolicyCatalog.StandardRelease, ...
                "SpecificationVersion", ...
                    sixgr.phy.frame.TimingPolicyCatalog.SpecificationVersion);
        end

        function values = defaultK1Values(mu)
            %DEFAULTK1VALUES DCI format 1_0 timing values from TS 38.213.
            mu = localMu(mu);
            if mu <= 3
                values = 1:8;
            elseif mu == 5
                values = [7, 8, 12, 16, 20, 24, 28, 32];
            elseif mu == 6
                values = [13, 16, 24, 32, 40, 48, 56, 64];
            else
                error("sixgr:phy:frame:UnsupportedProductionTimingNumerology", ...
                    "TS 38.213 V18.8.0 clause 9.2.3 provides no " + ...
                    "DCI-1_0 default K1 set for mu=%d.", mu);
            end
        end

        function rows = configuredRows(relation, values, sourcePath)
            %CONFIGUREDROWS Add honest configuration/standard provenance.
            relation = upper(string(relation));
            if ~any(relation == ["K0", "K1", "K2"])
                error("sixgr:phy:frame:InvalidTimingRelation", ...
                    "Configured timing relation must be K0, K1, or K2.");
            end
            values = localIntegerVector(values, relation);
            sourcePath = strtrim(string(sourcePath));
            if strlength(sourcePath) == 0
                error("sixgr:phy:frame:MissingTimingRowProvenance", ...
                    "%s rows require a configuration source path.", relation);
            end
            if relation == "K0"
                reference = ...
                    sixgr.phy.frame.TimingPolicyCatalog.K0Reference;
                selection = "configured_pdsch_tdra";
            elseif relation == "K1"
                reference = ...
                    sixgr.phy.frame.TimingPolicyCatalog.K1Reference;
                selection = "configured_pdsch_to_harq_feedback_list";
            else
                reference = ...
                    sixgr.phy.frame.TimingPolicyCatalog.K2Reference;
                selection = "configured_pusch_tdra";
            end
            rows = repmat(struct( ...
                "Relation", relation, ...
                "ConfiguredOrdinal", 0, ...
                "Value", 0, ...
                "SelectionDomain", selection, ...
                "StandardReference", reference, ...
                "ConfigurationSource", sourcePath, ...
                "IndexConvention", "zero_based"), numel(values), 1);
            for index = 1:numel(values)
                rows(index).ConfiguredOrdinal = index - 1;
                rows(index).Value = values(index);
            end
        end

        function resolved = resolveProduction(attached, dlMu, ulMu, ...
                requiredRelations)
            %RESOLVEPRODUCTION Validate and pin a runtime production policy.
            if nargin < 4 || isempty(requiredRelations)
                requiredRelations = ["K0", "K1", "K2"];
            end
            requiredRelations = unique(upper(string( ...
                requiredRelations(:).')), "stable");
            if any(~ismember(requiredRelations, ["K0", "K1", "K2"]))
                error("sixgr:phy:frame:InvalidTimingRelation", ...
                    "Required production timing relations must be K0, K1, or K2.");
            end
            if ~(isstruct(attached) && isscalar(attached))
                error("sixgr:phy:frame:InvalidProductionTimingPolicy", ...
                    "The attached production timing policy must be a scalar struct.");
            end
            profile = strtrim(string(localRequiredField( ...
                attached, "CapabilityProfileID")));
            dlRow = sixgr.phy.frame.TimingPolicyCatalog.capability1(dlMu);
            ulRow = sixgr.phy.frame.TimingPolicyCatalog.capability1(ulMu);
            localValidateProfile(profile, dlRow.Mu, ulRow.Mu);

            localRequireExactScalar(attached, ...
                "N1PDSCHProcessingTimeSymbols", dlRow.PDSCHN1Symbols);
            localRequireExactScalar(attached, ...
                "N2PUSCHPreparationTimeSymbols", ulRow.PUSCHN2Symbols);
            processing = localRequiredField(attached, ...
                "ControlToDataProcessingTimeSymbols");
            if ~(isstruct(processing) && isscalar(processing))
                error("sixgr:phy:frame:InvalidProductionTimingPolicy", ...
                    "ControlToDataProcessingTimeSymbols must be a scalar struct.");
            end
            localRequireExactScalar(processing, "PDCCHToPDSCH", 0);
            localRequireExactScalar(processing, ...
                "PDSCHToHARQACKN1", dlRow.PDSCHN1Symbols);
            localRequireExactScalar(processing, ...
                "PDCCHToPUSCHN2", ulRow.PUSCHN2Symbols);

            resolved = attached;
            resolved.PolicyID = "3gpp_release18_production_timing";
            resolved.StandardRelease = ...
                sixgr.phy.frame.TimingPolicyCatalog.StandardRelease;
            resolved.SpecificationVersion = ...
                sixgr.phy.frame.TimingPolicyCatalog.SpecificationVersion;
            resolved.CapabilityProfileID = profile;
            for relation = ["K0", "K1", "K2"]
                allowedField = "Allowed" + relation;
                rowField = relation + "Rows";
                if ismember(relation, requiredRelations)
                    [resolved.(allowedField), resolved.(rowField)] = ...
                        localValidatedConfiguredRows(attached, relation);
                else
                    if isfield(attached, allowedField)
                        resolved.(allowedField) = ...
                            reshape(double(attached.(allowedField)), 1, []);
                    else
                        resolved.(allowedField) = zeros(1, 0);
                    end
                    if isfield(attached, rowField)
                        resolved.(rowField) = attached.(rowField);
                    else
                        resolved.(rowField) = struct([]);
                    end
                end
            end
            resolved.ControlToDataProcessingTimeSymbols = struct( ...
                "PDCCHToPDSCH", 0, ...
                "PDSCHToHARQACKN1", dlRow.PDSCHN1Symbols, ...
                "PDCCHToPUSCHN2", ulRow.PUSCHN2Symbols);
            resolved.PDSCHProcessingTimeReference = ...
                dlRow.PDSCHProcessingTimeReference;
            resolved.PUSCHProcessingTimeReference = ...
                ulRow.PUSCHProcessingTimeReference;
            resolved.PDSCHProcessingStandardReference = ...
                dlRow.PDSCHStandardReference;
            resolved.PUSCHProcessingStandardReference = ...
                ulRow.PUSCHStandardReference;
        end
    end
end

function mu = localMu(input)
if ~(isnumeric(input) && isreal(input) && isscalar(input) && ...
        isfinite(double(input)) && double(input) >= 0 && ...
        double(input) == fix(double(input)))
    error("sixgr:phy:frame:InvalidTimingNumerology", ...
        "Timing numerology mu must be a nonnegative integer.");
end
mu = double(input);
end

function values = localIntegerVector(input, label)
if ~(isnumeric(input) && isreal(input) && ~isempty(input) && ...
        all(isfinite(double(input(:)))) && ...
        all(double(input(:)) >= 0) && ...
        all(double(input(:)) == fix(double(input(:)))))
    error("sixgr:phy:frame:InvalidProductionTimingPolicy", ...
        "%s values must be a nonempty vector of nonnegative integers.", label);
end
values = unique(reshape(double(input), 1, []), "stable");
end

function value = localRequiredField(input, field)
if ~isfield(input, field) || isempty(input.(field))
    error("sixgr:phy:frame:IncompleteProductionTimingPolicy", ...
        "The production timing policy requires '%s'.", field);
end
value = input.(field);
end

function localRequireExactScalar(input, field, expected)
value = localRequiredField(input, field);
if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
        isfinite(double(value)) && double(value) == expected)
    error("sixgr:phy:frame:ProductionTimingCapabilityOverride", ...
        "%s must equal the pinned Release-18 value %g; received '%s'.", ...
        field, expected, string(value));
end
end

function localValidateProfile(profile, dlMu, ulMu)
base = sixgr.phy.frame.TimingPolicyCatalog.CapabilityProfileBase;
if profile == base
    return;
end
dlSpecific = base + "-mu" + string(dlMu);
if dlMu == ulMu && profile == dlSpecific
    return;
end
error("sixgr:phy:frame:UnsupportedProductionTimingCapability", ...
    "CapabilityProfileID '%s' is incompatible with DL mu=%d and UL mu=%d.", ...
    profile, dlMu, ulMu);
end

function [values, rows] = localValidatedConfiguredRows(policy, relation)
allowedField = "Allowed" + relation;
rowField = relation + "Rows";
values = localIntegerVector(localRequiredField(policy, allowedField), ...
    allowedField);
rows = localRequiredField(policy, rowField);
if ~(isstruct(rows) && numel(rows) == numel(values))
    error("sixgr:phy:frame:MissingTimingRowProvenance", ...
        "%s must contain one provenance row per configured value.", rowField);
end
rowValues = zeros(1, numel(rows));
for index = 1:numel(rows)
    row = rows(index);
    required = ["Relation", "ConfiguredOrdinal", "Value", ...
        "SelectionDomain", "StandardReference", ...
        "ConfigurationSource", "IndexConvention"];
    if any(~isfield(row, required))
        error("sixgr:phy:frame:MissingTimingRowProvenance", ...
            "%s row %d is incomplete.", rowField, index - 1);
    end
    if upper(string(row.Relation)) ~= relation || ...
            double(row.ConfiguredOrdinal) ~= index - 1 || ...
            string(row.IndexConvention) ~= "zero_based" || ...
            strlength(strtrim(string(row.SelectionDomain))) == 0 || ...
            strlength(strtrim(string(row.StandardReference))) == 0 || ...
            strlength(strtrim(string(row.ConfigurationSource))) == 0
        error("sixgr:phy:frame:InvalidTimingRowProvenance", ...
            "%s row %d has invalid identity or provenance.", ...
            rowField, index - 1);
    end
    rowValues(index) = double(row.Value);
end
if ~isequal(rowValues, values)
    error("sixgr:phy:frame:TimingRowValueMismatch", ...
        "%s values must be derived exactly from %s.", ...
        allowedField, rowField);
end
end
