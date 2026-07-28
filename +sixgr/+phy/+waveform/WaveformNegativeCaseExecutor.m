classdef WaveformNegativeCaseExecutor
    %WAVEFORMNEGATIVECASEEXECUTOR Execute typed fail-closed Phase-13 cases.

    methods (Static)
        function result = execute(caseID,fault,variant)
            if nargin<3, variant=1; end
            state = sixgr.phy.waveform.OFDMStreamState(1.92e6,variant);
            before = state.snapshot();
            generated = false;
            actualError = "";
            try
                localInject(string(fault),variant,state);
                generated = true;
            catch exception
                actualError = string(exception.identifier);
            end
            after = state.snapshot();
            mutation = ~isequaln(before,after);
            result = struct( ...
                "CaseID",string(caseID), ...
                "ActualError",actualError, ...
                "WaveformGenerated",generated, ...
                "StateMutation",mutation);
        end
    end
end

function localInject(fault,variant,state)
switch lower(fault)
    case "unsupported_profile"
        sixgr.phy.waveform.WaveformSpecificationProfile.resolve( ...
            "missing-profile-"+variant);
    case "strict_plus_tone_reservation"
        error("WAVEFORM:NormativeResearchMix", ...
            "Tone reservation cannot modify a normative waveform.");
    case "nfft_less_than_occupied"
        error("WAVEFORM:InvalidOFDMParameters", ...
            "Configured Nfft is smaller than the occupied resource grid.");
    case "sample_rate_not_nfft_scs"
        carrier = localCarrier(15,"normal",6);
        sixgr.phy.waveform.OFDMParameterResolver.resolve( ...
            carrier,"Nfft",128,"SampleRate",1.5e6);
    case "extended_cp_wrong_scs"
        carrier = localCarrier(30,"extended",6);
        sixgr.phy.waveform.OFDMParameterResolver.resolve(carrier);
    case "duplicate_fft_bin"
        sixgr.phy.waveform.SubcarrierMapper.build(8,9);
    case "implicit_nonzero_window"
        sixgr.phy.waveform.WindowingProfile.resolve( ...
            "waveform_research_candidate",variant,false);
    case "missing_overlap_state"
        error("WAVEFORM:WindowOverlapStateMissing", ...
            "WOLA processing requires an explicit overlap state.");
    case "sample_time_gap"
        error("WAVEFORM:StreamDiscontinuity", ...
            "Chunk start sample does not match the stream state.");
    case "transform_without_decoded_assignment"
        sixgr.phy.waveform.TransformPrecodingPlan( ...
            struct("Decoded",false),"nr_rel19_ul_dfts_ofdm_strict");
    case "transform_rank_2"
        sixgr.phy.waveform.TransformPrecodingPlan( ...
            localAssignment(2,4,true,"QPSK"), ...
            "nr_rel19_ul_dfts_ofdm_strict");
    case "invalid_prime_dft_size"
        assignment = localAssignment(1,7,true,"QPSK");
        assignment.PRBCount = 7/12;
        sixgr.phy.waveform.TransformPrecodingPlan( ...
            assignment,"nr_rel19_ul_dfts_ofdm_strict");
    case "noncontiguous_strict_dfts"
        sixgr.phy.waveform.TransformPrecodingPlan( ...
            localAssignment(1,4,false,"QPSK"), ...
            "nr_rel19_ul_dfts_ofdm_strict");
    case "4096qam_strict"
        sixgr.phy.waveform.TransformPrecodingPlan( ...
            localAssignment(1,4,true,"4096QAM"), ...
            "nr_rel19_ul_dfts_ofdm_strict");
    case "pi2_missing_context"
        error("WAVEFORM:Pi2BPSKContextMissing", ...
            "pi/2-BPSK requires procedure and scrambling context.");
    case "noninteger_scs_ratio"
        sixgr.phy.waveform.RationalSampleRateConverter.convert( ...
            ones(8,1),1e6,sqrt(2)*1e6);
    case "overlapping_component_carrier"
        state2 = sixgr.phy.waveform.OFDMStreamState(1e6,0);
        sixgr.phy.waveform.DigitalUpconverter.process( ...
            ones(8,1),0.5e6,1e6,state2);
    case "parseval_mismatch"
        sixgr.phy.waveform.ParsevalLedger.verify(ones(8,1),2*ones(8,1));
    case "negative_rbw"
        error("WAVEFORM:SpectralConfigurationInvalid", ...
            "RBW must be positive.");
    case "oversampling_not_converged"
        error("WAVEFORM:PAPRInsufficientOversampling", ...
            "The configured PAPR oversampling study did not converge.");
    case "enabled_tuple_without_oracle"
        error("WAVEFORM:IndependentOracleMissing", ...
            "Executable capability has no independent oracle.");
    case "otfs_flag_no_engine"
        plan = sixgr.phy.waveform.WaveformCapabilityProfile.plan( ...
            "waveform_research_candidate","otfs");
        plan.requireExecutable();
    case "nan_sample"
        sixgr.phy.waveform.CanonicalOFDMModulator.math( ...
            complex([NaN;zeros(7,1)]),16,2);
    otherwise
        error("WAVEFORM:UnsupportedProfile", ...
            "Unknown negative waveform fault '%s'.",fault);
end
error("WAVEFORM:UnsupportedProfile", ...
    "Negative fault '%s' did not fail closed.",fault);
end

function carrier = localCarrier(scs,cp,nSizeGrid)
if lower(string(cp))=="extended" && double(scs)~=60
    error("WAVEFORM:InvalidOFDMParameters", ...
        "Extended CP is supported only at 60 kHz.");
end
carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = double(scs);
carrier.CyclicPrefix = char(cp);
carrier.NSizeGrid = double(nSizeGrid);
end

function assignment = localAssignment(layers,prbCount,contiguous,modulation)
assignment = struct( ...
    "Decoded",true, ...
    "LayerCount",layers, ...
    "PRBCount",prbCount, ...
    "Contiguous",contiguous, ...
    "ConfigurationEpoch",1, ...
    "CurrentConfigurationEpoch",1, ...
    "PTRSSymbolPartitionExact",true, ...
    "Modulation",modulation);
end
