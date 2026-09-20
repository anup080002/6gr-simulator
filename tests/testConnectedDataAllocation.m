function ok=testConnectedDataAllocation()
% Actual coded control/data fixtures. This is not shared-scheduler qualification.
setup6GRSimToolkit('Verbose',false); rng(90129,'twister');
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
installed=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,31);
for fmt=["0_1","1_1"]
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(installed,fmt);
    schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context); f=struct();
    for def=schema.Definitions(:).', f.(def.Name)=def.ValueMin; end
    f.frequency_resource_assignment=installed.phy.carrier.NSizeGrid*5+3; % Six RBs, start 3.
    f.mcs=10; f.ndi=1; f.dmrs_sequence_initialization=1;
    f.antenna_ports=4;
    if fmt=="0_1", f.antenna_ports=3; f.precoding_information_and_number_of_layers=3; end
    dci=sixgr.phy.pdcch.DCIPacker.pack(f,context);
    p=sixgr.link.preparePDCCHTransmission(installed,'DCIBits',dci.Bits,'RNTI',installed.phy.pdsch.RNTI);
    [control,info]=sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,installed,'SampleRate_Hz',p.SampleRateHz);
    a=sixgr.phy.pdcch.materializeConnectedDCI(control,info,installed);
    allocation=sixgr.phy.pdcch.connectedDataAllocation(installed,a);
    assert(isequal(allocation.ChannelConfig.PRBSet,3:8) && allocation.ChannelConfig.DMRS.NSCID==1 && ...
        isequal(allocation.ChannelConfig.DMRS.DMRSPortSet,1) && allocation.NominalTBSBits>0);
    % gNB endpoint uses its independently scheduled values. It must not
    % learn the UE's decoded payload through a simulator side channel.
    name='pdsch'; if fmt=="0_1", name='pusch'; end
    tdra=context.Data.DLTimeDomainAllocations;
    if fmt=="0_1", tdra=context.Data.ULTimeDomainAllocations; end
    scheduled=tdra(tdra(:,1)==0,:);
    assert(size(scheduled,1)==1);
    gnb=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,31+scheduled(4));
    profile=sixgr.link.resolveMCSProfile(gnb.phy.(name).mcsTable,10);
    gnb.phy.(name).prbSet=3:8;
    gnb.phy.(name).symbolAllocation=scheduled(2:3);
    gnb.phy.(name).mcsIndex=10;
    gnb.phy.(name).modulation=char(profile.Modulation);
    gnb.phy.(name).codeRate=profile.TargetCodeRate;
    gnb.phy.(name).rv=0;
    gnb.phy.(name).dmrs.NSCID=1;
    gnb.phy.(name).dmrs.scheduledPortSet=1;
    gnb.phy.(name).dmrs.portSet=1;
    gnb.phy.(name).dmrs.numCDMGroupsWithoutData=2;
    if fmt=="0_1"
        gnb.phy.pusch.TPMI=3; gnb.phy.pusch.PMI=3;
        command=sixgr.phy.ul.resolvePUSCHPrecoding(allocation.ChannelConfig,allocation.Config);
        assert(command.AuthoritativeDCIDecisionUsed && ~command.AuthoritativeSRSDecisionUsed && ...
            command.PMI==3 && command.Source=="ul_pusch_native_codebook_received_dci");
        wrong=allocation.ChannelConfig; wrong.TPMI=0;
        localReject(@()sixgr.phy.ul.resolvePUSCHPrecoding(wrong,allocation.Config), ...
            'sixgr:phy:ul:ReceivedPrecodingMismatch');
        wrong.TPMI=3;
        wrong.TransformPrecoding=true;
        localReject(@()sixgr.phy.ul.resolvePUSCHPrecoding(wrong,allocation.Config), ...
            'sixgr:phy:ul:ReceivedPrecodingMismatch');
        wrong.TransformPrecoding=false;
        wrong.TransmissionScheme='nonCodebook';
        localReject(@()sixgr.phy.ul.resolvePUSCHPrecoding(wrong,allocation.Config), ...
            'sixgr:phy:ul:ReceivedPrecodingMismatch');
        wrong.TransmissionScheme='codebook';
        stale=sixgr.phy.grid.applyRuntimeCarrierTimeline(allocation.Config,a.DataAbsoluteSlot+2);
        localReject(@()sixgr.phy.ul.resolvePUSCHPrecoding(wrong,stale), ...
            'sixgr:phy:ul:ReceivedPrecodingMismatch');
        missing=allocation.Config; missing.phy.pusch=rmfield(missing.phy.pusch,'receivedDCIAssignment');
        localReject(@()sixgr.phy.ul.resolvePUSCHPrecoding(allocation.ChannelConfig,missing), ...
            'sixgr:mimo:MissingSRSState');
        bits=int8(randi([0 1],allocation.NominalTBSBits,1));
        tx=sixgr.link.transmitReceivedPUSCH(installed,a,bits,[]);
        assert(tx.TransmissionAuthority=="received_dci_and_ue_new_tb_payload");
        localReject(@()sixgr.link.transmitReceivedPUSCH(installed,a,bits(2:end),[]), ...
            'sixgr:link:ReceivedULTBSizeMismatch');
    else
        % Explicit TX-only unit-channel fixture matrix; not a measured PMI.
        % The independent UE receiver estimates the effective channel.
        gnb.phy.pdsch.precoding.matrix=[1;0];
        gnb.phy.pdsch.normalizePrecodingMatrix=false;
        gnb.phy.pdsch.selectedPrecoderSHA256= ...
            sixgr.phy.mimo.MatrixContract.digest(gnb.phy.pdsch.precoding.matrix);
        tx=sixgr.phy.dl.PDSCH_Tx(gnb,'ExecutionProfile','phy_calibration');
    end
    nfft=nrOFDMInfo(allocation.Carrier).Nfft;
    noise=10^(-35/10)/nfft;
    wave=tx.Waveform+sqrt(noise/2)*complex(randn(size(tx.Waveform)),randn(size(tx.Waveform)));
    if fmt=="0_1"
        % No TX object, indices, TBS or coding layout enters gNB reception.
        rx=sixgr.phy.ul.PUSCH_Rx(wave,gnb,'NoiseVar',noise,'NoiseVarDomain','time');
    else
        % Build a NEW-TB plan from independent receive allocation, not TX.
        plan=sixgr.pdsch.DLSCHCodingPlan.resolve( ...
            'TransportBlockSize',allocation.NominalTBSBits,'TargetCodeRate',a.TargetCodeRate, ...
            'RateMatchedBitCount',allocation.RateMatchedCapacityBits,'RV',a.RV, ...
            'Modulation',a.Modulation,'NumLayers',a.NumLayers);
        rx=sixgr.phy.dl.PDSCH_Rx(wave,allocation.Config, ...
            'ExecutionProfile','phy_calibration','CodingPlan',plan, ...
            'NoiseVar',noise,'NoiseVarDomain','time');
        assert(rx.PrecodeInfo.ReceiverOnly && ~rx.PrecodeInfo.AppliedPrecoderAvailable && ...
            isempty(rx.PrecodeInfo.MatrixPorts));
        % Production typed receiver assignment comes from the actual
        % decoded capsule, not a cloned calibration/scheduled assignment.
        bundle=sixgr.pdsch.PDSCHCalibrationFacadeAdapter.materializeReceivedNewTB( ...
            installed,a,1,size(wave,2));
        typed=sixgr.pdsch.PDSCHReceiver(wave,bundle.Assignment,bundle.ResourcePlan, ...
            bundle.Carrier,bundle.ReferenceConfig,bundle.ReceiverConfig, ...
            'CodingPlans',bundle.CodingPlans,'IntegrationContext',bundle.IntegrationContext);
        assert(typed.CRCPass && isequal(typed.TransportBlock,tx.TransportBlock) && ...
            bundle.Assignment.Profile=="connected_strict" && ...
            bundle.Assignment.get('ControlAuthority')=="receiver_crc_valid_decode" && ...
            bundle.Assignment.get('ReceivedAssignmentDigest')==a.AssignmentDigest && ...
            bundle.Assignment.get('MCSIndexPerCodeword')==a.MCS && ...
            bundle.Assignment.get('HARQProcessId')==a.HARQProcess && ...
            bundle.Assignment.get('TCIStateId')==installed.phy.pdsch.qclTCI.state_id && ...
            bundle.Assignment.get('TransmissionConfigurationIndication')==a.TCICodepoint && ...
            bundle.Assignment.get('DAI')==a.Fields.dai && ...
            bundle.Assignment.get('PDSCHAbsoluteSlot')==a.DataAbsoluteSlot && ...
            isempty(bundle.PrecoderBundle) && isempty(bundle.TransportBlocks{1}) && ...
            ~isfield(bundle.ReceiverConfig,'NoiseVariance') && ...
            typed.IntegrationBinding.PrecoderBinding.Status=="NOT_EVALUATED");
        assert(bundle.Source=="received_connected_dci_to_canonical_receiver_assignment");
        % Same waveform through the strict compatibility entry point and
        % its measured native-clock capture-acquisition branch.
        strictArgs={'ExecutionProfile','connected_strict','Assignment',bundle.Assignment, ...
            'ResourcePlan',bundle.ResourcePlan,'Carrier',bundle.Carrier, ...
            'ReferenceSignalConfig',bundle.ReferenceConfig,'ReceiverConfig',bundle.ReceiverConfig, ...
            'CodingPlan',bundle.CodingPlans,'IntegrationContext',bundle.IntegrationContext};
        delayed=[complex(zeros(43,size(wave,2)));wave;complex(zeros(17,size(wave,2)))];
        strictRX=sixgr.phy.dl.PDSCH_Rx(delayed,allocation.Config,strictArgs{:}, ...
            'TimingSearchWindowSamples',[0 60]);
        assert(strictRX.CRCPass && isequal(strictRX.TransportBlock,tx.TransportBlock) && ...
            strictRX.TimingOffset==43 && ~strictRX.ReceiveTiming.OracleTimingUsed);
        bad=installed; bad.phy.pdsch.qclTCI.codepoint=7;
        localReject(@()sixgr.pdsch.PDSCHCalibrationFacadeAdapter.materializeReceivedNewTB( ...
            bad,a,1,size(wave,2)),'sixgr:pdsch:ReceivedTCIMappingUnavailable');
        bad=installed; bad.phy.pdsch.qclTCI.activation_absolute_slot0=a.ControlAbsoluteSlot+1;
        localReject(@()sixgr.pdsch.PDSCHCalibrationFacadeAdapter.materializeReceivedNewTB( ...
            bad,a,1,size(wave,2)),'sixgr:pdsch:ReceivedTCIMappingUnavailable');
        fprintf('RECEIVED_TYPED_DL_PASS tbs=%d measured_delay=%d tci_state=%d codepoint=%d\n', ...
            numel(typed.TransportBlock),strictRX.TimingOffset,bundle.Assignment.get('TCIStateId'),a.TCICodepoint);
        poisoned=installed;
        poisoned.phy.pdsch.mcsIndexPerCodeword=0;
        poisoned.phy.pdsch.mcsTablePerCodeword='qam256_table2';
        poisonBundle=sixgr.pdsch.PDSCHCalibrationFacadeAdapter.materializeReceivedNewTB( ...
            poisoned,a,1,size(wave,2));
        assert(poisonBundle.Assignment.ExecutionValidationDigest==bundle.Assignment.ExecutionValidationDigest && ...
            string(poisonBundle.CodingPlans{1}.PlanID)==string(bundle.CodingPlans{1}.PlanID), ...
            'Bootstrap MCS compatibility aliases must not override received DCI.');
        poisoned.phy.pdsch.mcsTable='qam256_table2';
        localReject(@()sixgr.phy.pdcch.connectedDataAllocation(poisoned,a), ...
            'sixgr:phy:pdcch:stale_bwp_context');
        wrong=allocation.Config; wrong.phy.pdsch.dmrs.NSCID=0;
        localReject(@()sixgr.phy.dl.PDSCH_Rx(wave,wrong, ...
            'ExecutionProfile','phy_calibration','CodingPlan',plan, ...
            'NoiseVar',noise,'NoiseVarDomain','time'), ...
            'sixgr:pdsch:ReceivedAssignmentMismatch');
    end
    assert(rx.Ok && isequal(rx.TransportBlock,tx.TransportBlock), ...
        'Independent %s allocation/coding reception failed.',fmt);
    assert(allocation.NominalTBSBits==tx.TransportBlockSize);
    fprintf('CONNECTED_DATA_ALLOCATION_PASS format=%s tbs=%d nscid=1 port=1\n',fmt,allocation.NominalTBSBits);
    mutated=a; mutated.NSCID=0;
    localReject(@()sixgr.phy.pdcch.connectedDataAllocation(installed,mutated), ...
        'sixgr:phy:pdcch:ReceivedAssignmentDigestMismatch');
end
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
