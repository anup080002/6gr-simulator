function ok=testCSIRSNonoccasionDataCapacity()
% Isolate periodic CSI reservation from waveform, estimator and decoder.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
saved=load(fullfile('docs','lls','evidence_20260913','received_dl_harq_calendar_03','attempt_4.mat'));
[cfg,a,scheduled,periodicity]=localReceiveNonoccasionAssignment(installed,saved);
assert(~scheduled,'test:FixtureMustBeCSIAbsent', ...
    'This captured control assignment must address a configured CSI-RS non-occasion.');
withCSI=sixgr.phy.pdcch.connectedDataAllocation(cfg,a);
disabled=cfg; disabled.phy.csirs.enable=false;
withoutCSI=sixgr.phy.pdcch.connectedDataAllocation(disabled,a);
assert(withCSI.AssignmentDigest==withoutCSI.AssignmentDigest && ...
    isequal(withCSI.Carrier,withoutCSI.Carrier), ...
    'Comparison must retain the same actual received DCI and carrier clock.');
extraHoles=setdiff(double(withCSI.ChannelConfig.ReservedRE(:)), ...
    double(withoutCSI.ChannelConfig.ReservedRE(:)));
fprintf(['CSI_NONOCCASION_CAPACITY slot0=%d calendar=%s scheduled=%d ' ...
    'enabled_G=%d disabled_G=%d extra_reserved_re=%d enabled_TBS=%d disabled_TBS=%d\n'], ...
    a.DataAbsoluteSlot,periodicity,scheduled,withCSI.RateMatchedCapacityBits, ...
    withoutCSI.RateMatchedCapacityBits,numel(extraHoles), ...
    withCSI.NominalTBSBits,withoutCSI.NominalTBSBits);
assert(isempty(extraHoles) && ...
    isequal(withCSI.Indices,withoutCSI.Indices) && ...
    withCSI.RateMatchedCapacityBits==withoutCSI.RateMatchedCapacityBits && ...
    withCSI.NominalTBSBits==withoutCSI.NominalTBSBits, ...
    'sixgr:test:CSIRSNonoccasionCapacityMismatch', ...
    'CSI-RS that is not scheduled must not remove PDSCH REs or change G/TBS.');
ok=true;
end

function [cfg,a,scheduled,periodicity]=localReceiveNonoccasionAssignment(installed,saved)
% Decode a current-context DCI on a legal DL monitoring slot whose PDSCH is
% outside the periodic CSI-RS calendar. Do not mutate an archived assignment
% digest or reinterpret a CSI-present waveform as a non-occasion.
base=double(saved.a.ControlAbsoluteSlot);
for delta=1:20
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,base+delta+1);
    try
        context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
        definitions=sixgr.phy.pdcch.DCISchemaEngine.resolve(context).Definitions;
        fields=struct();
        for definition=definitions(:).'
            fields.(definition.Name)=saved.control.DecodedDCI.Fields.(definition.Name);
        end
        packed=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
        tx=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',packed.Bits, ...
            'RNTI',cfg.phy.pdsch.RNTI);
        [decoded,info]=sixgr.phy.dl.PDCCH_Rx(tx.TransmitSamples,cfg, ...
            'SampleRate_Hz',tx.SampleRateHz);
        a=sixgr.phy.pdcch.materializeConnectedDCI(decoded,info,cfg);
        [scheduled,periodicity]=sixgr.phy.refsig.csirsOccasion(cfg,a.DataAbsoluteSlot);
        if ~scheduled
            return;
        end
    catch
        % Try the next installed monitoring occasion; no assignment is
        % accepted unless the complete physical PDCCH chain succeeds.
    end
end
error('test:MissingCurrentCSIAbsentAssignment', ...
    'No current-context received DL assignment addressed a CSI-RS non-occasion.');
end
