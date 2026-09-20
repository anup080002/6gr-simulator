function ok=testPUCCHTransmitLayoutInvariant()
%TESTPUCCHTRANSMITLAYOUTINVARIANT Guard the typed TX-only UCI contract.
fixture=sixgr.phy.pucch.PUCCHFixtureFactory.connected( ...
    2,int8([1;0;1;1]),'RNTI',320);
report=fixture.Report;
serialized=sixgr.phy.pucch.UCIReportSerializer.serialize(report);
context=sixgr.phy.pucch.validateTransmitUCILayout(report,serialized);
assert(context.Sequence1Length+context.Sequence2Length== ...
    numel(serialized.Sequence1.Bits)+numel(serialized.Sequence2.Bits));

bad=serialized;
bad.Layout.BitValue(1)=int8(1-double(bad.Layout.BitValue(1)));
localReject(@()sixgr.phy.pucch.validateTransmitUCILayout(report,bad), ...
    'sixgr:phy:pucch:TransmitUCILayoutMismatch');

% A receiver is intentionally absent here: this invariant validates the
% transmitter's own report and must not impose a TX/RX oracle comparison.
ok=true;
end

function localReject(fn,id)
try
    fn();
    error('sixgr:test:ExpectedFailure','Expected %s.',id);
catch ME
    assert(string(ME.identifier)==string(id), ...
        'Expected %s, received %s.',id,ME.identifier);
end
end
