function ok = testRARULGrantStandardsCodec()
% Independent field-position/RIV checks, not merely encoder-decoder agreement.
ra = localContext(25);
ra.Msg3PUSCH.NumPRB = 24;
ra.Msg3PUSCH.MCS = 10;
ra.Msg3PUSCH.Modulation = "16QAM";
ra.Msg3PUSCH.TargetCodeRate = 340/1024;
g = sixgr.mac.ra.buildRARULGrant(ra);
expected = int8('000000001001010000010100110'.' - '0');
assert(isequal(g.BitVector, expected), ...
    "RAR bits must be hopping:1, type-1 FDRA:14, TDRA:4, MCS:4, TPC:3, reserved CSI:1.");
assert(g.ResourceIndicationValue == 74 && g.MCS == 10 && ...
    g.Modulation == "16QAM" && g.TargetCodeRate == 340/1024 && g.TPCDelta_dB == 0);
rar = sixgr.mac.ra.encodeMACRAR("RAPID", 7, "TimingAdvanceCommand", 28, ...
    "TemporaryCRNTI", 4660, "ULGrant", g);
% Deliberately contradict the Tx-side planned MCS. Receiver interpretation
% must depend on the received index plus common table, not that planned row.
rxContext = ra;
rxContext.Msg3PUSCH.MCS = 0;
rxContext.Msg3PUSCH.Modulation = "QPSK";
rxContext.Msg3PUSCH.TargetCodeRate = 120/1024;
decoded = sixgr.mac.ra.decodeMACRAR(rar.Bits, rxContext);
fromBytes = sixgr.mac.ra.decodeMACRAR(rar.Bytes, rxContext);
assert(isequal(fromBytes.ULGrant.BitVector, decoded.ULGrant.BitVector));
assert(decoded.ULGrant.MCS == 10 && decoded.ULGrant.Modulation == "16QAM" && ...
    decoded.ULGrant.TargetCodeRate == 340/1024 && decoded.TemporaryCRNTI == 4660);
pc = struct("Msg3RequestedTxPower_dBm",20,"Msg3ClosedLoopCorrection_dB",0, ...
    "Msg3NumPRBForPower",24,"Pcmax_dBm",23);
powerGrant = decoded.ULGrant; powerGrant.TPCCommand = 7;
power = sixgr.mac.ra.applyRARGrantPowerCommand(pc,powerGrant);
assert(power.Msg3RequestedTxPower_dBm == 28 && power.Msg3TxPower_dBm == 23 && ...
    power.Msg3ClosedLoopCorrection_dB == 8);
pc.Msg3RequestedTxPower_dBm = NaN;
power = sixgr.mac.ra.applyRARGrantPowerCommand(pc,powerGrant);
assert(isnan(power.Msg3RequestedTxPower_dBm), "Missing power must not be replaced by a TPC-derived synthetic budget.");

for n = [1 6 25 51 106 180 181 275]
    for start = unique([0 floor(n/3) n-1])
        for count = unique([1 min(24,n-start) n-start])
            c = localContext(n);
            c.Msg3PUSCH.PRBStart = start;
            c.Msg3PUSCH.NumPRB = count;
            if count-1 <= floor(n/2)
                riv = n*(count-1)+start;
            else
                riv = n*(n-count+1)+(n-1-start);
            end
            if riv >= 2^14
                localThrows(@() sixgr.mac.ra.buildRARULGrant(c), "sixgr:mac:ra:UnrepresentableRARFDRA");
            else
                out = sixgr.mac.ra.buildRARULGrant(c);
                assert(out.ResourceIndicationValue == riv && out.PRBStart == start && out.NumPRB == count);
            end
        end
    end
end

% Nonzero unused FDRA MSBs are truncated, as required for small BWPs.
bits = g.BitVector; bits(2) = 1;
out = sixgr.mac.ra.RARULGrantCodec.decode(bits, ra);
assert(out.PRBStart == 0 && out.NumPRB == 24);
% MCS/TPC boundaries and transform precoding's higher-layer authority.
for transform = [false true]
    c = localContext(51); c.Msg3PUSCH.TransformPrecoding = transform;
    for mcs = [0 10 15]
        for tpc = 0:7
            c.RARGrantConfig.tpc_command = tpc;
            out = sixgr.mac.ra.RARULGrantCodec.encode(c, mcs);
            assert(out.MCS == mcs && out.TPCCommand == tpc && out.TPCDelta_dB == 2*tpc-6);
            assert(out.TransformPrecoding == transform && ~out.CSIRequest);
        end
    end
end
localThrows(@() sixgr.mac.ra.RARULGrantCodec.encode(ra,16), "sixgr:mac:ra:InvalidRARULGrant");
wrongTable = ra; wrongTable.Msg3PUSCH.MCSTable = "qam256";
localThrows(@() sixgr.mac.ra.RARULGrantCodec.decode(g.BitVector,wrongTable), "sixgr:mac:ra:InvalidRARMCSTable");
localThrows(@() sixgr.mac.ra.encodeMACRAR("RAPID",64,"ULGrant",g), "sixgr:mac:ra:InvalidMACRARField");
localThrows(@() sixgr.mac.ra.encodeMACRAR("TimingAdvanceCommand",1.5,"ULGrant",g), "sixgr:mac:ra:InvalidMACRARField");
localThrows(@() sixgr.mac.ra.decodeMACRAR(rar.Bits(1:end-1),ra), "sixgr:mac:ra:InvalidMACRARInput");
badBytes = rar.Bytes; badBytes(1) = bitor(badBytes(1),uint8(128));
localThrows(@() sixgr.mac.ra.decodeMACRAR(badBytes,ra), "sixgr:mac:ra:UnsupportedMACRARSubheader");
bits = g.BitVector; bits(1) = 1;
localThrows(@() sixgr.mac.ra.RARULGrantCodec.decode(bits,ra), "sixgr:mac:ra:UnsupportedRARHopping");
bits = g.BitVector; bits(19) = 1;
row2 = sixgr.mac.ra.RARULGrantCodec.decode(bits,ra);
assert(row2.TimeResourceAssignment == 1 && row2.SymbolStart == 0 && ...
    row2.NumSymbols == 12 && row2.MappingType == "A", ...
    "A received TDRA index must not be replaced by the transmitter's configured index 0.");
bits = g.BitVector; bits(2:15) = 1; % 511 is not a valid RIV for N=25.
localThrows(@() sixgr.mac.ra.RARULGrantCodec.decode(bits,ra), "sixgr:mac:ra:InvalidRARFDRA");
bits = g.BitVector; bits(2) = 2;
localThrows(@() sixgr.mac.ra.RARULGrantCodec.decode(bits,ra), "sixgr:mac:ra:InvalidULGrantBits");
for scenarioName = ["lls_causal_access_to_data_wiring", "lls_causal_access_to_data_wiring_tdd"]
    sc = sixgr.lls6g.config.loadScenarioConfig(fullfile("simulator","configs","scenarios",scenarioName+".yaml"));
    assert(sc.Data.random_access.rar_grant.tpc_command == 3);
    assert(sc.Data.random_access.rar_grant.field_layout == "licensed_27bit");
    bad = sc.Data; bad.random_access.rar_grant.tpc_command = 8;
    localThrows(@() sixgr.lls6g.config.validateScenarioConfig(bad), "sixgr:lls6g:config:UnsupportedRARGrantPolicy");
end
ok = true;
fprintf("PASS testRARULGrantStandardsCodec: independent field positions, type-1 RIV, decoded MCS and TPC.\n");
end

function ra = localContext(n)
ra = struct("NSizeGrid",n, "CarrierSCSkHz",15, "CarrierCyclicPrefix","normal", ...
    "RARGrantConfig",struct("field_layout","licensed_27bit", ...
    "frequency_hopping",false,"time_resource_assignment",0,"tpc_command",3), ...
    "Msg3PUSCH",struct("PRBStart",0,"NumPRB",1,"SymbolStart",0,"NumSymbols",14, ...
    "MCS",0,"MCSTable","qam64","Modulation","QPSK","TargetCodeRate",120/1024, ...
    "TransformPrecoding",false,"EnablePTRS",false,"RV",0,"NLayers",1));
end

function localThrows(f, id)
try
    f();
catch e
    assert(string(e.identifier) == id, "Expected %s, received %s: %s", id,e.identifier,e.message);
    return;
end
error("testRARULGrantStandardsCodec:MissingRejection", "Expected rejection %s.",id);
end
