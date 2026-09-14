function counts=countPUCCHDetectorPilotErrors(c,decoded,usable,dtx)
% Count a real receiver result, or explicitly declared unit-test inputs.
% Rejected bits are not actionable ACKs. Keep the original conservative
% noise EventError gate on ANY raw decoded ACK; never weaken that gate.
assert(islogical(usable) && isscalar(usable) && islogical(dtx) && isscalar(dtx) && ...
    ~(usable && dtx),'test:PilotReceiverAccounting','Invalid receiver usability/DTX state.');
assert((isnumeric(decoded) || islogical(decoded)) && ...
    (isempty(decoded) || isvector(decoded)) && all(ismember(decoded(:),[0 1])), ...
    'test:PilotReceiverAccounting','Receiver payload must be binary, not rounded or coerced.');
width=c.harq_bits; expected=c.payload(:); decoded=decoded(:);
assert(isscalar(width) && ismember(width,[1 2]) && ...
    islogical(c.signal_present) && isscalar(c.signal_present) && ...
    all(ismember(expected,[0 1])) && ...
    ((c.signal_present && numel(expected)==width) || (~c.signal_present && isempty(expected))), ...
    'test:PilotReceiverAccounting','Invalid declared Format-0 hypothesis.');
assert(~usable || numel(decoded)==width,'test:PilotReceiverAccounting', ...
    'A usable receiver result must have the declared length.');
counts=struct('ReceiverUsable',usable,'FalseACKBits',0,'FalseACKBitOpportunities',0, ...
    'MissedACKBits',0,'TransmittedACKBits',0,'NACKToACKBits',0, ...
    'TransmittedNACKBits',0,'SignalBitErrors',0,'SignalBits',0,'RawNoiseACKBits',0);
if ~c.signal_present
    counts.RawNoiseACKBits=sum(decoded==1);
    counts.FalseACKBits=double(usable)*counts.RawNoiseACKBits;
    counts.FalseACKBitOpportunities=width;
    counts.EventError=any(decoded==1); % Original gate, including rejected output.
else
    counts.TransmittedACKBits=sum(expected==1);
    counts.TransmittedNACKBits=sum(expected==0);
    counts.SignalBits=width;
    if usable
        counts.MissedACKBits=sum(expected==1 & decoded~=1);
        counts.NACKToACKBits=sum(expected==0 & decoded==1);
        counts.SignalBitErrors=sum(expected~=decoded);
    else
        counts.MissedACKBits=counts.TransmittedACKBits;
        counts.SignalBitErrors=width; % Every erased signal bit remains an error.
    end
    counts.EventError=~usable || counts.SignalBitErrors>0;
end
end
