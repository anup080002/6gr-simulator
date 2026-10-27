function bits=dlSchedulingQueueBits(state)
% gNB-local actual L2 demand, including retained AM retransmission and reverse STATUS.
bits=double(state.DLQueueBits);
if ~logical(sixgr.util.structGet(state,'ProtocolWaveformEnabled',false)), return; end
bridge=state.ProtocolBridge;
for u=1:numel(bits)
    volume=bridge.pendingTransmitBytes(u,'DL');
    bits(u)=8*volume.TotalBSRBytes;
end
end
