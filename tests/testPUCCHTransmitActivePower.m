function ok=testPUCCHTransmitActivePower()
setup6GRSimToolkit('Verbose',false);
for scs=[15 30]
    for format=0:4
        f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,[],'SCS',scs);
        tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,f.Assignment,f.Report);
        % Independent direct sample indexing: allocated useful symbols only.
        nfft=double(tx.OFDMInfo.Nfft); cp=double(tx.OFDMInfo.CyclicPrefixLengths(:));
        symbols=f.Assignment.Resource.Data.StartSymbol+(0:f.Assignment.Resource.Data.NumSymbols-1);
        offset=0; energy=0; count=0;
        for symbol=0:max(symbols)
            cpLength=cp(mod(symbol,numel(cp))+1);
            indices=offset+cpLength+(1:nfft);
            if ismember(symbol,symbols)
                energy=energy+sum(abs(tx.Waveform(indices,:)).^2,'all');
                count=count+nfft;
            end
            offset=offset+cpLength+nfft;
        end
        measured=10*log10(energy/count);
        assert(abs(measured-tx.Power.AppliedPowerdBm)<1e-9);
        assert(abs(measured-tx.Power.MeasuredWaveformPowerdBm)<1e-9);
        assert(tx.Power.MeasurementReferenceDomain=="specified_active_ofdm_symbols_excluding_cp");
        assert(isequal(tx.Power.MeasurementActiveSymbolIndices0,symbols));
        assert(tx.Power.MeasurementSampleCount==count);
        % Inactive symbols must remain silence, not a normalization target.
        assert(tx.Power.MeasuredSlotAveragePowerdBm<measured-3);
    end
end
data=f.Assignment.PowerControlState.Data; data.Mu=data.Mu+1;
bad=sixgr.phy.pucch.PUCCHTransmissionAssignment(f.Assignment.Data, ...
    f.Assignment.Resource,sixgr.phy.pucch.PUCCHPowerControlState(data), ...
    f.Assignment.SpatialRelationState);
assertRejected(@()sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,bad,f.Report));
data=f.Assignment.PowerControlState.Data; data.MRB=data.MRB+1;
bad=sixgr.phy.pucch.PUCCHTransmissionAssignment(f.Assignment.Data, ...
    f.Assignment.Resource,sixgr.phy.pucch.PUCCHPowerControlState(data), ...
    f.Assignment.SpatialRelationState);
assertRejected(@()sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,bad,f.Report));
ok=true;
end
function assertRejected(fcn)
observed="";
try, fcn(); catch e, observed=string(e.identifier); end
assert(observed=="sixgr:phy:pucch:PowerResourceMismatch");
end
