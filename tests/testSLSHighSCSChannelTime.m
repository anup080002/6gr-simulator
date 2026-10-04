function ok=testSLSHighSCSChannelTime()
% Nonuniform normal-CP slots: actual DL/UL TDL/CDL plus sealed HARQ episodes.
ok=testSLSWaveformChannelIdentity('DopplerHz',70,'AbsoluteSlot',83, ...
    'SubcarrierSpacing',120,'RetryCollection',true);
end
