function ok=testDLCRCScoringSeparation()
% Actual saved receiver verdicts must be invariant to scoring-reference bits.
setup6GRSimToolkit('Verbose',false);
for k=[1 2 4]
    saved=load(fullfile('docs','lls','evidence_20260913','received_dl_harq',sprintf('attempt_%d.mat',k)));
    [crc,errors,count]=sixgr.link.scoreReceivedDLTransportBlock(saved.rx,saved.bits);
    [changedCRC,changedErrors,changedCount]=sixgr.link.scoreReceivedDLTransportBlock(saved.rx,1-saved.bits);
    assert(crc==saved.rx.CRCPass && changedCRC==crc && count==numel(saved.bits) && ...
        changedCount==count && errors+changedErrors==count);
    if k~=1, assert(crc && errors==0 && changedErrors==count); else, assert(~crc); end
end
bad=saved.rx; bad.TransportBlock=bad.TransportBlock(2:end);
reject(@()sixgr.link.scoreReceivedDLTransportBlock(bad,saved.bits),'sixgr:link:DLDecodedTBSMismatch');
bad=saved.rx; bad=rmfield(bad,'CRCPass');
reject(@()sixgr.link.scoreReceivedDLTransportBlock(bad,saved.bits),'sixgr:link:DLDecodeVerdictRequired');
fprintf('DL_CRC_SCORING_SEPARATION_PASS captures=3 scoring_complements=3 guards=2\n');
ok=true;
end

function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
