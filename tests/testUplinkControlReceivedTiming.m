function ok=testUplinkControlReceivedTiming()
% Actual NR SRS/PUCCH codecs with analytic delayed multipath unit samples.
% Received-clock/RAR fixtures are NOT main-scheduler or field measurements.
setup6GRSimToolkit('Verbose',false);
for mode=["TDD","FDD"]
file='lls_causal_access_to_data_wiring_tdd.yaml';
if mode=="FDD", file='lls_causal_access_to_data_wiring.yaml'; end
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios',file));
base=sixgr.lls6g.buildInternalConfig(source,tempname);
base.channel.model='AWGN'; base.channel.awgnOnly=true;
base.channel.fading.enabled=false; base.channel.fading.type='AWGN';
base.run.noiseOperatingMode='standalone_awgn_snr_argument';
base=sixgr.phy.grid.applyRuntimeCarrierTimeline(base,5,1);
base.lls6g.userContext.RuntimeSlotStartTime_s=4e-3;
base.lls6g.userContext.RuntimeServingPathloss_dB=77;
base.lls6g.userContext.RuntimeServingPathlossSource='unit_fixture_analytic_reference_not_field_measurement';
base.lls6g.userContext.RuntimeServingPathlossReferenceRS='SSB-0';
base.lls6g.userContext.RuntimeServingPathlossMeasurementId='unit_fixture_not_measured_access';
base.lls6g.userContext.RuntimeServingPathlossMeasurementSlot=1;
base.lls6g.userContext.RuntimeServingPathlossReferenceSignalType='SSB';
base.lls6g.userContext.RuntimeServingPathlossReferenceSignalId=0;
carrier=sixgr.phy.grid.makeCarrier(base); ofdm=nrOFDMInfo(carrier); fs=ofdm.SampleRate;
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',fs,'DLPhaseOffsetSamples',6,'AvailableAtSample',1000);
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
base.SharedULTimingContext=struct('DLReference',reference, ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'TimingAdvanceAvailableAtSample',1000,'TimingAdvanceEffectiveAtSample',2000, ...
    'TimeAlignmentExpirySampleExclusive',round(.01*fs));
assert(sixgr.phy.frame.resolveDuplexMode(base)==mode);
    for command=[0 3]
        cfg=base;
        ta=sixgr.phy.ra.resolveRARTimingAdvance(command,carrier.SubcarrierSpacing,fs);
        cfg.SharedULTimingContext.ReceivedRARTiming=ta;
        for channel=["SRS","PUCCH"]
            if channel=="SRS"
                runner=@sixgr.link.runSRSChannelEstimation;
                args={'SlotIndex',5,'SNR_dB',12,'TimingAdvanceSamples',ta.Samples};
            else
                report=localPUCCH(cfg,logical([1;0;1]));
                runner=@sixgr.link.runPUCCHWaveformTrial;
                args={'Assignment',report.Assignment,'Report',report.Report, ...
                    'Carrier',carrier,'ChannelProfile','AWGN','SNR_dB',12,'TimingAdvanceSamples',ta.Samples};
            end
            prepared=runner(cfg,args{:},'PrepareOnly',true); p=prepared.PreparedTransmission;
            if channel=="PUCCH"
                badArgs=args; profile=find(strcmp(badArgs,'ChannelProfile'),1); badArgs{profile+1}='TDL-C';
                localReject(@()runner(cfg,badArgs{:},'PrepareOnly',true),'sixgr:config:YAMLChannelProfileBypassed');
            end
            assert(~prepared.Ok && p.PhysicalTiming.WaveformTimingApplied && ...
                ~p.PhysicalTiming.FiniteWaveformCropped);
            assert(p.StartSample~=p.ReceiveStartSample && ...
                p.EndSampleExclusive-p.StartSample==size(p.Tx.Waveform,1));
            a=sixgr.rf.AntennaArrayFactory.build(cfg,'ue','signal',lower(channel), ...
                'numPorts',size(p.Tx.Waveform,2));
            x=p.Tx.Waveform*cast(a.PortToElementMatrix.','like',p.Tx.Waveform);
            connector=eye(size(x,2),p.NumReceiveAntennas)*10^(-77/20);
            signal=x*cast(connector,'like',x);
            % Analytic propagation delay 6 and filter delay 7. These are
            % ONLY used to create fixture samples, never passed to RX.
            physicalDelay=13; secondaryDelay=3;
            arrival=p.StartSample+physicalDelay-p.ReceiveStartSample;
            count=p.ReceiveEndSampleExclusive-p.ReceiveStartSample+physicalDelay+secondaryDelay;
            desired=complex(zeros(count,p.NumReceiveAntennas));
            desired(arrival+(1:size(signal,1)),:)=signal;
            desired(arrival+secondaryDelay+(1:size(signal,1)),:)= ...
                desired(arrival+secondaryDelay+(1:size(signal,1)),:)+.1*exp(.3i)*signal;
            if channel=="SRS", indices=p.Tx.SRSIndices; else, indices=p.Tx.PUCCHIndices; end
            aligned=desired(arrival+(1:size(signal,1)),:);
            energy=sixgr.phy.waveform.measureReceivedOccupiedREEnergy(carrier,aligned,indices,'SignalFamily',channel);
            rng(190+command,'twister');
            [y,noise]=sixgr.phy.waveform.addOccupiedREAWGN(desired,carrier,12,'SignalEnergyPerOccupiedRE',energy);
            replay=struct('SampleNoiseVariance',noise.SampleNoiseVariance, ...
                'SampleNoiseVarianceDomain','receiver_sample_waveform_post_composite_front_end', ...
                'NoiseOperatingMode','standalone_awgn_snr_argument','ApproximationMode','none');
            context=struct('Prepared',p,'Observation',localBuffer(y,p.ReceiveStartSample,fs), ...
                'PhysicalMeasurementObservation',localBuffer(y,p.ReceiveStartSample,fs), ...
                'DesiredReferenceObservation',localBuffer(desired,p.ReceiveStartSample,fs), ...
                'TransmitterObservation',localBuffer(x,p.StartSample,fs),'Replay',replay, ...
                'ChannelState',struct('UnitFixtureOnly',true), ...
                'Channel',struct('Profile','AWGN','Source','analytic_two_tap_unit_fixture_not_3gpp_channel_realization'));
            saved=rng;
            output=runner(cfg,args{:},'ReceivedContext',context);
            assert(isequal(saved,rng),'RX must not regenerate TX, noise or propagation.');
            if channel=="SRS"
                timing=output.ReceiveTiming;
                assert(output.Ok && output.NMSE_dB<=output.ChannelNMSEThreshold_dB,output.Notes);
            else
                timing=output.Rx.ReceiveTiming;
                assert(output.Ok && output.UCIContentMatch && ~output.Rx.OraclePayloadBitsUsed,output.FailureReason);
            end
            assert(abs(timing.TimingOffsetSamples-arrival)<=1 && ...
                timing.AppliedTimingCorrectionSamples==timing.TimingOffsetSamples && ...
                ~timing.OracleTimingUsed && ~timing.ReceiverZeroPaddingUsed);
            bad=context; bad.Observation=localBuffer(y,p.StartSample,fs);
            localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:link:ULControlObservationMismatch');
            future=cfg; future.SharedULTimingContext.TimingAdvanceAvailableAtSample=p.StartSample+1;
            future.SharedULTimingContext.TimingAdvanceEffectiveAtSample=p.StartSample+1;
            localReject(@()runner(future,args{:},'PrepareOnly',true),'sixgr:link:ConnectedULBeforeReceivedTA');
            future=cfg; future.SharedULTimingContext.TimingAdvanceEffectiveAtSample=p.StartSample+1;
            localReject(@()runner(future,args{:},'PrepareOnly',true),'sixgr:link:ConnectedULBeforeTAApplication');
            expired=cfg; expired.SharedULTimingContext.TimeAlignmentExpirySampleExclusive=p.EndSampleExclusive-1;
            localReject(@()runner(expired,args{:},'PrepareOnly',true),'sixgr:link:ConnectedULAfterTAExpiry');
            incomplete=cfg; incomplete.SharedULTimingContext=rmfield(incomplete.SharedULTimingContext,'TimingAdvanceEffectiveAtSample');
            localReject(@()runner(incomplete,args{:},'PrepareOnly',true),'sixgr:link:MissingConnectedULTiming');
            corrupted=cfg;
            corrupted.SharedULTimingContext.Offset.NTAOffset_Tc= ...
                corrupted.SharedULTimingContext.Offset.NTAOffset_Tc+int64(1);
            localReject(@()runner(corrupted,args{:},'PrepareOnly',true),'sixgr:link:ConnectedULOffsetAuthorityMismatch');
            wrong=args; wrong{end}=ta.Samples+1;
            localReject(@()runner(cfg,wrong{:},'PrepareOnly',true),'sixgr:link:ULControlTimingAuthorityMismatch');
            fprintf('[PASS] %s %s RAR=%d measured timing=%g expected=%g; actual NR unit reception.\n', ...
                mode,channel,command,timing.TimingOffsetSamples,arrival);
        end
    end
end
% Format 0 timing must not be inferred from known transmitted payload.
report=localPUCCH(base,true); tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,report.Assignment,report.Report);
schema=sixgr.phy.pucch.UCIReportContext.fromReport(report.Report);
localReject(@()sixgr.phy.pucch.PUCCHReceiver.receive(tx.Waveform,carrier, ...
    report.Assignment,schema,'TimingSearchWindowSamples',[0 10]), ...
    'sixgr:phy:pucch:PUCCHTimingReferenceRequired');
ok=true;
end

function out=localPUCCH(cfg,bits)
identity=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',cfg.phy.pusch.RNTI,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
frame=struct('K1',4,'K1Source','decoded_dci','PDSCHEndSlot',1,'TargetSlot',5, ...
    'DecodedPRI',0,'PRIFieldWidth',3,'PRIProvenance','unit_fixture', ...
    'FirstCCE',0,'NumCCE',4,'SlotSymbolOwnership','UUUUUUUUUUUUUU', ...
    'FlexibleResolutionProvided',false,'TriggeringEventID','unit_fixture');
out=sixgr.phy.pucch.PUCCHConfigBuilder.connectedHARQ(cfg,ue,bits,frame);
end
function buffer=localBuffer(x,first,fs)
buffer=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(x,1),fs,size(x,2));
buffer.append(sixgr.phy.waveform.WaveformChunk(x,first),fs);
end
function localReject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),cause.message); return; end
error('test:ExpectedFailure','Expected %s.',id);
end
