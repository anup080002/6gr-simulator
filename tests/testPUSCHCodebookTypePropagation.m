function [ok, checks] = testPUSCHCodebookTypePropagation()
%TESTPUSCHCODEBOOKTYPEPROPAGATION Native codebook arithmetic/configuration.
% This is a deliberately red reproducer until the production resolver
% propagates the actual eight-port CodebookType to its catalog and matrix.
% It calls existing production APIs, not a proposed fifth-argument adapter.
% No waveform, received DCI, measured SRS, accepted decision, or scheduler
% execution is produced by these declared configuration cases. In particular,
% current strict SRS and connected-DCI eight-port guards are not relaxed.
%
% Independent valid-TPMI sets below: TS 38.211 V18.8.0, section 6.3.1.5,
% tables 9--24, 29--36, 39--47. Matrix oracle: public R2026a API, not copied
% Toolbox internals. Native matrix agreement is an interoperability check,
% not independent numerical verification of every standard matrix entry.
% https://www.etsi.org/deliver/etsi_ts/138200_138299/138211/18.08.00_60/ts_138211v180800p.pdf
% https://www.mathworks.com/help/releases/R2026a/5g/ref/nrpuschcodebook.html

setup6GRSimToolkit('Verbose', false);
assert(strcmp(version('-release'), '2026a'), ...
    'sixgr:test:PUSCHCodebookType:PinnedRelease', ...
    'This reproducer pins the R2026a public 5G Toolbox contract.');
assert(exist('nrPUSCHCodebook', 'file') == 2 && ...
    exist('nrPUSCHConfig', 'class') == 8, ...
    'sixgr:test:PUSCHCodebookType:ToolboxRequired', ...
    'Native codebook evidence cannot be replaced by a skipped/pass result.');

types = ["codebook1_ng1n4n1", "codebook1_ng1n2n2", ...
    "codebook2", "codebook3", "codebook4"];
prototype = struct('Check', "", 'CodebookType', "", 'NumPorts', NaN, ...
    'NumLayers', NaN, 'TPMI', NaN, 'TransformPrecoding', false, ...
    'Passed', false, 'FailureID', "", 'FailureDetail', "", ...
    'EvidenceScope', "declared_native_codebook_arithmetic_no_waveform");
rows = repmat(prototype, 0, 1);

% A valid but inactive property must remain replayable on two/four ports;
% it must not change the selected native matrix or its valid TPMI domain.
smallPorts = [2 1 5; 2 2 2; 4 1 27; 4 2 21; 4 3 6; 4 4 4];
for k = 1:size(smallPorts, 1)
    ports = smallPorts(k, 1); layers = smallPorts(k, 2);
    validSet = 0:smallPorts(k, 3);
    record("inactive_selector_all_valid_TPMIs", "all_five_types", ...
        ports, layers, NaN, false, ...
        @() localInactiveSelector(types, ports, layers, validSet, false));
    if layers == 1
        % Transform-precoded waveform scope is one layer. Do not broaden it
        % merely because an arithmetic Toolbox call accepts other ranks.
        record("inactive_selector_transform_rank1", "all_five_types", ...
            ports, layers, NaN, true, ...
            @() localInactiveSelector(types, ports, layers, validSet, true));
    end
end

for type = types
    for layers = 1:8
        validSet = localEightPortTPMISet(type, layers);
        record("native_all_valid_TPMIs_and_boundaries", type, 8, layers, ...
            NaN, false, @() localNativeDomain(type, layers, validSet, false));
        record("production_type_specific_invalid_TPMIs", type, 8, layers, ...
            NaN, false, @() localResolvedInvalid(type, layers, validSet));
        % Current producer accepts the property on an actual nrPUSCHConfig.
        % Exercise first/middle/last and any isolated table-47 extension;
        % include the full candidate set in each production comparison.
        picks = unique(validSet([1, ceil(numel(validSet)/2), end]));
        for tpmi = picks
            record("production_resolver_catalog_and_matrix", type, ...
                8, layers, tpmi, false, ...
                @() localResolved(type, 8, layers, tpmi, false, validSet));
        end
        if layers == 1
            record("native_transform_rank1_domain", type, 8, layers, ...
                NaN, true, @() localNativeDomain(type, layers, validSet, true));
            for tpmi = picks
                record("production_transform_rank1", type, 8, layers, ...
                    tpmi, true, ...
                    @() localResolved(type, 8, layers, tpmi, true, validSet));
            end
        end
    end
end

record("native_invalid_and_fractional_configuration", "native_validation", ...
    NaN, NaN, NaN, false, @localNativeInvalidInputs);
record("production_fractional_TPMI_rejection", "codebook1_ng1n4n1", ...
    2, 1, 0.5, false, @localProductionFractionalTPMI);

checks = struct2table(rows);
failures = checks(~checks.Passed, :);
if ~isempty(failures)
    % Keep every failed case visible to the bounded batch log. A known
    % defect is not converted into a passing expected-failure result.
    for k = 1:height(failures)
        fprintf(2, '%s | %s | ports=%g layers=%g TPMI=%g transform=%d | %s | %s\n', ...
            char(failures.Check(k)), char(failures.CodebookType(k)), ...
            failures.NumPorts(k), failures.NumLayers(k), failures.TPMI(k), ...
            failures.TransformPrecoding(k), char(failures.FailureID(k)), ...
            char(failures.FailureDetail(k)));
    end
end
assert(isempty(failures), 'sixgr:test:PUSCHCodebookType:Propagation', ...
    '%d of %d declared native-codebook checks failed; no waveform was executed.', ...
    height(failures), height(checks));
ok = true;

    function record(name, type, ports, layers, tpmi, transform, operation)
        row = prototype;
        row.Check = name; row.CodebookType = type;
        row.NumPorts = ports; row.NumLayers = layers; row.TPMI = tpmi;
        row.TransformPrecoding = transform;
        try
            operation();
            row.Passed = true;
        catch ME
            row.FailureID = string(ME.identifier);
            row.FailureDetail = string(ME.message);
        end
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end

function values = localEightPortTPMISet(type, layers)
% Table-domain facts, not a copied implementation of the precoder matrices.
counts = [16 32 24 24 8 8 4 4; ...
          16 32 24 24 8 8 8 8; ...
          33 272 264 68 32 16 8 4; ...
          17 105 305 280 160 80 32 16];
types = ["codebook1_ng1n4n1", "codebook1_ng1n2n2", "codebook2", "codebook3"];
idx = find(types == type);
if ~isempty(idx)
    values = 0:counts(idx, layers)-1;
else
    assert(type == "codebook4");
    % Table 47 has rank-dependent, non-zero-origin, non-contiguous TPMIs.
    sets = { [0:7 255], [8:35 256], [36:91 257], [92:161 258], ...
        162:217, 218:245, 246:253, 254 };
    values = sets{layers};
end
end

function localNativeDomain(type, layers, validSet, transform)
for tpmi = validSet
    W = nrPUSCHCodebook(layers, 8, tpmi, transform, char(type));
    assert(isequal(size(W), [layers 8]) && all(isfinite(W(:))) && rank(W) == layers, ...
        'sixgr:test:PUSCHCodebookType:NativeMatrix', ...
        'Native five-argument matrix must be finite and full row rank.');
end
invalid = unique([min(validSet)-1, max(validSet)+1, 0, 304]);
invalid = invalid(invalid >= 0 & invalid <= 304 & ~ismember(invalid, validSet));
% Include the first hole after the contiguous part of table 47.
holes = setdiff(0:304, validSet);
if ~isempty(holes), invalid = unique([invalid holes(1)]); end
for tpmi = invalid
    if type == "codebook4"
        expectedID = "nr5g:nrPUSCHCodebook:InvalidTPMICodebook4";
    else
        expectedID = "nr5g:nrPUSCHCodebook:InvalidTPMI8Tx";
    end
    localMustReject(@() nrPUSCHCodebook(layers, 8, tpmi, transform, char(type)), expectedID);
end
end

function localInactiveSelector(types, ports, layers, validSet, transform)
for tpmi = validSet
    baseline = nrPUSCHCodebook(layers, ports, tpmi, transform, char(types(1)));
    for type = types
        actual = nrPUSCHCodebook(layers, ports, tpmi, transform, char(type));
        assert(isequal(actual, baseline), ...
            'sixgr:test:PUSCHCodebookType:InactiveSelector', ...
            'CodebookType is not a matrix selector for two/four antenna ports.');
        localResolved(type, ports, layers, tpmi, transform, validSet);
    end
end
end

function localResolvedInvalid(type, layers, validSet)
% Keep the actual object's generic TPMI range valid so rejection must come
% from the selected family's rank-specific catalog, not its property setter.
cfg=localArchitectureConfig(8);
invalid = unique([0, min(validSet)-1, max(validSet)+1, 304]);
invalid = invalid(invalid >= 0 & invalid <= 304 & ~ismember(invalid, validSet));
for tpmi = invalid
    pusch = nrPUSCHConfig('TransmissionScheme', 'codebook', ...
        'NumAntennaPorts', 8, 'NumLayers', layers, 'TPMI', tpmi, ...
        'TransformPrecoding', false, 'CodebookType', char(type));
    rejected = false;
    try
        sixgr.phy.ul.resolvePUSCHPrecoding(pusch, cfg, 'FixedReferenceMode', true);
    catch ME
        assert(strcmp(ME.identifier, 'sixgr:phy:ul:PUSCHPrecoding:UnsupportedCodebook'), ...
            'sixgr:test:PUSCHCodebookType:WrongRejection', ...
            'An invalid family/rank TPMI must fail the production codebook guard.');
        rejected = true;
    end
    assert(rejected, 'sixgr:test:PUSCHCodebookType:MissingRejection', ...
        'Production accepted TPMI=%d outside the selected %s rank-%d domain.', ...
        tpmi, char(type), layers);
end
end

function localResolved(type, ports, layers, tpmi, transform, validSet)
pusch = nrPUSCHConfig('TransmissionScheme', 'codebook', ...
    'NumAntennaPorts', ports, 'NumLayers', layers, 'TPMI', tpmi, ...
    'TransformPrecoding', transform, 'CodebookType', char(type));
cfg=localArchitectureConfig(ports);
prec = sixgr.phy.ul.resolvePUSCHPrecoding(pusch, cfg, 'FixedReferenceMode', true);
expected = double(nrPUSCHCodebook(layers, ports, tpmi, transform, char(type)));
assert(string(prec.CodebookMode) == type, ...
    'sixgr:test:PUSCHCodebookType:RetainedProperty', ...
    'Preserve the actual native enum for frozen configuration replay.');
assert(isequal(double(prec.CodebookCatalogValidTPMISet), double(validSet)) && ...
    double(prec.CodebookCatalogNumCandidates) == numel(validSet), ...
    'sixgr:test:PUSCHCodebookType:Catalog', ...
    'Production catalog must use the actual selected type, including sparse table-47 TPMIs.');
assert(isequal(size(prec.MatrixNR), size(expected)) && ...
    norm(double(prec.MatrixNR)-expected, 'fro') <= 1e-12 && ...
    isequal(size(prec.MatrixLogicalPorts), [ports layers]) && ...
    norm(double(prec.MatrixLogicalPorts)-expected.', 'fro') <= 1e-12, ...
    'sixgr:test:PUSCHCodebookType:Matrix', ...
    'Production must use the actual five-argument native matrix and nonconjugating transpose.');
assert(norm(expected*double(prec.MatrixRightInverse)-eye(layers), 'fro') <= 1e-12, ...
    'sixgr:test:PUSCHCodebookType:RightInverse', ...
    'The receiver projection inverse must match the same selected native matrix.');
assert(string(prec.AppliedMatrixSHA256) == ...
    string(sixgr.phy.mimo.MatrixContract.digest(double(prec.MatrixPorts))), ...
    'sixgr:test:PUSCHCodebookType:Digest', ...
    'A retained digest must describe the resolved matrix, not a different family.');
end

function cfg=localArchitectureConfig(ports)
cfg=struct();
if ports~=8
    return; % Preserve the original one/two/four-port fixture semantics.
end
% Use the existing direct high-rank PHY architecture from
% testPUSCHTwoCodewordHARQFacade, not the implicit four-element UE default.
% This declares eight elements/logical ports/RF chains; it does not relax
% strict connected-SRS/DCI capability guards or synthesize an SRS decision.
cfg.phy=struct('ueArray',[8 1 1],'pusch',struct('NumAntennaPorts',8));
arch=sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg,"ue", ...
    "Signal","PUSCH","MinimumPorts",8);
assert(arch.NumElements==8 && arch.NumPorts==8 && arch.NumRFChains==8, ...
    'sixgr:test:PUSCHCodebookType:Architecture', ...
    'Eight-port codebook cases require the declared eight-port UE architecture.');
end

function localNativeInvalidInputs()
% These identifiers are pinned to the installed R2026a validation contract;
% an unrelated missing class/function/license failure is not a rejection.
localMustReject(@() nrPUSCHConfig('CodebookType', 'not_a_native_codebook'), ...
    "MATLAB:nrPUSCHConfig:CodebookType:unrecognizedStringChoice");
localMustReject(@() nrPUSCHConfig('NumLayers', 1.5), "MATLAB:validators:mustBeInteger");
localMustReject(@() nrPUSCHConfig('NumAntennaPorts', 2.5), "MATLAB:validators:mustBeMember");
localMustReject(@() nrPUSCHConfig('TPMI', 0.5), "MATLAB:validators:mustBeInteger");
localMustReject(@() nrPUSCHCodebook(1, 8, 0, false, 'not_a_native_codebook'), ...
    "MATLAB:nrPUSCHCodebook:unrecognizedStringChoice");
localMustReject(@() nrPUSCHCodebook(1.5, 8, 0, false, 'codebook2'), ...
    "MATLAB:nrPUSCHCodebook:expectedInteger");
localMustReject(@() nrPUSCHCodebook(1, 8.5, 0, false, 'codebook2'), ...
    "MATLAB:nrPUSCHCodebook:expectedInteger");
localMustReject(@() nrPUSCHCodebook(1, 8, 0.5, false, 'codebook2'), ...
    "MATLAB:nrPUSCHCodebook:expectedInteger");
end

function localProductionFractionalTPMI()
% Existing production resolver explicitly rejects non-integer TPMI before
% its matrix helper. This does not assert a new contract for helper rounding.
pusch = struct('NumLayers', 1, 'NumAntennaPorts', 2, 'TPMI', 0.5, ...
    'TransmissionScheme', "codebook", 'TransformPrecoding', false, ...
    'CodebookType', "codebook1_ng1n4n1", 'NumCodewords', 1);
try
    sixgr.phy.ul.resolvePUSCHPrecoding(pusch, struct(), 'FixedReferenceMode', true);
catch ME
    assert(strcmp(ME.identifier, 'sixgr:phy:ul:PUSCHPrecoding:BadTPMI'), ...
        'sixgr:test:PUSCHCodebookType:WrongRejection', ...
        'Fractional TPMI must fail the existing input guard, not an unrelated path.');
    return;
end
error('sixgr:test:PUSCHCodebookType:MissingRejection', 'Fractional TPMI was accepted.');
end

function localMustReject(operation, expectedID)
try
    operation();
catch ME
    assert(any(localExceptionIDs(ME) == expectedID), ...
        'sixgr:test:PUSCHCodebookType:WrongNativeRejection', ...
        'Expected native validation %s, observed %s: %s', ...
        char(expectedID), ME.identifier, ME.message);
    return;
end
error('sixgr:test:PUSCHCodebookType:MissingRejection', ...
    'The native configuration/codebook accepted an out-of-domain input.');
end

function identifiers = localExceptionIDs(exception)
identifiers = string(exception.identifier);
for k = 1:numel(exception.cause)
    identifiers = [identifiers; localExceptionIDs(exception.cause{k})]; %#ok<AGROW>
end
end
