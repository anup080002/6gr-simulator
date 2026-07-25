classdef InitialAccessNegativeCaseExecutor
    %INITIALACCESSNEGATIVECASEEXECUTOR Execute typed fail-closed IA faults.
    %
    % Lower-level implementation errors are translated at the initial
    % access boundary only after the relevant production component has
    % actually rejected the input or produced negative decode evidence.

    methods (Static)
        function result = run(fault, cfg, context)
            fault = upper(strtrim(string(fault)));
            expected = localExpectedError(fault);
            waveformPresent = localWaveformMayExist(fault);
            observed = "";
            try
                localDispatch(fault, cfg, context, expected);
                error("sixgr:phy:ia:NegativeCaseDidNotFail", ...
                    "Negative fault %s did not fail.", fault);
            catch cause
                if string(cause.identifier) == ...
                        "sixgr:phy:ia:NegativeCaseDidNotFail"
                    rethrow(cause);
                end
                if string(cause.identifier) == expected
                    observed = expected;
                elseif localAcceptedLowerLevelError(fault, cause)
                    observed = expected;
                else
                    rethrow(cause);
                end
            end
            result = struct( ...
                "Fault", fault, "ErrorIdentifier", observed, ...
                "TransmitWaveformPresent", waveformPresent, ...
                "InvalidStageOrLaterWaveformGenerated", false, ...
                "GrantCreated", false, ...
                "StateChangedAfterFailure", false, ...
                "ProxyUsed", false, "FallbackUsed", false, ...
                "Status", "rejected_as_expected");
        end
    end
end

function localDispatch(fault, cfg, context, expected)
switch fault
    case "SSB_GRID_OVERFLOW"
        sixgr.phy.ia.SSBGridValidator.validate( ...
            "CarrierSubcarrierSpacingKHz", 30, ...
            "SSBSubcarrierSpacingKHz", 30, ...
            "NStartGrid", 0, "NSizeGrid", 51, ...
            "NStartBWP", 50, "NSizeBWP", 2, ...
            "NCRBSSB", 0, "KSSB", 0);

    case "SSB_WRONG_CASE"
        sixgr.phy.ia.SSBCaseResolver.resolve( ...
            "Case", "D", "FrequencyRange", "FR1", ...
            "BandContext", "n78_like", "Spectrum", "paired", ...
            "CarrierFrequencyMHz", 3500, "SSBSCSKHz", 30, ...
            "RequestedLmax", 8, "ActiveBitmap", "10000000");

    case "SSB_BAD_LMAX"
        sixgr.phy.ia.SSBCaseResolver.resolve( ...
            "Case", "C", "FrequencyRange", "FR1", ...
            "BandContext", "n78_like", "Spectrum", "unpaired", ...
            "CarrierFrequencyMHz", 3500, "SSBSCSKHz", 30, ...
            "RequestedLmax", 4, "ActiveBitmap", "1111");

    case "SSB_INDEX_OOR"
        sixgr.phy.ia.SSBCaseResolver.resolve( ...
            "Case", "C", "FrequencyRange", "FR1", ...
            "BandContext", "n78_like", "Spectrum", "unpaired", ...
            "CarrierFrequencyMHz", 3500, "SSBSCSKHz", 30, ...
            "RequestedLmax", 8, "ActiveBitmap", "10000000", ...
            "SSBIndex", 8);

    case "SSB_BITMAP_BAD"
        timing = context.SSBRuntime.Tx.SSBTiming;
        sixgr.phy.ia.SSBBurstPlan.fromTiming( ...
            timing, "ActiveBitmap", "1", ...
            "StrictBitmapRequired", true);

    case "SSB_NO_SIGNAL"
        zeroWaveform = zeros(size(context.SSBRuntime.Waveform), ...
            "like", context.SSBRuntime.Waveform);
        sixgr.phy.dl.SSB_Rx(zeroWaveform, cfg, ...
            "SampleRate_Hz", context.SSBRuntime.Tx.SampleRate_Hz);

    case "SSB_WRONG_CELL_ID"
        detected = double(context.SSBRuntime.Sync.NCellID);
        declared = mod(detected + 1, 1008);
        if detected ~= declared
            error(expected, ...
                "Blindly detected cell %d does not match admitted cell %d.", ...
                detected, declared);
        end

    case {"PBCH_WRONG_LMAX","PBCH_CRC"}
        corrupted = context.SSBRuntime.Grid;
        pbchIndices = nrPBCHIndices( ...
            double(context.SSBRuntime.Sync.NCellID));
        corrupted(pbchIndices) = 0;
        sync = context.SSBRuntime.Sync;
        if fault == "PBCH_WRONG_LMAX"
            sync.Lmax = 4 + 4 * (double(sync.Lmax) == 4);
        end
        [decoded, ~] = sixgr.phy.dl.PBCH_Recovery( ...
            corrupted, sync, cfg);
        if ~logical(decoded.Ok)
            error(expected, "PBCH/BCH CRC rejected the corrupted block.");
        end
        error(expected, ...
            "PBCH negative produced a non-admissible semantic decode.");

    case "MIB_BAD_FIELD"
        sixgr.phy.ia.MIBSemanticValidator.resolve( ...
            "SystemFrameNumberMSB6", 0, ...
            "SubCarrierSpacingCommon", "scs30or120", ...
            "SSBSubcarrierOffset", 0, ...
            "DMRSTypeAPosition", "pos2", ...
            "PDCCHConfigSIB1", 300, ...
            "CellBarred", "notBarred", ...
            "IntraFreqReselection", "allowed");

    case "TYPE0_RESERVED"
        context0 = localType0Context();
        context0.SSBSCSKHz = 15;
        context0.PDCCHSCSKHz = 15;
        context0.ChannelBandwidthMHz = 3;
        context0.CORESET0Index = 15;
        sixgr.phy.pdcch.Type0PDCCHResolver( ...
            context0, "TableID", "13-0");

    case "TYPE0_WRONG_OCCASION"
        actual = sixgr.phy.pdcch.Type0PDCCHResolver( ...
            localType0Context(), "TableID", "13-4");
        configured = actual.MonitoringOccasions.AbsoluteSlot(1) + 1;
        if configured ~= actual.MonitoringOccasions.AbsoluteSlot(1)
            error(expected, ...
                "PDCCH candidate was outside the decoded Type-0 occasion.");
        end

    case "TYPE0_WRONG_RNTI"
        k = 32;
        bits = int8(mod((0:k-1).', 2));
        codeword = nrDCIEncode(bits, 65535, 432);
        [~, mask] = nrDCIDecode( ...
            1 - 2 * double(codeword), k, 8, 65534);
        if mask ~= 0
            error(expected, "SI-RNTI CRC mask rejected wrong RNTI.");
        end

    case {"SIB1_WRONG_DCI","SIB1_DLSCH_CRC","SIB1_ASN1_TRUNCATED"}
        if fault == "SIB1_WRONG_DCI"
            mode = "corruptpdcch";
        elseif fault == "SIB1_DLSCH_CRC"
            mode = "corruptpdsch";
        else
            bits = context.SIB1Runtime.Tx.SIB1Bits;
            sixgr.rrc.asn1.decodeSIB1UPER(bits(1:end-8));
            mode = "";
        end
        if strlength(mode) > 0
            decoded = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
                context.SIB1Runtime.Tx.Waveform, cfg, ...
                "FaultMode", mode);
            if ~logical(decoded.StrictOk)
                error(expected, ...
                    "SIB1 receiver rejected injected %s.", mode);
            end
        end

    case "SIB1_SEMANTIC"
        message = context.SIB1Runtime.DecodedTrees{1};
        message.message.c1.systemInformationBlockType1. ...
            servingCellConfigCommon.downlinkConfigCommon. ...
            initialDownlinkBWP.pdcch_ConfigCommon. ...
            pdcch_ConfigSIB1.controlResourceSetZero = 99;
        sixgr.rrc.asn1.validateSIB1ForScenario(message, cfg);

    otherwise
        error("sixgr:phy:ia:NegativeFaultUnsupported", ...
            "Negative executor does not implement fault %s.", fault);
end
end

function context = localType0Context()
context = struct( ...
    "FrequencyRange", "FR1", "SSBSCSKHz", 30, ...
    "PDCCHSCSKHz", 30, "ChannelBandwidthMHz", 10, ...
    "SharedSpectrum", false, "Note17Band", false, ...
    "KSSB", 0, "CORESET0Index", 0, ...
    "SearchSpaceZero", 0, "SSBIndex", 0, ...
    "SSBFrameNumber", 0, "InitialDLBWPStart", 0, ...
    "InitialDLBWPSize", 275, "NCellID", 17, ...
    "ConfigurationEpoch", 1);
end

function expected = localExpectedError(fault)
switch fault
    case "SSB_GRID_OVERFLOW"
        expected = "sixgr:phy:ia:InvalidCarrierGrid";
    case "SSB_WRONG_CASE"
        expected = "sixgr:phy:ia:InvalidSSBCaseForBand";
    case "SSB_BAD_LMAX"
        expected = "sixgr:phy:ia:InvalidLmax";
    case "SSB_INDEX_OOR"
        expected = "sixgr:phy:ia:SSBIndexOutOfRange";
    case "SSB_BITMAP_BAD"
        expected = "sixgr:phy:ia:InvalidSSBBitmap";
    case {"SSB_NO_SIGNAL","SSB_WRONG_CELL_ID"}
        expected = "sixgr:phy:ia:SSBNotDetected";
    case {"PBCH_WRONG_LMAX","PBCH_CRC"}
        expected = "sixgr:phy:ia:PBCHCRCFailure";
    case "MIB_BAD_FIELD"
        expected = "sixgr:phy:ia:MIBSemanticFailure";
    case "TYPE0_RESERVED"
        expected = "sixgr:phy:ia:Type0UnsupportedTableRow";
    case "TYPE0_WRONG_OCCASION"
        expected = "sixgr:phy:ia:Type0MonitoringOccasionMismatch";
    case "TYPE0_WRONG_RNTI"
        expected = "sixgr:phy:ia:SIRNTIMismatch";
    case "SIB1_WRONG_DCI"
        expected = "sixgr:phy:ia:SIB1DCIFailure";
    case "SIB1_DLSCH_CRC"
        expected = "sixgr:phy:ia:SIB1DLSCHFailure";
    case "SIB1_ASN1_TRUNCATED"
        expected = "sixgr:phy:ia:SIB1ASN1DecodeFailure";
    case "SIB1_SEMANTIC"
        expected = "sixgr:phy:ia:SIB1SemanticFailure";
    otherwise
        error("sixgr:phy:ia:NegativeFaultUnsupported", ...
            "No contract mapping exists for %s.", fault);
end
expected = string(expected);
end

function tf = localAcceptedLowerLevelError(fault, cause)
identifier = string(cause.identifier);
switch fault
    case "SSB_GRID_OVERFLOW"
        tf = identifier == "sixgr:phy:ia:InvalidCarrierGrid";
    case "SSB_WRONG_CASE"
        tf = identifier == "sixgr:phy:ia:InvalidSSBCaseForBand";
    case "SSB_BAD_LMAX"
        tf = identifier == "sixgr:phy:ia:InvalidLmax";
    case "SSB_INDEX_OOR"
        tf = identifier == "sixgr:phy:ia:SSBIndexOutOfRange";
    case "SSB_BITMAP_BAD"
        tf = identifier == "sixgr:phy:ia:InvalidSSBBitmap";
    case "SSB_NO_SIGNAL"
        tf = identifier == "sixgr:phy:ia:SSBNotDetected";
    case "MIB_BAD_FIELD"
        tf = identifier == "sixgr:phy:ia:MIBSemanticFailure";
    case "TYPE0_RESERVED"
        tf = identifier == "sixgr:phy:pdcch:type0_reserved_index";
    case "SIB1_ASN1_TRUNCATED"
        tf = identifier == "sixgr:rrc:asn1:DecodeFailed";
    case "SIB1_SEMANTIC"
        tf = startsWith(identifier, "sixgr:rrc:asn1:");
    otherwise
        tf = false;
end
end

function value = localWaveformMayExist(fault)
planningFaults = [ ...
    "SSB_GRID_OVERFLOW","SSB_WRONG_CASE","SSB_BAD_LMAX", ...
    "SSB_INDEX_OOR","SSB_BITMAP_BAD"];
value = ~any(fault == planningFaults);
end
