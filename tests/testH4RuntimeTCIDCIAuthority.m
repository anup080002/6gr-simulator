function ok = testH4RuntimeTCIDCIAuthority()
%TESTH4RUNTIMETCIDCIAUTHORITY DCI follows the measured per-UE TCI state.

setup6GRSimToolkit('Verbose', false);
scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
    'simulator','configs','scenarios', ...
    'h4_100_cdlc100_connected_impaired_40db_gate.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(scenario, tempname);
cfg.phy.beamManagement.selectedCRI = 2;
cfg.phy.csi.selectedCRI = 2;
% One-based slot 21 is the first connected DL data occasion in the retained
% gate.  It is a full-DL slot without SS/PBCH overlap.
grant = sixgr.link.resolveWaveformGrant(cfg, 'DL', 21);
assert(grant.Valid && grant.PHYGrant.IsFrozen && ...
    double(grant.DCI.ContextData.ActiveTCIStateID) == 17);

% SSB index 1 maps to initial CSI-RS resource 2 and therefore to the
% installed H4 TCI state/codepoint 18/2.  Model the causal per-UE binding
% produced by CoupledTruthRuntime.applyUserContext without consulting
% transmitted data or decoded UE payload bits.
activeCfg = cfg;
activeCfg.phy.beamManagement.selectedCRI = 2;
activeCfg.phy.csi.selectedCRI = 2;
qcl = activeCfg.phy.pdsch.qclTCI;
qcl.state_id = 18;
qcl.codepoint = 2;
qcl.activation_absolute_slot0 = max(0, double(grant.Slot) - 1);
qcl.spatial_source_resource_id = 2;
qcl.spatial_source_reference_signal = 'NZP-CSI-RS';
qcl.initialization_source = ...
    'runtime_received_measurement_and_decoded_tci';
activeCfg.phy.pdsch.qclTCI = qcl;
activeCfg.phy.pdsch.activeTCIStateID = 18;
activeCfg = sixgr.phy.grid.applyRuntimeCarrierTimeline( ...
    activeCfg, double(grant.ScheduledAbsoluteSlot) + 1);

scheduler = sixgr.l2.mac.SchedulerPF(cfg, 'Direction','DL');
stale = grant;
request = localRequestFromGrant(activeCfg, grant);
frozenCfg = sixgr.phy.grant.applyPHYGrantToConfig(activeCfg, grant.PHYGrant);
localReject(@()sixgr.pdsch.bindSchedulerPDSCHTransmitContext( ...
    request, frozenCfg, stale, double(grant.ScheduledAbsoluteSlot), ...
    grant.PHYGrant), 'sixgr:pdsch:StaleAuthoredSchedulerDCIContext');

grant.DCI = scheduler.buildDCIBitfield(grant, activeCfg);
assert(double(grant.DCI.ContextData.ActiveTCIStateID) == 18);
decoded = sixgr.phy.pdcch.decodeDCIPayload( ...
    grant.DCI.Bits, grant.DCI.Format, grant.DCI.ContextData);
assert(double(decoded.Fields.transmission_configuration_indication) == 2);
bound = sixgr.pdsch.bindSchedulerPDSCHTransmitContext( ...
    request, frozenCfg, grant, double(grant.ScheduledAbsoluteSlot), ...
    grant.PHYGrant);
assert(double(bound.ConfigurationEpoch) == ...
    double(grant.DCI.ContextData.ConfigurationEpoch));

% Exact retained-run transition: the delivered CSI report selected CRI 1
% before the first connected DCI.  CRI 1 maps to state 17/codepoint 1, so
% both the frozen PDSCH precoder and its authored TCI indication must be
% produced from that same active configuration.
refinedCfg = cfg;
refinedCfg.phy.beamManagement.selectedCRI = 1;
refinedCfg.phy.csi.selectedCRI = 1;
refinedQCL = refinedCfg.phy.pdsch.qclTCI;
refinedQCL.state_id = 17;
refinedQCL.codepoint = 1;
refinedQCL.activation_absolute_slot0 = 20;
refinedQCL.spatial_source_resource_id = 1;
refinedQCL.spatial_source_reference_signal = 'NZP-CSI-RS';
refinedQCL.initialization_source = ...
    'runtime_received_measurement_and_decoded_tci';
refinedCfg.phy.pdsch.qclTCI = refinedQCL;
refinedCfg.phy.pdsch.activeTCIStateID = 17;
refinedGrant = sixgr.link.resolveWaveformGrant(refinedCfg, 'DL', 21);
refinedCfg = sixgr.phy.grid.applyRuntimeCarrierTimeline( ...
    refinedCfg, double(refinedGrant.ScheduledAbsoluteSlot) + 1);
refinedGrant.DCI = scheduler.buildDCIBitfield(refinedGrant, refinedCfg);
refinedDecoded = sixgr.phy.pdcch.decodeDCIPayload( ...
    refinedGrant.DCI.Bits, refinedGrant.DCI.Format, ...
    refinedGrant.DCI.ContextData);
assert(double(refinedGrant.DCI.ContextData.ActiveTCIStateID) == 17 && ...
    double(refinedDecoded.Fields.transmission_configuration_indication) == 1);
[refinedTX, ~] = sixgr.phy.dl.PDSCH_Tx(refinedCfg, ...
    'PHYGrant',refinedGrant.PHYGrant, ...
    'SchedulerGrantContext',refinedGrant, ...
    'CompactOutput',true);
assert(~isempty(refinedTX.Waveform) && ...
    double(refinedTX.Assignment.get('NumLayers')) == ...
        double(refinedGrant.NumLayers));
ok = true;
disp('PASS testH4RuntimeTCIDCIAuthority: measured TCI context owns authored DCI.');
end

function request = localRequestFromGrant(cfg, grant)
[tx, ~] = sixgr.phy.dl.PDSCH_Tx(cfg, ...
    'PHYGrant',grant.PHYGrant, ...
    'SchedulerGrantContext',localReauthor(grant,cfg), ...
    'CompactOutput',false);
request = tx.Assignment.toStruct();
end

function grant = localReauthor(grant, cfg)
scheduler = sixgr.l2.mac.SchedulerPF(cfg, 'Direction','DL');
grant.DCI = scheduler.buildDCIBitfield(grant, cfg);
end

function localReject(call, identifier)
try
    call();
catch cause
    assert(strcmp(cause.identifier, identifier), ...
        'Expected %s, got %s: %s', identifier, cause.identifier, cause.message);
    assert(contains(string(cause.message), 'ActiveTCIStateID'), ...
        'The rejection must identify the stale TCI context field.');
    return;
end
error('TEST:MissingRejection','Expected %s.',identifier);
end
