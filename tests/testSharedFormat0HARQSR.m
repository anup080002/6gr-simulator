function ok=testSharedFormat0HARQSR()
% Actual shared Format-0 waveform, with isolated DL decoder ACK connector.
% Two Type-2 assignments plus SR must not turn into a Format-2 allocation.
root=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(root,'results','lls','shared_format0_harq_sr', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
fprintf('SHARED_FORMAT0_HARQ_SR_EVIDENCE=%s\n',folder);
fixture=fullfile(root,'simulator','configs','validation','lls_pucch_format0_harq_sr_clock.yaml');
ok=testSharedPUCCHFeedbackClock(true,'TDD',fixture,folder);
saved=load(fullfile(folder,'received_pucch.mat'),'item');
h=saved.item.Context.GNBReception;
assert(h.Assignment.Format==0 && h.Mapping.BitCount==2 && ...
    h.Context.HARQACKBits==2 && h.Context.SRBits==1 && ...
    h.Context.Sequence1Length==3 && h.Context.CSIPart1Bits==0 && ...
    h.Assignment.Resource.ID==0, ...
    'test:ShortHARQSRResource','SR is carried by Format-0 sequence choice, not a third HARQ allocation bit.');
fprintf('SHARED_FORMAT0_HARQ_SR_PASS HARQ=2 SR=1 CSI=0 format=0 physical_UCI=1 detector_qualified=0\n');
end
