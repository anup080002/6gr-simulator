function ok=testSharedSSBPowerReference(absolute)
% Actual bounded shared SSB execution; declared acquired state is a fixture.
% Tests original measurement/reference binding, NOT access, standardized
% RSRP accuracy, statistical detector reliability or a complete scenario.
setup6GRSimToolkit('Verbose',false);
% recoverSIB1 installs these defaults before any acquisition can fail.
empty=sixgr.phy.refsig.buildSSBPowerMeasurementReceipt();
assert(empty.SSBPhysicalMeasurementReferencePlane=="unavailable_original_measurement_plane"&& ...
    ~empty.SSBPowerMeasurementReceiptAvailable);
projected=sixgr.link.ssbPowerReferenceEvidence(empty);
assert(projected.SSBPhysicalMeasurementReferencePlane==empty.SSBPhysicalMeasurementReferencePlane&& ...
    ~projected.SSBEmittedPowerComparisonAvailable);
if nargin<1, absolute=false; end
fixture='lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml';
if absolute, fixture='lls_ssb_physical_power_contract_fixture.yaml'; end
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',fixture));
root=tempname(fullfile(pwd,'logs')); mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(s,root); cfg.run.rootRunFolder=root;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),6);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentCanonicalSlot=1;
state.CurrentServingIdx(:)=1; state.CellAcquisitionState(1)="acquired";
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
prototype=sixgr.link.runCellSearch_MIB_SIB1(dl,'PrepareOnly',true,'UseRuntimeChannel',true,'RuntimeSlot',0);
assert(isfield(prototype,'PreparedBroadcast'),'%s',prototype.FailureReason);
p=prototype.PreparedBroadcast; power=p.Tx.SSBPowerReferenceContract;
assert(power.PhysicalDevicePowerClaim==absolute,'Execute the declared waveform power domain.');
state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture(cfg,power.SSPBCHBlockPower_dBm,1,1)};
c=struct('Config',dl,'Slot',1,'ServingCell',1,'TrackingOnly',true,'Prototype',prototype);
owner.queueDownlink('PBCH',1,p,c);
last=ceil(p.NumSamples/(p.SampleRateHz*state.SlotDuration_s));
assert(last<=9,'This is a bounded broadcast check, not a full scenario.');
for slot=1:last
    state.CurrentSlot=slot; state.CurrentCanonicalSlot=slot;
    state=sixgr.truth.SSBOccasionResultDelivery.deliver(state);
    [state,~]=owner.advanceSlot(state,cfg,@received);
end
state.CurrentSlot=last+1; state.CurrentCanonicalSlot=last+1;
state=sixgr.truth.SSBOccasionResultDelivery.deliver(state);
T=state.DeliveredSSBOccasionMeasurements;
assert(height(T)==numel(cfg.phy.ssb.activeCandidateIndices0Based)&&all(T.CRCPass)&& ...
    all(T.SSBPowerMeasurementReceiptAvailable)&&all(T.SSBEmittedPowerComparisonAvailable), ...
    'Every actual periodic SSB must retain its original operator and independent comparison: %s', ...
    strjoin(T.SSBEmittedPowerComparisonStatus,' | '));
assert(isfield(state,'TestFullSSBPowerRows')&&height(state.TestFullSSBPowerRows)==height(T));
assert(all(state.TestFullSSBPowerRows.SSBEmittedPowerComparisonAvailable));
assert(~any(T.SSBEmittedPowerComparisonStandardizedAccuracyQualified));
assert(all(T.SSBReceiveElementBindingAvailable)&& ...
    all(T.SSBPhysicalMeasurementReferencePlane=="internal_physical_receive_element_before_RX_front_end")&& ...
    ~any(T.SSBMeasurementStandardizedReferencePointQualified)&&~any(T.SSBMeasurementHardwareQualified)&& ...
    ~any(contains(T.PowerReferencePlane,"connector"))&&~any(contains(T.SSSINRReferencePlane,"connector")), ...
    'Actual internal element execution is not standardized connector or hardware qualification.');
assert(numel(unique(T.SSBPowerMeasurementReceiptSHA256))==height(T), ...
    'Different original SSB occasions must not share a copied receipt.');
for k=1:height(T)
    r=jsondecode(T.SSBPowerMeasurementReceiptJSON(k));
    e=jsondecode(T.SSBEmittedPowerComparisonEvidenceJSON(k));
    assert(r.ObservedSSBOccasionIndex==T.ReferenceSignalId(k)&& ...
        e.ObservedSSBOccasionIndex==T.ReferenceSignalId(k)&&e.AdditionalOFDMDemodulations==1&& ...
        e.AdditionalTimingAcquisitions==0&&e.AdditionalFrequencyEstimations==0&& ...
        e.AdditionalChannelEstimations==0&&e.AdditionalRFExecutions==0&& ...
        e.AdditionalChannelExecutions==0&&~e.ReferenceUsedByReceiver&& ...
        ~e.IsolatedIdealSSSReference&&~e.SameTransmitterLeakageExcluded&& ...
        ~e.StandardizedReferencePlaneQualified&&~e.StandardizedAccuracyQualified);
    assert(strcmp(r.WaveformAmplitudeUnit,p.PowerContext.WaveformAmplitudeUnit));
    assert(numel(e.Comparison.ReferencePerReceiveColumn)==r.NumReceiveColumns);
end
% Persist actual produced rows and check quoted receipts survive publication.
file=fullfile(root,'ssb_power_original_reference.csv');
sixgr.util.csvWriteTable(file,T,'PreserveSchema',true);
read=sixgr.util.csvReadTable(file,'TextType','string');
assert(isequal(string(read.SSBPowerMeasurementReceiptJSON),T.SSBPowerMeasurementReceiptJSON)&& ...
    isequal(string(read.SSBEmittedPowerComparisonEvidenceJSON),T.SSBEmittedPowerComparisonEvidenceJSON));
fprintf('SHARED_SSB_POWER_REFERENCE_PASS beams=%d full_burst=1 periodic=1 absolute=%d negative_groups=%d standardized_accuracy=0 root=%s\n', ...
    height(T),absolute,state.TestSSBPowerNegativeGroups,root);
ok=true;
end

function state=received(state,items)
for item=items
    if item.Kind=="SSBOccasion"
        state=sixgr.truth.SSBOccasionResultDelivery.complete(state,item);
    elseif item.Kind=="PBCH"
        c=item.Context; p=c.Prepared;
        [~,pre,tx,replay,post]=sixgr.truth.sharedObservationEvidence(item.Planes);
        [reference,source]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,c.DesiredReferencePlane);
        binding=state.SharedWaveformStream.Physical.receiveElementLayout(string(source.ReceiverID));
        originalBinding=struct('Planes',{item.Planes},'DesiredReferencePlaneID',c.DesiredReferencePlane, ...
            'ReceiveBranchBinding',state.SharedWaveformStream.Physical.receiveBranchLayout(string(source.ReceiverID)));
        prototype=c.Prototype; prototype.RuntimeChannelReplay=replay;
        prototype.RuntimeDLChannelState=state.SharedWaveformStream.channelState(item.UE,'DL');
        prototype.RuntimeChannelStateUsed=true; prototype.PowerContext=p.PowerContext;
        options=struct('UseRuntimeChannel',true,'RuntimeSlot',0, ...
            'CandidateSSBIndices',c.Config.phy.ssb.activeCandidateIndices0Based,'SSBIndex',[], ...
            'WriteArtifacts',false,'RunFolder','','RunId','ssb_original_power_reference', ...
            'PhysicalMeasurementObservation',pre,'TransmitObservation',tx, ...
            'DesiredReferenceObservation',reference,'DesiredReferenceEvidence',source,'ReceiveElementBinding',binding, ...
            'OriginalSSBPowerObservationBinding',originalBinding);
        hashes=[pre.sampleHash() reference.sampleHash() post.sampleHash()];
        output=sixgr.link.completeCellSearchBroadcast(p,post,prototype,options,tic);
        rows=cell(numel(output.CandidateResults),1);
        for k=1:numel(rows)
            result=output.CandidateResults{k};
            assert(result.SSBPowerMeasurementReceiptAvailable&&result.SSBEmittedPowerComparisonAvailable, ...
                'Original SSB comparison failed: %s %s',result.SSBEmittedPowerComparisonStatus, ...
                result.SSBEmittedPowerComparisonEvidenceJSON);
            comparison=jsondecode(result.SSBEmittedPowerComparisonEvidenceJSON);
            assert(string(comparison.OriginalDesiredReferencePlaneID)==string(originalBinding.DesiredReferencePlaneID), ...
                'Completed scoring must preserve the original desired-plane binding independently of measured power values.');
            assert(result.SSBReceiveElementBindingAvailable&& ...
                result.SSBPhysicalMeasurementReferencePlane=="internal_physical_receive_element_before_RX_front_end"&& ...
                ~contains(result.PowerReferencePlane,"connector")&&~contains(result.SSSINRReferencePlane,"connector"));
            f=sixgr.link.ssbPowerReferenceEvidence(result);
            for name=string(fieldnames(f)).'
                assert(isequaln(f.(name),result.PBCH.(name))&&isequaln(f.(name),result.SIB1.(name)), ...
                    'Full-burst completion must retain one original receipt through all result projections.');
            end
            rows{k}=struct2table(f,'AsArray',true);
        end
        state.TestFullSSBPowerRows=vertcat(rows{:});
        r=output.CandidateResults{1}.SIB1; before=r;
        receipt=jsondecode(r.SSBPowerMeasurementReceiptJSON);
        repeated=sixgr.phy.refsig.replaySSBPowerMeasurementOperator(reference.readComplete(),receipt);
        original=jsondecode(r.SSBEmittedPowerComparisonEvidenceJSON);
        assert(isequaln(repeated.ReferencePerReceiveColumn(:),original.Comparison.ReferencePerReceiveColumn(:)));
        % Pure operator replay on ORIGINAL noisy samples must recover the
        % EXACT original grid hash; this is not an accuracy reference.
        self=sixgr.phy.refsig.replaySSBPowerMeasurementOperator(pre.readComplete(),receipt);
        assert(self.SSBGridSHA256==string(receipt.SSBGridSHA256), ...
            'Recorded crop, phase origins, CP and FFT must reproduce the original noisy grid exactly.');
        for kind=1:5
            bad=r;
            switch kind
                case 1, bad.SSBPowerMeasurementReceiptSHA256="corrupt";
                case 2, bad.ObservedSSBOccasionIndex=bad.ObservedSSBOccasionIndex+1;
                case 3
                    value=receipt; value.InputSHA256="not_the_original_capture";
                    bad=replaceReceipt(bad,value);
                case 4
                    value=receipt; value.WaveformAmplitudeUnit="unknown";
                    bad=replaceReceipt(bad,value);
                case 5
                    value=receipt; value.ReceiverOperator.CFOCorrectionSampleOrigin=1;
                    bad=replaceReceipt(bad,value);
            end
            score=sixgr.truth.scoreSharedSSBPower(bad,reference,source,pre,replay,binding,p.PowerContext,originalBinding);
            assert(~score.SSBEmittedPowerComparisonAvailable&& ...
                strlength(score.SSBEmittedPowerComparisonErrorIdentifier)>0);
        end
        missing=sixgr.truth.scoreSharedSSBPower(r,reference,source,pre,replay,struct(),p.PowerContext,originalBinding);
        assert(~missing.SSBEmittedPowerComparisonAvailable&& ...
            missing.SSBEmittedPowerComparisonStatus=="unavailable_original_receive_element_execution_binding");
        % A fabricated replacement with the SAME clock and column shape is
        % a negative test only. It must never become accepted power evidence.
        changed=reference.readComplete(); changed(1,1)=changed(1,1)+1;
        replacement=sixgr.phy.waveform.WaveformObservationBuffer(reference.StartSample, ...
            reference.EndSampleExclusive,reference.SampleRateHz,reference.NumReceiveAntennas);
        replacement.append(sixgr.phy.waveform.WaveformChunk(changed,reference.StartSample),reference.SampleRateHz);
        substituted=sixgr.truth.scoreSharedSSBPower(r,replacement,source,pre,replay,binding,p.PowerContext,originalBinding);
        assert(~substituted.SSBEmittedPowerComparisonAvailable&& ...
            substituted.SSBEmittedPowerComparisonErrorIdentifier=="sixgr:truth:SSBPowerReference", ...
            'Same-shaped/same-clock samples are not the original desired-link observation.');
        wrongSource=source; wrongSource.LinkID=string(source.LinkID)+"_wrong_link";
        transplanted=sixgr.truth.scoreSharedSSBPower(r,reference,wrongSource,pre,replay,binding,p.PowerContext,originalBinding);
        assert(~transplanted.SSBEmittedPowerComparisonAvailable&& ...
            transplanted.SSBEmittedPowerComparisonErrorIdentifier=="sixgr:truth:SSBPowerReference");
        state.TestSSBPowerNegativeGroups=8;
        assert(isequaln(r,before)&&isequal(hashes,[pre.sampleHash() reference.sampleHash() post.sampleHash()]), ...
            'Scoring must not mutate practical reception or retained samples.');
    else
        error('test:UnexpectedSSBPowerObservation','Unexpected observation %s.',item.Kind);
    end
end
end
function r=replaceReceipt(r,value)
r.SSBPowerMeasurementReceiptJSON=string(jsonencode(value));
r.SSBPowerMeasurementReceiptSHA256=string(sixgr.util.sha256Hex(char(r.SSBPowerMeasurementReceiptJSON)));
end
