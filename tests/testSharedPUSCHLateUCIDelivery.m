function ok=testSharedPUSCHLateUCIDelivery()
% Received waveform is unchanged; scheduler delivery crosses a slot boundary.
% Use independently installed connected DCI/BWP/CORESET policy and actual
% received UL control. The legacy known-candidate fixture has no installed
% receive context and must not bypass validateSharedDCIConfiguration.
ok=testSharedPUSCHChannelArtifacts('TDD',true,true,false,true,true);
end
