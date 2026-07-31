function [msg, meta] = decodeSIB1UPER(bitsOrBytes)
%DECODESIB1UPER Decode Release-18 BCCH-DL-SCH/SIB1 UPER.
bits = localNormalizeBits(bitsOrBytes);
if isempty(bits) || mod(numel(bits), 8) ~= 0
    error("sixgr:rrc:asn1:DecodeFailed", ...
        "SIB1 UPER payload must contain a nonempty whole number of octets.");
end
hex = sixgr.rrc.asn1.bitsToHex(bits);
try
    decoded = sixgr.rrc.asn1.invokeNRRRCCodec( ...
        "decode", struct("uper_hex", char(hex)));
catch cause
    failure = MException("sixgr:rrc:asn1:DecodeFailed", ...
        "Release-18 SIB1 UPER decode failed: %s", cause.message);
    failure = addCause(failure, cause);
    throwAsCaller(failure);
end
semantic = decoded.semantic;
cfg = localConfig(semantic);
msg = sixgr.rrc.asn1.buildBCCHDLSCHMessage( ...
    cfg, "CellID", double(semantic.cell_identity));
msg.message.c1.systemInformationBlockType1.cellSelectionInfo.q_RxLevMin = ...
    double(semantic.q_rx_lev_min);
msg.message.c1.systemInformationBlockType1.cellSelectionInfo.q_QualMin = ...
    double(semantic.q_qual_min);
msg.message.c1.systemInformationBlockType1.cellAccessRelatedInfo. ...
    cellReservedForOperatorUse = string(semantic.cell_reserved);
sixgr.rrc.asn1.validateSIB1ForScenario(msg, cfg);
meta = struct( ...
    "Profile", string(decoded.profile), ...
    "ASN1Release", "3GPP TS 38.331 V18.9.0", ...
    "Codec", string(decoded.codec), ...
    "CodecVersion", string(decoded.codec_version), ...
    "ASN1SchemaSHA256", ...
        "29e55635561822bf625d9170f050552d65047c334a3c0a8a47797c8df1985db5", ...
    "PayloadBits", double(decoded.num_bits), ...
    "BodyBits", double(decoded.num_bits), ...
    "TrailingTransportBlockPaddingBits", ...
        double(decoded.transport_padding_bits), ...
    "TransportBlockBits", double(decoded.transport_num_bits), ...
    "PayloadHash", string(decoded.sha256), ...
    "EncodedHex", string(decoded.uper_hex), ...
    "IndependentImplementation", ...
        "asn1tools-0.167.0 official-TS38331-i90", ...
    "SelfConsistencyOnly", false);
end

function cfg = localConfig(s)
cfg = struct();
cfg.phy.carrier.NCellID = double(s.cell_identity);
cfg.phy.carrier.SubcarrierSpacing = ...
    double(s.subcarrier_spacing_khz);
cfg.phy.carrier.SubcarrierSpacing_kHz = ...
    double(s.subcarrier_spacing_khz);
cfg.phy.carrier.NSizeGrid = double(s.carrier_bandwidth_rb);
cfg.phy.fc_Hz = localARFCNToHz(double(s.absolute_frequency_point_a));
cfg.frequency.band_name = "n" + string(round(double(s.band)));
cfg.initial_access.band_context = cfg.frequency.band_name;
cfg.initial_access.ssb.positions_in_burst = ...
    string(s.ssb_positions_in_burst);
cfg.initial_access.ssb.periodicity_ms = ...
    str2double(erase(string(s.ssb_periodicity), "ms"));
cfg.rrc.sib1.plmn = string(s.mcc) + string(s.mnc);
cfg.rrc.sib1.tac = double(s.tracking_area_code);
cfg.rrc.sib1.cellIdentity = double(s.cell_identity);
cfg.rrc.sib1.ssb_per_rach_choice = string(s.ssb_per_rach_choice);
cfg.rrc.sib1.cb_preambles_per_ssb = string(s.cb_preambles_per_ssb);
cfg.rrc.sib1.si_broadcast_status = string(s.si_broadcast_status);
cfg.rrc.sib1.si_periodicity = string(s.si_periodicity);
cfg.rrc.sib1.mapped_sib_type = string(s.mapped_sib_type);
cfg.rrc.sib1.si_window_length = string(s.si_window_length);
cfg.rrc.sib1.modification_period_coeff = ...
    string(s.modification_period_coeff);
cfg.rrc.sib1.default_paging_cycle = string(s.default_paging_cycle);
cfg.rrc.sib1.paging_frame_choice = string(s.paging_frame_choice);
cfg.rrc.sib1.paging_frame_offset = double(s.paging_frame_offset);
cfg.rrc.sib1.paging_ns = string(s.paging_ns);
cfg.rrc.sib1.time_alignment_timer = string(s.time_alignment_timer);
cfg.rrc.sib1.ss_pbch_block_power_dbm = ...
    double(s.ss_pbch_block_power_dbm);
for name = ["t300","t301","t310","n310","t311","n311","t319"]
    cfg.rrc.sib1.(name) = string(s.(name));
end
cfg.phy.sib1.coreset0Index = 0;
cfg.phy.sib1.searchSpaceZero = 0;
cfg.phy.mib.dmrsTypeAPosition = 2;
cfg.phy.prach.configurationIndex = ...
    double(s.prach_configuration_index);
cfg.phy.prach.rootSeqIndex = double(s.root_sequence_index);
cfg.phy.prach.zeroCorrelationZone = double(s.zero_correlation_zone);
cfg.phy.prach.nPreambles = double(s.num_preambles);
cfg.phy.prach.preambleFormat = localPreambleFormat( ...
    double(s.prach_configuration_index), string(s.root_sequence_choice), ...
    double(s.band), double(s.msg1_subcarrier_spacing_khz));
cfg.phy.prach.subcarrierSpacing_kHz = ...
    double(s.msg1_subcarrier_spacing_khz);
cfg.phy.prach.restrictedSet = localRestrictedSet( ...
    string(s.restricted_set_config));
cfg.random_access = struct( ...
    "configuration_index", double(s.prach_configuration_index), ...
    "root_sequence_index", double(s.root_sequence_index), ...
    "zero_correlation_zone", double(s.zero_correlation_zone), ...
    "preamble_count", double(s.num_preambles), ...
    "prach_format", string(cfg.phy.prach.preambleFormat), ...
    "subcarrier_spacing_khz", double(s.msg1_subcarrier_spacing_khz), ...
    "restricted_set", string(cfg.phy.prach.restrictedSet), ...
    "msg1_fdm", localFDMValue(string(s.msg1_fdm)), ...
    "frequency_start", double(s.msg1_frequency_start), ...
    "preamble_received_target_power_dbm", ...
        double(s.preamble_received_target_power_dbm), ...
    "preamble_trans_max", localEnumNumber(string(s.preamble_trans_max)), ...
    "power_ramping_step_db", localEnumNumber(string(s.power_ramping_step)), ...
    "ra_response_window_slots", localEnumNumber(string(s.ra_response_window)), ...
    "ra_contention_resolution_timer_slots", ...
        localEnumNumber(string(s.contention_resolution_timer)));
end

function format = localPreambleFormat(index, rootChoice, band, scsKHz)
% PRACH format is not an ASN.1 field. TS 38.331 carries the configuration
% index and root-sequence choice; resolve the actual format from the same
% TS 38.211 table-backed Toolbox object used by scenario validation.
if isempty(which("nrPRACHConfig"))
    error("sixgr:rrc:asn1:DecodeFailed", ...
        "Canonical PRACH-format recovery requires nrPRACHConfig.");
end
duplex = localBandDuplexMode(band);
try
    prach = nrPRACHConfig;
    prach.FrequencyRange = "FR1";
    prach.DuplexMode = char(duplex);
    prach.ConfigurationIndex = double(index);
    prach.SubcarrierSpacing = double(scsKHz);
    format = string(prach.Format);
catch cause
    failure = MException("sixgr:rrc:asn1:DecodeFailed", ...
        "Cannot resolve PRACH format for FR1 band n%d, %s, " + ...
        "configuration index %d and SCS %g kHz: %s", ...
        round(double(band)), duplex, round(double(index)), ...
        double(scsKHz), cause.message);
    failure = addCause(failure, cause);
    throwAsCaller(failure);
end

longFormat = any(upper(format) == ["0","1","2","3"]);
if (rootChoice == "l839") ~= longFormat
    error("sixgr:rrc:asn1:DecodeFailed", ...
        "Decoded PRACH root-sequence choice %s conflicts with resolved " + ...
        "format %s for configuration index %d.", ...
        rootChoice, format, round(double(index)));
end
end

function duplex = localBandDuplexMode(band)
% Concrete FR1 unpaired bands from TS 38.101-1. The bounded SIB1 profile
% rejects SUL/FR2 contexts rather than guessing a duplex table.
band = round(double(band));
unpaired = [34 38 39 40 41 46 47 48 50 51 53 54 ...
    77 78 79 90 96 101 102 104];
sul = [80 81 82 83 84 86 89 95 97 98 99];
if any(band == sul) || band < 1 || band > 256
    error("sixgr:rrc:asn1:DecodeFailed", ...
        "Band n%d is outside the bounded FR1 paired/unpaired SIB1 profile.", ...
        band);
elseif any(band == unpaired)
    duplex = "TDD";
else
    duplex = "FDD";
end
end

function value = localRestrictedSet(name)
switch name
    case "unrestrictedSet"
        value = "UnrestrictedSet";
    case "restrictedSetTypeA"
        value = "RestrictedSetTypeA";
    case "restrictedSetTypeB"
        value = "RestrictedSetTypeB";
    otherwise
        error("sixgr:rrc:asn1:DecodeFailed", ...
            "Unsupported decoded restricted-set enum '%s'.", name);
end
end

function value = localFDMValue(name)
names = ["one","two","four","eight"];
values = [1 2 4 8];
index = find(names == name, 1);
if isempty(index)
    error("sixgr:rrc:asn1:DecodeFailed", ...
        "Unsupported msg1-FDM enum '%s'.", name);
end
value = values(index);
end

function value = localEnumNumber(name)
text = regexprep(char(name), '^[A-Za-z]+', '');
value = str2double(text);
if ~isfinite(value)
    error("sixgr:rrc:asn1:DecodeFailed", ...
        "Cannot decode numeric ASN.1 enum '%s'.", name);
end
end

function hz = localARFCNToHz(arfcn)
if arfcn < 600000
    mhz = arfcn * 0.005;
elseif arfcn < 2016667
    mhz = 3000 + (arfcn - 600000) * 0.015;
else
    mhz = 24250.08 + (arfcn - 2016667) * 0.06;
end
hz = mhz * 1e6;
end

function bits = localNormalizeBits(x)
x = x(:);
if isempty(x)
    bits = int8([]);
elseif all(x == 0 | x == 1)
    bits = int8(x);
else
    bytes = uint8(x);
    bits = zeros(numel(bytes) * 8, 1, "int8");
    for ii = 1:numel(bytes)
        for jj = 1:8
            bits((ii - 1) * 8 + jj) = int8( ...
                bitget(bytes(ii), 9 - jj));
        end
    end
end
end
