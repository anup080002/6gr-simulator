function [passed, failure, details] = validateReferenceQualificationTable(T)
%VALIDATEREFERENCEQUALIFICATIONTABLE Validate the canonical FRC gate table.
%
% 3GPP reference-point qualification is one-sided performance at the
% required SNR.  A symmetric measured-SNR crossing is an optional project
% regression.  Its measured SNR and delta are therefore required to be
% finite only on rows that explicitly set SymmetricRegressionRequired.

passed = false;
failure = "frc_reference_qualification_missing";
details = struct( ...
    "Evaluated", false, ...
    "RequiredRowCount", 0, ...
    "SymmetricRequiredRowCount", 0, ...
    "BaseContractPass", false, ...
    "SymmetricContractPass", false);
if ~(istable(T) && height(T) > 0)
    return;
end

columns = string(T.Properties.VariableNames);
requiredColumns = ["Pass","FullStandardExecutionExact", ...
    "DataChannelExact","StatisticallyQualified", ...
    "OneSidedReferencePass","Profile","EvidenceClass", ...
    "RequiredSNR_dB","MeasuredSNR_dB","Delta_dB", ...
    "CatalogSHA256","TransportBlocks"];
if any(~ismember(requiredColumns, columns))
    failure = "frc_reference_qualification_schema_invalid";
    return;
end

required = true(height(T), 1);
if ismember("Required", columns)
    required = localLogicalColumn(T.Required);
end
if ~any(required)
    failure = "frc_reference_qualification_has_no_required_rows";
    return;
end
rows = T(required, :);
details.RequiredRowCount = height(rows);

symmetricRequired = false(height(rows), 1);
if ismember("SymmetricRegressionRequired", columns)
    symmetricRequired = localLogicalColumn( ...
        rows.SymmetricRegressionRequired);
end
details.SymmetricRequiredRowCount = nnz(symmetricRequired);
if any(symmetricRequired) && ...
        any(~ismember(["SymmetricRegressionPass", ...
        "SymmetricRegressionStatisticallyQualified"], columns))
    failure = "frc_reference_qualification_schema_invalid";
    return;
end

hashes = lower(strtrim(string(rows.CatalogSHA256)));
hashOK = arrayfun(@(x) strlength(x) == 64 && ...
    ~isempty(regexp(char(x), "^[0-9a-f]{64}$", "once")), hashes);
requiredSNR = localNumericColumn(rows.RequiredSNR_dB);
transportBlocks = localNumericColumn(rows.TransportBlocks);
baseNumericOK = isfinite(requiredSNR) & ...
    isfinite(transportBlocks) & transportBlocks > 0 & ...
    transportBlocks == fix(transportBlocks);
baseContractPass = ...
    all(localLogicalColumn(rows.Pass)) && ...
    all(localLogicalColumn(rows.FullStandardExecutionExact)) && ...
    all(localLogicalColumn(rows.DataChannelExact)) && ...
    all(localLogicalColumn(rows.StatisticallyQualified)) && ...
    all(localLogicalColumn(rows.OneSidedReferencePass)) && ...
    all(lower(strtrim(string(rows.Profile))) == "full") && ...
    all(string(rows.EvidenceClass) == ...
        "ACTUAL_FRC_FULL_STANDARD_TRUTH_EXECUTION") && ...
    all(hashOK) && all(baseNumericOK);

symmetricContractPass = true;
if any(symmetricRequired)
    measured = localNumericColumn(rows.MeasuredSNR_dB);
    delta = localNumericColumn(rows.Delta_dB);
    symmetricPass = localLogicalColumn(rows.SymmetricRegressionPass);
    symmetricQualified = localLogicalColumn( ...
        rows.SymmetricRegressionStatisticallyQualified);
    symmetricContractPass = all(~symmetricRequired | ...
        (isfinite(measured) & isfinite(delta) & ...
        symmetricPass & symmetricQualified));
end

details.Evaluated = true;
details.BaseContractPass = logical(baseContractPass);
details.SymmetricContractPass = logical(symmetricContractPass);
passed = logical(baseContractPass && symmetricContractPass);
if passed
    failure = "";
else
    failure = "frc_reference_qualification_required_row_failed";
end
end

function values = localLogicalColumn(raw)
if islogical(raw)
    values = raw(:);
elseif isnumeric(raw)
    values = isfinite(double(raw(:))) & double(raw(:)) ~= 0;
else
    token = lower(strtrim(string(raw(:))));
    values = ismember(token, ["1","true","yes","on","pass","passed"]);
end
end

function values = localNumericColumn(raw)
if isnumeric(raw) || islogical(raw)
    values = double(raw(:));
else
    values = str2double(string(raw(:)));
end
end
