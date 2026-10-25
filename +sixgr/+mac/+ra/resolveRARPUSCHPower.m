function pc = resolveRARPUSCHPower(pc, grant, initialize)
%RESOLVERARPUSCHPOWER Actual RAR allocation / retained j=0 adjustment.
% TS 38.213 V18.8.0 7.1.1, including bounded initial ramp-up (pp36-37).
% initialize=false reuses f for a later explicit allocation; it does not
% invent or reapply a decoded TPC command.
if nargin<3, initialize=true; end
validateattributes(initialize,{'logical'},{'scalar'});
validateattributes(grant.NumPRB,{'numeric'},{'real','scalar','finite','integer','positive'});
for name=["Pcmax_dBm","Msg3P0PUSCH_dBm","Msg3Alpha","Msg3DeltaTF_dB", ...
        "Msg3Numerology","PreamblePowerRampingCounter","PreamblePowerRampingStep_dB"]
    validateattributes(pc.(name),{'numeric'},{'real','scalar','finite'});
end
validateattributes(pc.Msg3Numerology,{'numeric'},{'integer','>=',0,'<=',6});
validateattributes(pc.PreamblePowerRampingCounter,{'numeric'},{'integer','>=',1});
validateattributes(pc.PreamblePowerRampingStep_dB,{'numeric'},{'nonnegative'});
validateattributes(pc.Msg3Alpha,{'numeric'},{'>=',0,'<=',1});
validateattributes(pc.Msg3Pathloss_dB,{'numeric'},{'real','scalar'});
if ~isnan(pc.Msg3Pathloss_dB)
    validateattributes(pc.Msg3Pathloss_dB,{'numeric'},{'finite','nonnegative'});
end
pc.Msg3NumPRBForPower=double(grant.NumPRB);
pc.Msg3BandwidthTerm_dB=10*log10(2^double(pc.Msg3Numerology)*double(grant.NumPRB));
base=pc.Msg3P0PUSCH_dBm+pc.Msg3BandwidthTerm_dB+ ...
    pc.Msg3Alpha*pc.Msg3Pathloss_dB+pc.Msg3DeltaTF_dB;
if initialize
    validateattributes(grant.TPCCommand,{'numeric'},{'real','scalar','finite','integer','>=',0,'<=',7});
    delta=2*double(grant.TPCCommand)-6;
    requestedRamp=(pc.PreamblePowerRampingCounter-1)*pc.PreamblePowerRampingStep_dB;
    ramp=NaN;
    if isfinite(base)
        ramp=min(max(0,pc.Pcmax_dBm-base-delta),requestedRamp);
    end
    pc.Msg3TPCCommand=double(grant.TPCCommand);
    pc.Msg3TPCDelta_dB=delta;
    pc.Msg3RequestedRamping_dB=requestedRamp;
    pc.Msg3AppliedRamping_dB=ramp;
    pc.Msg3ClosedLoopCorrection_dB=ramp+delta;
    pc.Msg3TPCSource="decoded_rar_table_8_2_2_with_initial_ramping_7_1_1";
else
    validateattributes(pc.Msg3ClosedLoopCorrection_dB,{'numeric'},{'real','scalar'});
end
pc.Msg3RequestedTxPower_dBm=base+pc.Msg3ClosedLoopCorrection_dB;
pc.Msg3TxPower_dBm=NaN;
pc.Msg3PowerHeadroom_dB=NaN;
if isfinite(pc.Msg3RequestedTxPower_dBm)
    pc.Msg3TxPower_dBm=min(pc.Pcmax_dBm,pc.Msg3RequestedTxPower_dBm);
    % Legacy field is cap-minus-applied, not an encoded MAC PHR claim.
    pc.Msg3PowerHeadroom_dB=pc.Pcmax_dBm-pc.Msg3TxPower_dBm;
end
end
