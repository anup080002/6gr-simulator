function ok = testTRSMeasuredResultDelivery()
% Real noisy CDL receiver measurements, then causal runtime consumption.
[~,e] = testBroadcastTRSNoisyStream(13);
out = e.TRS;
assert(out.Ok && out.StrictOk && ~out.Crash);
row = struct2table(out,'AsArray',true);
row.Status = "PASS"; % Actual receiver outcome asserted immediately above.
row.Frame = floor((e.SourceSlot-1)/e.Config.phy.numerology.slotsPerFrame)+1;
row.Slot = e.SourceSlot;
row.UEIndex = 1;
row.ServingCell = 1;
row.EstimatedDopplerHz = out.EstimatedDoppler_Hz;
state = e.Runtime;
state.CurrentSlot = e.SourceSlot;
state.CurrentFrame = row.Frame;
initial = state.ReceiverTrackingStateByCell;
state = sixgr.truth.TRSResultDelivery.enqueue(state,1,1,row,e.Config,out.ObservedREAllocationTable);
assert(out.ObservationStartSample==round(0.012*e.SampleRateHz));
assert(out.ObservationEndSampleExclusive==round(0.018*e.SampleRateHz));
for slot = e.SourceSlot:18
    state.CurrentSlot = slot;
    [state,notYet] = sixgr.truth.TRSResultDelivery.takeAvailable(state);
    assert(isempty(notYet));
    assert(isequaln(state.ReceiverTrackingStateByCell,initial));
end
state.CurrentSlot = 19;
[state,ready] = sixgr.truth.TRSResultDelivery.takeAvailable(state);
assert(numel(ready)==1);
assert(isequaln(ready.Trial(:,row.Properties.VariableNames),row));
state = sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state,1,ready.Trial);
tracking = state.ReceiverTrackingStateByCell(1);
assert(state.TrackingEligibilityByCell(1));
assert(state.LastSuccessfulTRSSlotByCell(1)==19);
assert(tracking.LastUpdateSlot==19 && tracking.TRSTrackingUpdateTime_s>=out.ObservationCompletionTime_s);
assert(tracking.NMSE_dB==out.NMSE_dB);
assert(tracking.EstimatedCFO_Hz==out.EstimatedCFO_Hz);
assert(tracking.TimingEstimate_samples==out.EstimatedTimingOffset_samples);
assert(state.ReferenceSignalMeasurementTable.ProducerSlot(end)==13);
assert(state.ReferenceSignalMeasurementTable.AvailableSlot(end)==19);
assert(isequaln(ready.ObservedRE,out.ObservedREAllocationTable));
ok = true;
disp('TRS_MEASURED_RESULT_DELIVERY_PASS');
end
