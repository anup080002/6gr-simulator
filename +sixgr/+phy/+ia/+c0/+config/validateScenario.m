function validateScenario(cfg)
%VALIDATESCENARIO Fail-closed validation for production C0 configurations.
if ~(isstruct(cfg) && isscalar(cfg))
    error("sixgr:phy:ia:c0:config:BadTopLevel", ...
        "Resolved C0 IA config must be a scalar struct.");
end
s = sixgr.phy.ia.c0.config.schema();
required = string(s.required_paths);
for k = 1:numel(required)
    value = sixgr.util.structGet(cfg,required(k),[]);
    if isempty(value)
        error("sixgr:phy:ia:c0:config:MissingField", ...
            "Required IA configuration field '%s' is missing.",required(k));
    end
end
localEnum(cfg,"run.mode",string(s.allowed_run_modes));
localEnum(cfg,"meta.research_class",string(s.allowed_research_classes));
localEnum(cfg,"channel.model",string(s.allowed_channels));
localEnum(cfg,"waveform.normalization",string(s.allowed_normalizations));
localEnum(cfg,"waveform.candidate",string(s.allowed_candidates));
if string(cfg.meta.scenario_id) ~= "JIO_RAN1_126_AI_10_5_1_1_C0"
    error("sixgr:phy:ia:c0:config:PhaseGate", ...
        "Phase 1 permits only scenario JIO_RAN1_126_AI_10_5_1_1_C0.");
end
localScalar(cfg.carrier.frequency_hz,0,Inf,"carrier.frequency_hz");
localScalar(cfg.carrier.scs_khz,0,Inf,"carrier.scs_khz");
localInteger(cfg.carrier.n_size_grid,1,275,"carrier.n_size_grid");
localInteger(cfg.waveform.n_cell_id,0,1007,"waveform.n_cell_id");
localInteger(cfg.waveform.ssb_index,0,7,"waveform.ssb_index");
localInteger(cfg.waveform.candidate_start_symbol,0,10,"waveform.candidate_start_symbol");
if double(cfg.waveform.candidate_start_symbol) + 4 > 14
    error("sixgr:phy:ia:c0:config:SSBOutsideSlot", ...
        "waveform.candidate_start_symbol must leave four symbols inside one slot.");
end
if ~any(double(cfg.waveform.lmax) == [4 8 64])
    error("sixgr:phy:ia:c0:config:BadLmax", ...
        "waveform.lmax must be 4, 8, or 64.");
end
if double(cfg.waveform.pbch_payload_bits) ~= 24 || ...
        double(cfg.waveform.pbch_crc_bits) ~= 24 || ...
        double(cfg.waveform.pbch_total_information_bits) ~= 56
    error("sixgr:phy:ia:c0:config:PBCHInformationContract", ...
        "C0 requires a 24-bit BCH transport block, eight added timing bits, and 24-bit CRC (56 information bits total).");
end
localInteger(cfg.waveform.mib.bcch_bch_choice_bit,0,0, ...
    "waveform.mib.bcch_bch_choice_bit");
% Reuse the central production MIB semantic validator. It owns the exact
% 23-bit field packing and rejects invalid spare/range/enumeration values.
sixgr.phy.ia.MIBSemanticValidator.resolve( ...
    "CaseID",string(cfg.meta.scenario_id), ...
    "SystemFrameNumberMSB6",double(cfg.waveform.mib.system_frame_number_msb6), ...
    "SubCarrierSpacingCommon",string(cfg.waveform.mib.subcarrier_spacing_common), ...
    "SSBSubcarrierOffset",double(cfg.waveform.mib.ssb_subcarrier_offset), ...
    "DMRSTypeAPosition",string(cfg.waveform.mib.dmrs_type_a_position), ...
    "PDCCHConfigSIB1",double(cfg.waveform.mib.pdcch_config_sib1), ...
    "CellBarred",string(cfg.waveform.mib.cell_barred), ...
    "IntraFreqReselection",string(cfg.waveform.mib.intra_freq_reselection), ...
    "Spare",double(cfg.waveform.mib.spare));
if string(cfg.channel.model) ~= "AWGN" && string(cfg.channel.delay_profile) ~= string(cfg.channel.model)
    error("sixgr:phy:ia:c0:config:ChannelProfileMismatch", ...
        "channel.delay_profile must exactly match concrete channel.model for fading C0 execution.");
end
if any(contains(string(cfg.channel.model),["TDL" "CDL"])) && ...
        ~any(startsWith(string(cfg.channel.model),["TDL-" "CDL-"]))
    error("sixgr:phy:ia:c0:config:ConcreteProfileRequired", ...
        "Fading channel.model must be a concrete TDL-* or CDL-* profile.");
end
localInteger(cfg.mimo.num_tx_antennas,1,64,"mimo.num_tx_antennas");
localInteger(cfg.mimo.num_rx_antennas,1,64,"mimo.num_rx_antennas");
localProbability(cfg.false_alarm.target_probability,"false_alarm.target_probability");
localInteger(cfg.false_alarm.calibration_trials,1,Inf,"false_alarm.calibration_trials");
localInteger(cfg.false_alarm.validation_trials,1,Inf,"false_alarm.validation_trials");
localInteger(cfg.run.max_trials_per_snr,1,Inf,"run.max_trials_per_snr");
localInteger(cfg.run.min_errors_per_snr,0,Inf,"run.min_errors_per_snr");
localScalar(cfg.statistics.confidence_level,0,1,"statistics.confidence_level");
if ~logical(cfg.output.prohibit_svg)
    error("sixgr:phy:ia:c0:config:RasterPolicy", ...
        "output.prohibit_svg must be true.");
end
end

function localEnum(cfg,path,allowed)
value = string(sixgr.util.structGet(cfg,path,""));
if ~isscalar(value) || ~any(strcmpi(value,allowed))
    error("sixgr:phy:ia:c0:config:BadEnum", ...
        "%s='%s' is unsupported; allowed values are %s.",path,value,strjoin(allowed,", "));
end
end
function localScalar(v,lo,hi,name)
if ~(isnumeric(v) && isscalar(v) && isreal(v) && isfinite(v) && v > lo && v <= hi)
    error("sixgr:phy:ia:c0:config:BadScalar", ...
        "%s must be in (%g,%g].",name,lo,hi);
end
end
function localInteger(v,lo,hi,name)
if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v >= lo && v <= hi && v == round(v))
    error("sixgr:phy:ia:c0:config:BadInteger", ...
        "%s must be an integer in [%g,%g].",name,lo,hi);
end
end
function localProbability(v,name)
if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v > 0 && v < 1)
    error("sixgr:phy:ia:c0:config:BadProbability", ...
        "%s must be strictly between zero and one.",name);
end
end
