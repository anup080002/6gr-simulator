function ok = testCSIRSPhysicalRuntimePortProjection()
%TESTCSIRSPHYSICALRUNTIMEPORTPROJECTION Exercise all configured elements.

setup6GRSimToolkit("Verbose", false);
cfg = localConfig();
codebook = sixgr.rf.AntennaArrayFactory.dftCodebookURA(2, 2, 2, 2);
cfg.phy.csirs.precoderMatrices = codebook(:, [1 2]);
cfg.phy.csirs.precoderDigests = ...
    sixgr.phy.mimo.MatrixContract.digest(cfg.phy.csirs.precoderMatrices);
cfg.phy.csirs.precoderBeamIndices = [0 1];

[tx, info] = sixgr.phy.dl.PDSCH_Tx(cfg, ...
    "PrecodingMatrix", eye(2), "CompactOutput", false);
event = tx.CSIRSRuntimeEvent;
resource = event.ResourceEvents(1);
assert(size(tx.Grid, 3) == 2 && double(event.WaveformPortCount) == 2, ...
    "The focused fixture must retain two logical waveform ports.");
assert(double(event.PhysicalPortCount) == 4 && ...
    double(resource.PhysicalPortCount) == 4, ...
    "CSI-RS evidence must retain all four configured physical elements.");
assert(string(event.RuntimeMaterializationStatus) == ...
    "physical_element_precoder_exact_runtime_port_projection_mapping", ...
    "Projected CSI-RS must disclose the logical/physical domain boundary.");
assert(double(resource.PortProjectionResidual) < 1e-12 && ...
    strlength(string(resource.WaveformPrecoderDigest)) == 64 && ...
    strlength(string(resource.PortToElementMatrixDigest)) == 64, ...
    "CSI-RS projection must be exact and independently hash-auditable.");

arch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg, "bs", ...
    "Signal", "PDSCH", "NumElements", 4, "NumPorts", 2, ...
    "MinimumPorts", 2);
assert(all(sum(abs(arch.PortToElementMatrix), 2) > 0) && ...
    norm(arch.PortToElementMatrix' * arch.PortToElementMatrix - eye(2), "fro") < 1e-12, ...
    "Four-element/two-port projection must energize every element and preserve power.");
Wphysical = cfg.phy.csirs.precoderMatrices;
Wwaveform = arch.PortToElementMatrix' * Wphysical;
assert(norm(arch.PortToElementMatrix * Wwaveform - Wphysical, "fro") < 1e-12, ...
    "Runtime antenna projection must reconstruct the YAML physical CSI-RS beams exactly.");
assert(string(info.CSIRSRuntimeEvent.PrecoderSource) == ...
    "yaml_dft_ura_physical_csirs_resource_filter_via_runtime_port_projection", ...
    "Tx info must preserve the physical CSI-RS precoder authority.");

observedUE1 = sixgr.truth.buildObservedREAllocation(tx, ...
    "Direction", "DL", "AbsoluteSlot", 0, "CellID", 1, ...
    "UEID", 1, "AllocationID", "pdsch_slot_0_ue_1");
observedUE2 = sixgr.truth.buildObservedREAllocation(tx, ...
    "Direction", "DL", "AbsoluteSlot", 0, "CellID", 1, ...
    "UEID", 2, "AllocationID", "pdsch_slot_0_ue_2");
csi1 = observedUE1(string(observedUE1.component) == "CSI-RS", :);
csi2 = observedUE2(string(observedUE2.component) == "CSI-RS", :);
assert(~isempty(csi1) && ~isempty(csi2) && ...
    all(string(csi1.channel) == "CSI-RS") && ...
    all(isnan(double(csi1.ue_id))) && all(isnan(double(csi1.layer_count))) && ...
    all(string(csi1.allocation_id) == "csirs_cell_1_slot_0"), ...
    "Cell CSI-RS occupancy must not inherit a PDSCH grant's UE/layer identity.");
[canonicalCSI, removedCSI] = sixgr.truth.deduplicateObservedREAllocation([csi1; csi2]);
assert(removedCSI == height(csi1) && height(canonicalCSI) == height(csi1), ...
    "One executed cell CSI-RS resource must canonicalize once across per-UE PDSCH observations.");

cfgBad = cfg;
cfgBad.phy.csirs.precoderMatrices = codebook(:, [1 3]);
localAssertThrows(@() sixgr.phy.dl.PDSCH_Tx(cfgBad, ...
    "PrecodingMatrix", eye(2), "CompactOutput", false), ...
    "sixgr:pdsch:CSIRSPrecoderOutsideRuntimePortSubspace");

% The production 64-RF-unit case must not use the two-port projection at
% all.  Materialize the same PDSCH/CSI-RS path on the exact 64-element
% waveform domain and verify that the requested DFT beams are transmitted
% unchanged.
cfg64 = localConfig();
cfg64.phy.bsArray = [8 8 1];
cfg64.phy.nTxAnt = 64;
cfg64.channel.nTxAnt = 64;
cfg64.scenario.bs.nTxAnt = 64;
cfg64.antenna.bs.numElements = 64;
cfg64.antenna.bs.numRFChains = 64;
cfg64.antenna.bs.numTxRFChains = 64;
cfg64.rf.bs.numRFChains = 64;
cfg64.phy.beamManagement.hybridBeamformingEnabled = true;
codebook64 = sixgr.rf.AntennaArrayFactory.dftCodebookURA(8, 8, 8, 8);
cfg64.phy.csirs.precoderMatrices = codebook64(:, [1 2]);
cfg64.phy.csirs.precoderDigests = ...
    sixgr.phy.mimo.MatrixContract.digest(cfg64.phy.csirs.precoderMatrices);
cfg64.phy.csirs.precoderBeamIndices = [0 1];
[tx64, info64] = sixgr.phy.dl.PDSCH_Tx(cfg64, ...
    "PrecodingMatrix", eye(2), "CompactOutput", false);
event64 = tx64.CSIRSRuntimeEvent;
resource64 = event64.ResourceEvents(1);
assert(size(tx64.Grid, 3) == 64 && size(tx64.Waveform, 2) == 64 && ...
    double(event64.PhysicalPortCount) == 64 && ...
    double(event64.WaveformPortCount) == 64, ...
    "The 64-RF-unit PDSCH/CSI-RS chain must execute all 64 physical elements.");
assert(string(event64.RuntimeMaterializationStatus) == ...
    "physical_element_domain_csirs_resource_set_mapping" && ...
    double(resource64.PortProjectionResidual) == 0 && ...
    string(resource64.PrecoderDigest) == ...
        sixgr.phy.mimo.MatrixContract.digest(codebook64(:, [1 2])) && ...
    string(resource64.WaveformPrecoderDigest) == ...
        string(resource64.PrecoderDigest), ...
    "Element-domain CSI-RS must preserve the exact requested DFT precoder identity.");
assert(string(info64.CSIRSRuntimeEvent.PrecoderSource) == ...
    "yaml_dft_ura_physical_csirs_resource_filter_via_runtime_port_projection", ...
    "Tx evidence must retain YAML physical-codebook authority on the direct element-domain path.");
ok = true;
end

function cfg = localConfig()
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.pdschExecutionProfile = "phy_calibration";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.bsArray = [2 2 1];
cfg.phy.nTxAnt = 4;
cfg.channel.nTxAnt = 4;
cfg.scenario.bs.nTxAnt = 4;
cfg.antenna.bs.numElements = 4;
cfg.antenna.bs.numRFChains = 4;
cfg.antenna.bs.numTxRFChains = 4;
cfg.rf.bs.numRFChains = 4;
cfg.phy.pdsch.enable = true;
cfg.phy.pdsch.prbSet = 0:11;
cfg.phy.pdsch.symbolAllocation = [2 12];
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.3;
cfg.phy.pdsch.mcsTable = "calibration_explicit";
cfg.phy.pdsch.mcsIndex = 0;
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.phy.pdsch.mcsContext = struct( ...
    "UECapability1024QAM", false, "RRCEnabled1024QAM", false, ...
    "DCIEnabled1024QAM", false, "DeploymentAllows1024QAM", false, ...
    "FrequencyRangeAllows1024QAM", false, "BandAllows1024QAM", false, ...
    "FrequencyRange", "FR1", "OperatingBand", "n78", ...
    "DeploymentClass", "controlled_test");
cfg.phy.pdsch.nLayers = 2;
cfg.phy.pdsch.numLayers = 2;
cfg.phy.pdsch.numPorts = 2;
cfg.phy.pdsch.nPorts = 2;
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.csirs.enable = true;
cfg.phy.csirs.period_slots = 1;
cfg.phy.csirs.offset_slots = 0;
cfg.phy.csirs.nPorts = 2;
cfg.phy.csirs.numResources = 1;
cfg.phy.csirs.resourceID = 0;
cfg.phy.csirs.resourceIDs = 0;
cfg.phy.csirs.rowNumber = 3;
cfg.phy.csirs.rowNumbers = 3;
cfg.phy.csirs.symbolLocations = 10;
cfg.phy.csirs.symbolLocationsByResource = 10;
cfg.phy.csirs.subcarrierLocations = 0;
cfg.phy.csirs.subcarrierLocationsByResource = 0;
cfg.phy.csirs.rbOffset = 0;
cfg.phy.csirs.rbOffsetsByResource = 0;
cfg.phy.csirs.numRB = 12;
cfg.phy.csirs.numRBsByResource = 12;
cfg.phy.csirs.precoderCodebookType = "dft_ura";
end

function localAssertThrows(fh, expectedIdentifier)
try
    fh();
catch ME
    assert(strcmp(ME.identifier, expectedIdentifier), ...
        "Expected %s, got %s: %s", expectedIdentifier, ME.identifier, ME.message);
    return;
end
error("testCSIRSPhysicalRuntimePortProjection:MissingFailure", ...
    "Expected %s to be thrown.", expectedIdentifier);
end
