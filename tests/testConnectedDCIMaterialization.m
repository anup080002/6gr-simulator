function ok=testConnectedDCIMaterialization()
% Coded received control -> semantic capsule -> scalar CSV roundtrip.
% This is not data-receiver integration or full-run qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,31);
rows=repmat(sixgr.truth.connectedDCIAssignmentEvidence(struct()),0,1);
for singleEntry=[false true]
    selected=cfg;
    if singleEntry
        selected.phy.pdsch.timeDomainAllocations=cfg.phy.pdsch.timeDomainAllocations(1,:);
        selected.phy.pusch.timeDomainAllocations=cfg.phy.pusch.timeDomainAllocations(1,:);
        selected.phy.pucch.dlDataToULACK=cfg.phy.pucch.dlDataToULACK(end);
    end
    for fmt=["0_1","1_1"]
        context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(selected,fmt);
        schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
        fields=struct();
        for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
        fields.mcs=10; fields.ndi=1; fields.dmrs_sequence_initialization=1;
        fields.antenna_ports=3;
        if fmt=="0_1"
            fields.precoding_information_and_number_of_layers=3;
        else
            % DL table -1 codepoint 4 and UL table -8 codepoint 3 both
            % indicate port 1 with two CDM groups; their indices differ.
            fields.antenna_ports=4;
            fields.transmission_configuration_indication=5;
            if ~singleEntry
                fields.pdsch_to_harq_feedback_timing=numel(selected.phy.pucch.dlDataToULACK)-1;
            end
        end
        authored=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
        p=sixgr.link.preparePDCCHTransmission(selected,'DCIBits',authored.Bits,'RNTI',selected.phy.pdsch.RNTI);
        [rx,info]=sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,selected,'SampleRate_Hz',p.SampleRateHz);
        a=sixgr.phy.pdcch.materializeConnectedDCI(rx,info,selected);
        assert(a.NSCID==1 && isequal(a.DMRSPortSet,1) && a.NumCDMGroupsWithoutData==2 && ...
            a.NumLayers==1 && a.ControlAbsoluteSlot==30 && a.TimeDomainAssignmentIndex==0 && ...
            a.MCS==10 && ~a.ExecutionQualified && ~isfield(a,'TBSBits'), ...
            'Unexpected received reference capsule: %s',jsonencode(a));
        if fmt=="0_1"
            assert(a.TPMI==3 && a.SRSResourceIndex==0 && a.ULSCHIndicator==1 && ...
                a.SRSResourceSelectionSource=="implicit_single_configured_resource" && a.DataAbsoluteSlot==31);
        else
            assert(a.K1Slots==selected.phy.pucch.dlDataToULACK(end) && a.TCICodepoint==5 && ...
                a.HARQFeedbackAbsoluteSlot==a.DataAbsoluteSlot+a.K1Slots);
        end
        % Authored waveform settings and scoring bits are not RX authority.
        changed=selected; changed.phy.pdsch.mcs=1; changed.phy.pusch.mcs=1;
        changed.phy.pdsch.dmrs.NSCID=0; changed.phy.pusch.dmrs.NSCID=0;
        changed.phy.pusch.TPMI=0;
        changed.ConfiguredOracleGrant=struct('MCS',31,'TPMI',0,'TCI',0,'K1',99);
        diagnostic=info; diagnostic.ExpectedDCIBits=int8(zeros(3,1));
        again=sixgr.phy.pdcch.materializeConnectedDCI(rx,diagnostic,changed);
        assert(again.AssignmentDigest==a.AssignmentDigest);
        for name={'pdsch','pusch'}
            stale=selected; root=name{1}; replacement="qam256_table2";
            if string(stale.phy.(root).mcsTable)==replacement, replacement="qam64_table1"; end
            stale.phy.(root).mcsTable=char(replacement);
            localReject(@()sixgr.phy.pdcch.materializeConnectedDCI(rx,info,stale), ...
                'sixgr:phy:pdcch:stale_bwp_context');
        end
        corrupted=rx; corrupted.DecodedDCI.Fields.dmrs_sequence_initialization=0;
        localReject(@()sixgr.phy.pdcch.materializeConnectedDCI(corrupted,info,selected), ...
            'sixgr:phy:pdcch:ReceivedSemanticMismatch');
        failed=rx; failed.Ok=false;
        localReject(@()sixgr.phy.pdcch.materializeConnectedDCI(failed,info,selected), ...
            'sixgr:phy:pdcch:ConnectedReceptionRequired');
        wrong=info; wrong.RNTI=info.RNTI+1;
        localReject(@()sixgr.phy.pdcch.materializeConnectedDCI(rx,wrong,selected), ...
            'sixgr:phy:pdcch:stale_bwp_context');
        future=selected; future.lls6g.runtime.AbsoluteSlotIndex0=31;
        localReject(@()sixgr.phy.pdcch.materializeConnectedDCI(rx,info,future), ...
            'sixgr:phy:pdcch:ReceivedClockMismatch');
        evidence=sixgr.truth.connectedDCIAssignmentEvidence(a);
        assert(evidence.DecodedDCIAssignmentAvailable && evidence.DecodedDCINSCID==1 && ...
            isequal(jsondecode(evidence.DecodedDCIDMRSPortSet),1) && ...
            evidence.DecodedDCIConfigurationEpoch==context.Data.ConfigurationEpoch);
        rows(end+1,1)=evidence; %#ok<AGROW>
    end
end
path=[tempname '.csv']; writetable(struct2table(rows),path);
readback=readtable(path,'TextType','string');
assert(height(readback)==4 && all(readback.DecodedDCINSCID==1) && ...
    all(readback.DecodedDCIAssignmentAvailable) && ...
    all(strlength(readback.DecodedDCIAssignmentDigest)==64));
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
