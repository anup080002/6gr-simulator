function ok=testReceiveBranchNativeSwap()
% R2026a native 64/4 CDL getters through real physical-owner registration and
% tail-safe retarget. Declared idle samples, not SRS decode/access coverage.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(source,tempdir);
multi=sixgr.truth.resolveMultiUserSpec(cfg);
runtime=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempdir,multi,struct(),0);
runtime.CurrentSlot=1; runtime.CurrentServingIdx(:)=1;
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'DL');
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'UL');
firstWindow=sixgr.truth.resolveTRSObservationWindow(dl,1);
firstRuntimeSlot=firstWindow.AbsoluteSlotNumbers(1)+1;
window=sixgr.truth.resolveTRSObservationWindow(dl,firstRuntimeSlot);
assert(dl.phy.trs.enable&&window.ObservationStarts&& ...
    sixgr.truth.isActiveTRSOccasion(dl,firstRuntimeSlot));
prepared=sixgr.link.prepareTRSTransmission(dl,12,'RuntimeSlot',firstRuntimeSlot);
assert(isequal(prepared.StrictConfig.SlotNumbers,window.AbsoluteSlotNumbers));
tx=prepared.Tx; tx.Waveform=prepared.TransmitSamples;
truth=sixgr.link.initWaveformTruthChannelState(prepared.ReceiverConfig,tx,prepared.TxInfo);
channel=truth.RuntimeChannelState;
assert(isa(channel.Obj,'nrCDLChannel')&&channel.Materialized&& ...
    channel.CurrentSampleIndex==0&&channel.NumTxAnt==64&&channel.NumRxAnt==4&& ...
    channel.Meta.RuntimeTDDReciprocityExact);
fs=channel.SampleRate_Hz; epoch=cfg.rf.configurationEpoch;
owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,epoch);
owner.addTransmitter('gnb',dl,'DL',64,false);
owner.addTransmitter('ue',ul,'UL',4,false);
owner.addReceiver('ue_rx',dl,'DL',4,false);
owner.addReceiver('gnb_rx',ul,'UL',64,false);
owner.addLink('serving','gnb','ue_rx',channel,dl); % actual validateLink
assert(owner.receiveBranchLayout('gnb_rx').Available);
checkCurrent('DL',64,4,false);
consumeIdle();
owner.retargetTDDLink('serving','ue','gnb_rx',ul); % actual strict UL layout guard
checkCurrent('UL',4,64,true);
consumeIdle();
owner.retargetTDDLink('serving','gnb','ue_rx',dl);
checkCurrent('DL',64,4,false);
assert(~owner.Faulted);
fprintf('RECEIVE_BRANCH_NATIVE_SWAP_PASS release=%s native_ports=64/4 actual_owner_retargets=2 decoded_SRS=0\n', ...
    version('-release'));
ok=true;

    function checkCurrent(direction,nTx,nRx,swapped)
        states=owner.channelStates(); assert(isscalar(states)); current=states{1};
        assert(current.Direction==string(direction)&&current.NumTxAnt==nTx&& ...
            current.NumRxAnt==nRx&&logical(current.Obj.TransmitAndReceiveSwapped)==swapped);
        % Public properties are already direction-swapped. This is the
        % release-specific behavior used by the production guard, not an
        % assumption based only on equal-sized endpoints.
        assert(getNumElements(current.Obj.TransmitAntennaArray)==nTx&& ...
            getNumElements(current.Obj.ReceiveAntennaArray)==nRx);
        actual=getElementPosition(current.Obj.ReceiveAntennaArray).';
        if direction=="UL"
            installed=ul.lls6g.userContext.RuntimeServingBSAntenna;
        else
            installed=dl.lls6g.userContext.RuntimeUEAntenna;
        end
        assert(isequal(double(actual),double(installed.ElementPositions_m)));
    end
    function consumeIdle()
        states=owner.channelStates(); first=owner.NextSampleIndex;
        stop=first+double(states{1}.ChannelPadSamples)+1;
        inputs(1)=struct('ID',"gnb",'Chunk',sixgr.phy.waveform.WaveformChunk( ...
            complex(zeros(stop-first,64)),first));
        inputs(2)=struct('ID',"ue",'Chunk',sixgr.phy.waveform.WaveformChunk( ...
            complex(zeros(stop-first,4)),first));
        [~,execution]=owner.process(inputs,first,stop,[]);
        assert(owner.NextSampleIndex==stop&&execution.StartSample==first&& ...
            execution.EndSampleExclusive==stop);
        selected=find(string({execution.RX.ID})=="gnb_rx");
        receipt=execution.RX(selected).Replay.ReceiveBranchExecution;
        assert(receipt.ExecutionVerified&&receipt.StartSample==first&& ...
            receipt.EndSampleExclusive==stop&&receipt.Identity.NumReceiveRFChains==64&& ...
            receipt.HashBindingSource=="original_RF_producer_hashes_from_restricted_canonical_owner");
    end
end
