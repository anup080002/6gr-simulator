function ok = testPUSCHCodebookCatalogAndHybridElementDomain()
%TESTPUSCHCODEBOOKCATALOGANDHYBRIDELEMENTDOMAIN Validate UL codebook and hybrid waveform contracts.

setup6GRSimToolkit("Verbose", false);
if exist("nrPUSCHCodebook", "file") ~= 2 || exist("nrPUSCH", "file") ~= 2
    ok = true;
    return;
end

expected = [ ...
    1 1 0; ...
    2 1 5; ...
    2 2 2; ...
    4 1 27; ...
    4 2 21; ...
    4 3 6; ...
    4 4 4];

for transformPrecoding = [false true]
    for row = 1:size(expected, 1)
        nPorts = expected(row, 1);
        nLayers = expected(row, 2);
        maxTPMI = expected(row, 3);
        catalog = sixgr.phy.ul.puschCodebookCatalog(nLayers, nPorts, transformPrecoding);
        assert(logical(catalog.Valid), ...
            "PUSCH codebook catalog rejected valid ports=%d layers=%d transform=%d.", ...
            nPorts, nLayers, transformPrecoding);
        assert(isequal(double(catalog.ValidTPMISet), 0:maxTPMI), ...
            "Unexpected TPMI catalog for ports=%d layers=%d transform=%d.", ...
            nPorts, nLayers, transformPrecoding);

        for tpmi = double(catalog.ValidTPMISet)
            [Wlayer, status, Wtx, Winv] = sixgr.phy.ul.puschCodebookProjectionMatrix( ...
                nLayers, nPorts, tpmi, transformPrecoding);
            Wref = nrPUSCHCodebook(nLayers, nPorts, tpmi, transformPrecoding);
            assert(isequal(size(Wtx), [nLayers nPorts]) && isequal(size(Wlayer), [nPorts nLayers]), ...
                "PUSCH codebook matrix shape mismatch for ports=%d layers=%d TPMI=%d.", ...
                nPorts, nLayers, tpmi);
            assert(localMaxAbs(Wtx(:) - Wref(:)) < 1e-12, ...
                "PUSCH codebook matrix must be bit-exact with nrPUSCHCodebook.");
            assert(localMaxAbs(Wlayer(:) - reshape(Wtx.', [], 1)) < 1e-12, ...
                "Wlayer must be the port-by-layer transpose of the Toolbox layer-by-port matrix.");
            assert(localMaxAbs((Wtx * Winv * Wtx) - Wtx) < 1e-12, ...
                "PUSCH codebook right inverse must preserve the codebook row space.");
            assert(contains(string(status), "nr_pusch_"), ...
                "PUSCH codebook status must describe the native NR source.");
        end

        localAssertThrows(@() sixgr.phy.ul.puschCodebookProjectionMatrix( ...
            nLayers, nPorts, maxTPMI + 1, transformPrecoding), ...
            "sixgr:phy:ul:PUSCHCodebookProjection:UnsupportedTPMI");
    end
end

localAssertResolveCatalogEvidence(expected);
localAssertHybridULElementWaveform();
localAssertTransformCodebookWaveform();
ok = true;
end

function localAssertResolveCatalogEvidence(expected)
for row = 1:size(expected, 1)
    nPorts = expected(row, 1);
    nLayers = expected(row, 2);
    maxTPMI = expected(row, 3);
    pusch = struct( ...
        "NumLayers", double(nLayers), ...
        "NumAntennaPorts", double(nPorts), ...
        "TransmissionScheme", "codebook", ...
        "TPMI", double(maxTPMI), ...
        "TransformPrecoding", false, ...
        "NumCodewords", 1);
    prec = sixgr.phy.ul.resolvePUSCHPrecoding(pusch, struct(), "FixedReferenceMode", true);
    assert(prec.NativeCodebookApplied && prec.NumLogicalPorts == nPorts, ...
        "Resolved PUSCH precoder must apply native codebook on logical ports.");
    assert(isequal(double(prec.CodebookCatalogValidTPMISet), 0:maxTPMI), ...
        "Resolved PUSCH precoder must expose the exact valid TPMI catalog.");
    assert(double(prec.CodebookCatalogNumCandidates) == maxTPMI + 1, ...
        "Resolved PUSCH precoder candidate count must match the catalog.");
end
end

function localAssertHybridULElementWaveform()
cfg = sixgr.config.defaultConfig();
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.phy.carrier.NSizeGrid = 18;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.NCellID = 11;
cfg.phy.ueArray = [2 2 1];
cfg.antenna.ue.numElements = 4;
cfg.scenario.ue.nTxAnt = 4;
cfg.phy.pusch.NumAntennaPorts = 2;
cfg.phy.pusch.numPorts = 2;
cfg.phy.pusch.transformPrecoding = false;
cfg.rf.ue.hybridBeamformingEnabled = true;
cfg.rf.ue.numRFChains = 2;

pusch = nrPUSCHConfig;
pusch.NumLayers = 2;
pusch.NumAntennaPorts = 2;
pusch.TransmissionScheme = "codebook";
pusch.TPMI = 0;
pusch.Modulation = "QPSK";
pusch.PRBSet = 0:5;
pusch.SymbolAllocation = [0 14];
pusch.NID = 11;
pusch.RNTI = 401;

tx = sixgr.phy.ul.PUSCH_Tx(cfg, "PUSCH", pusch, "CompactOutput", false);
assert(tx.PrecodeInfo.HybridElementDomainApplied, ...
    "Hybrid UL PUSCH must apply the physical element-domain precoder.");
assert(size(tx.PUSCHPortSymbols, 2) == 2 && size(tx.PUSCHWaveformSymbols, 2) == 4, ...
    "Hybrid UL PUSCH must keep logical-port and element-domain waveform symbols separate.");
H = double(tx.PrecodeInfo.HybridElementToPortMatrix);
expectedWaveformSymbols = tx.PUSCHPortSymbols * H.';
assert(localMaxAbs(tx.PUSCHWaveformSymbols(:) - expectedWaveformSymbols(:)) < 1e-12, ...
    "Hybrid UL PUSCH waveform symbols must equal X_logical*(F_RF*F_BB)'.");
pageEnergy = sum(abs(tx.PUSCHWaveformSymbols).^2, 1);
assert(all(pageEnergy > 0), ...
    "Hybrid UL PUSCH element waveform columns must carry nonzero energy; empty padding is not allowed.");
assert(size(tx.Waveform, 2) == 4 && size(tx.Grid, 3) >= 4, ...
    "Hybrid UL PUSCH must materialize physical UE element waveform columns and grid pages.");
end

function localAssertTransformCodebookWaveform()
cfg = sixgr.config.defaultConfig();
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.phy.carrier.NSizeGrid = 18;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.pusch.NumAntennaPorts = 2;
cfg.phy.pusch.numPorts = 2;
cfg.antenna.ue.numElements = 2;
cfg.scenario.ue.nTxAnt = 2;

pusch = nrPUSCHConfig;
pusch.NumLayers = 1;
pusch.NumAntennaPorts = 2;
pusch.TransmissionScheme = "codebook";
pusch.TransformPrecoding = true;
pusch.TPMI = 1;
pusch.Modulation = "QPSK";
pusch.PRBSet = 0:5;
pusch.SymbolAllocation = [0 14];
pusch.NID = 17;
pusch.RNTI = 402;

tx = sixgr.phy.ul.PUSCH_Tx(cfg, "PUSCH", pusch, "CompactOutput", false);
assert(tx.PrecodeInfo.NativeCodebookApplied && tx.PrecodeInfo.TransformPrecodingApplied, ...
    "Transform-precoded PUSCH codebook must use the native codebook waveform path.");
assert(contains(string(tx.PrecodeInfo.CodebookStatus), "transform_codebook"), ...
    "Transform-codebook status must disclose the transform-precoded catalog path.");
assert(size(tx.PUSCHPortSymbols, 2) == 2 && ~isempty(tx.Waveform), ...
    "Transform-codebook PUSCH must materialize the configured logical antenna ports.");
end

function value = localMaxAbs(x)
if isempty(x)
    value = 0;
else
    value = max(abs(x(:)));
end
end

function localAssertThrows(fh, expectedId)
try
    fh();
catch ME
    assert(strcmp(ME.identifier, expectedId), ...
        "Expected %s, got %s: %s", expectedId, ME.identifier, ME.message);
    return;
end
error("ExpectedException:notThrown", "Expected %s to be thrown.", expectedId);
end
