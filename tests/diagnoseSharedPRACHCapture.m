function diagnoseSharedPRACHCapture(folder)
% Reprocess retained actual planes. Never replay the channel/RF or replace
% production receiver rows with these explicitly offline comparisons.
files=dir(fullfile(folder,'**','ra_received_observations','*Msg1*.mat'));
assert(~isempty(files),'No real PRACH capture was persisted.');
for file=files(:).'
    data=load(fullfile(file.folder,file.name),'capture'); c=data.capture;
    checkpoint=c.ReceiverContinuation;
    cfg=checkpoint.Config; raCfg=checkpoint.RAConfig;
    occasion=checkpoint.PreparedContext.Occasion;
    fprintf('PRACH_CAPTURE=%s\n',file.name);
    fprintf('Prepared start=%g s; PRACH slot0=%g; carrier slot0=%g; carrier start symbol=%g\n', ...
        c.Prepared.StartTime_s,occasion.PRACHSlotIndex0,occasion.SlotIndex0,occasion.CarrierStartSymbol);
    disp(checkpoint.Msg1Tx.OFDMInfo);
    for name=["TXAfterRF","RXBeforeRF","RXAfterRF","RXAfterDigitalGainCompensation"]
        samples=c.(name);
        d=sixgr.phy.ra.detectMsg1PRACH(samples,cfg,raCfg,occasion);
        fprintf('%s detected=%d index=%g peak=%g threshold=%g meanSamplePower_dBm=%s\n', ...
            name,d.Detected,d.DetectedPreambleIndex,d.PeakMetric,d.Threshold, ...
            mat2str(10*log10(mean(abs(samples).^2,1)),8));
    end
    segment=c.ExecutionReplay.ReceiveStreamExecutionSegments{1}.Execution;
    for link=segment.Links
        disp(link.LossReplay);
    end
end
end
