function ok=testReceivedDLHARQState()
% Actual coded control and waveforms; isolated UE endpoint, not full scheduler.
setup6GRSimToolkit('Verbose',false); rng(90213,'twister');
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
entity=sixgr.link.ReceivedDLHARQState(installed,1);
initial=sixgr.link.resolveMCSProfile(installed.phy.pdsch.mcsTable,10);
outputRoot=tempname; mkdir(outputRoot);
fprintf('RECEIVED_DL_HARQ_OUTPUT=%s\n',outputRoot);
bits=[]; rows=table();
for k=1:4
    % Use DL slot index 2 within each TDD period, outside the periodic
    % two-slot SS/PBCH burst. Resource-collision guards remain enabled.
    slot=33+10*(k-1); ndi=1; mcs=10; nprb=6; rv=0;
    if k==2 || k==3, mcs=31; nprb=8; rv=2; end
    if k==4, ndi=0; end
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,slot);
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
    defs=sixgr.phy.pdcch.DCISchemaEngine.resolve(context).Definitions;
    f=struct(); for d=defs(:).', f.(d.Name)=d.ValueMin; end
    f.frequency_resource_assignment=cfg.phy.carrier.NSizeGrid*(nprb-1)+3;
    f.mcs=mcs; f.rv=rv; f.ndi=ndi; f.harq_process=2;
    f.antenna_ports=4; f.dmrs_sequence_initialization=1;
    packed=sixgr.phy.pdcch.DCIPacker.pack(f,context);
    controlTx=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',packed.Bits,'RNTI',cfg.phy.pdsch.RNTI);
    [control,controlInfo]=sixgr.phy.dl.PDCCH_Rx(controlTx.TransmitSamples,cfg, ...
        'SampleRate_Hz',controlTx.SampleRateHz);
    a=sixgr.phy.pdcch.materializeConnectedDCI(control,controlInfo,cfg);
    % Independent gNB fixture uses scheduled values and retains its own TB.
    gnb=cfg; gnb.phy.pdsch.prbSet=3:(3+nprb-1);
    tdra=context.Data.DLTimeDomainAllocations;
    tdra=tdra(tdra(:,1)==0,:);
    gnb.phy.pdsch.symbolAllocation=tdra(2:3);
    gnb.phy.pdsch.mcsTable='calibration_explicit';
    gnb.phy.pdsch.mcsIndex=0; gnb.phy.pdsch.mcsIndexPerCodeword=0;
    gnb.phy.pdsch.mcsTablePerCodeword='calibration_explicit';
    gnb.phy.pdsch.modulation=char(initial.Modulation);
    if k==2 || k==3, gnb.phy.pdsch.modulation='64QAM'; end
    gnb.phy.pdsch.codeRate=initial.TargetCodeRate; gnb.phy.pdsch.rv=rv;
    gnb.phy.pdsch.dmrs.NSCID=1; gnb.phy.pdsch.dmrs.scheduledPortSet=1;
    gnb.phy.pdsch.dmrs.portSet=1; gnb.phy.pdsch.dmrs.numCDMGroupsWithoutData=2;
    gnb.phy.pdsch.precoding.matrix=[1;0]; gnb.phy.pdsch.normalizePrecodingMatrix=false;
    gnb.phy.pdsch.selectedPrecoderSHA256=sixgr.phy.mimo.MatrixContract.digest([1;0]);
    txArgs={};
    if k==2 || k==3
        txArgs={'TransportBlockBits',bits,'TransportBlockSizeOverride',numel(bits)};
    end
    tx=sixgr.phy.dl.PDSCH_Tx(gnb,'ExecutionProfile','phy_calibration',txArgs{:});
    if k==1 || k==4, bits=tx.TransportBlock; end
    % Deliberately low-margin first capture, high-margin retransmission.
    % Do not manufacture a NACK or feed expected bits to the UE receiver.
    snr=35; if k==1, snr=-12; end
    noise=10^(-snr/10)/nrOFDMInfo(tx.Carrier).Nfft;
    wave=tx.Waveform+sqrt(noise/2)*complex(randn(size(tx.Waveform)),randn(size(tx.Waveform)));
    delayed=[complex(zeros(43,size(wave,2)));wave;complex(zeros(17,size(wave,2)))];
    before=entity;
    [rx,decision,entity]=entity.receive(cfg,a,delayed,'TimingSearchWindowSamples',[0 60]);
    if k==1
        assert(~rx.CRCPass && ~decision.ACK && ~decision.DeliverTransportBlock, ...
            'Stress waveform must cause an actual failed initial decode.');
    elseif k==3
        assert(isempty(rx) && decision.ACK && decision.AcknowledgedFromPriorDecode && ...
            ~decision.DecodeAttempted && ~decision.DeliverTransportBlock, ...
            'Already-decoded TB must not be fabricated as a fresh decode or delivered twice.');
    else
        assert(rx.CRCPass && isequal(rx.TransportBlock,bits) && decision.DeliverTransportBlock);
    end
    if k==2
        assert(a.RequiresHARQHistory && isnan(a.TargetCodeRate) && ...
            rx.Assignment.get('MCSIndexPerCodeword')==31 && ...
            rx.Assignment.get('TargetCodeRatePerCodeword')==initial.TargetCodeRate && ...
            rx.Decode.HARQCombineInfo.Applied && ~rx.Decode.HARQCombineInfo.ResetPrior && ...
            rx.CodingPlans{1}.BaseGraph==before.Processes{3}.History.BaseGraph && ...
            string(rx.CodingPlans{1}.CombineSignature)==before.Processes{3}.History.CombineSignature);
        missing=sixgr.link.ReceivedDLHARQState(cfg,1);
        localReject(@()missing.receive(cfg,a,delayed),'sixgr:pdsch:ReceivedDLHARQHistoryRequired');
        % Mutating the typed assignment cannot attach retained coding to a new NDI.
        bad=rx.Assignment.toStruct(); bad.NDIPerCodeword=0;
        localReject(@()sixgr.pdsch.PDSCHSchedulingAssignment(bad), ...
            'sixgr:pdsch:ReceivedDLHARQIdentityMismatch');
    end
    measuredDelay=NaN;
    if ~isempty(rx)
        measuredDelay=rx.TimingOffset;
        assert(measuredDelay>=0 && measuredDelay<=60 && ~rx.ReceiveTiming.OracleTimingUsed);
        % Low-SNR acquisition can err and contributes to the actual NACK;
        % exact acquisition is required for the high-margin recovery/reset.
        if k~=1, assert(measuredDelay==43); end
    end
    if k==4
        assert(decision.Attempt==1 && ~decision.IsRetransmission && ...
            ~rx.Decode.HARQCombineInfo.Applied && entity.Processes{3}.NDI==0);
    end
    localReject(@()entity.receive(cfg,a,delayed),'sixgr:link:ReceivedDLHARQNoncausalAssignment');
    save(fullfile(outputRoot,sprintf('attempt_%d.mat',k)), ...
        'a','control','controlInfo','delayed','rx','decision','before','entity','bits','snr');
    rows=[rows;table(k,ndi,rv,mcs,nprb,numel(bits),measuredDelay,decision.DecodeAttempted,decision.ACK, ...
        decision.DeliverTransportBlock,'VariableNames',{'Sequence','NDI','RV','ReceivedMCS', ...
        'NumPRB','RetainedTBSBits','MeasuredDelaySamples','DecodeAttempted','ACKDecision','DeliverTransportBlock'})]; %#ok<AGROW>
    writetable(rows,fullfile(outputRoot,'received_dl_harq.csv'));
    fprintf('RECEIVED_DL_HARQ_PASS sequence=%d ndi=%d rv=%d mcs=%d bits=%d delay=%g decode=%d ack=%d deliver=%d\n', ...
        k,ndi,rv,mcs,numel(bits),measuredDelay,decision.DecodeAttempted,decision.ACK,decision.DeliverTransportBlock);
end
assert(isempty(entity.Processes{1}) && isempty(entity.Processes{2}));
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
