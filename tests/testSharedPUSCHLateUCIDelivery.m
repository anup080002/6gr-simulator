function ok=testSharedPUSCHLateUCIDelivery()
% Received waveform is unchanged; scheduler delivery crosses a slot boundary.
ok=testSharedPUSCHChannelArtifacts('TDD',true,true);
end
