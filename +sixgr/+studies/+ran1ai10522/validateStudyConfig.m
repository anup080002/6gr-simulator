function cfg = validateStudyConfig(cfg)
%VALIDATESTUDYCONFIG Fail-closed semantic validation beyond the main schema.
required = ["study","pdschDmrsStudy"];
for name = required
    if ~isfield(cfg, name)
        error("sixgr:ran1ai10522:MissingConfigSection", ...
            "Required configuration section %s is missing.", name);
    end
end
s = cfg.study; d = cfg.pdschDmrsStudy;
if string(s.schema_version) ~= "sixgr.ran1.10_5_2_2/v1" || ...
        string(s.id) ~= "ran1_ai_10_5_2_2_pdsch_dmrs_wideband"
    error("sixgr:ran1ai10522:BadStudySchema", ...
        "Study schema/id does not match the 10.5.2.2 contract.");
end
if ~logical(s.strict) || ~logical(s.prohibit_fallback)
    error("sixgr:ran1ai10522:StrictModeRequired", ...
        "study.strict and study.prohibit_fallback must both be true.");
end
sixgr.studies.ran1ai10522.EvidenceClass.validate(s.evidence_class);
if lower(string(s.controlling_prompt_sha256)) ~= ...
        "680db7439450b55b074342284d435cde95671c947bdae220adb6d8221f22e5cc"
    error("sixgr:ran1ai10522:PromptHashMismatch", ...
        "The resolved configuration is not bound to the inspected prompt hash.");
end
if logical(s.common_evm_verified) && strlength(string(s.controlling_tdoc_path)) == 0
    error("sixgr:ran1ai10522:UnverifiedCommonEVM", ...
        "Common-EVM execution requires an identified controlling document.");
end
if ~logical(d.enabled)
    error("sixgr:ran1ai10522:StudyDisabled", ...
        "pdschDmrsStudy.enabled must be true for this suite.");
end
td = d.timeDomain;
if ~ismember(double(td.X), [1 2 4]) || ...
        ~strcmp(string(td.placementRule), "floor_remainder_long_gaps_at_end") || ...
        ~logical(td.noImplicitShift)
    error("sixgr:ran1ai10522:InvalidTimeDomainPolicy", ...
        "X, placementRule or noImplicitShift violates the exact study contract.");
end
expected = sixgr.studies.ran1ai10522.TimeDomainProfile.supportedL(double(td.X));
if ~isequal(double(td.supportedL(:)).', expected)
    error("sixgr:ran1ai10522:SupportedLMismatch", ...
        "timeDomain.supportedL is inconsistent with X.");
end
if ~all(ismember([1 28], double(td.allocationSymbolCounts(:)).'))
    error("sixgr:ran1ai10522:IncompleteAllocationGrid", ...
        "allocationSymbolCounts must span N_sym=1:28.");
end
if logical(d.nestedFamily.enabled) && double(d.nestedFamily.Lmax) > max(expected)
    error("sixgr:ran1ai10522:NestedLMaxUnsupported", ...
        "nestedFamily.Lmax exceeds the configured X capability.");
end
if logical(d.nestedFamily.allowMixedX)
    error("sixgr:ran1ai10522:MixedXRuleUnavailable", ...
        "Mixed-X nesting is rejected until an explicit normative rule is configured.");
end
indexModes = string(d.frequencyDomain.sequenceIndexingModes(:));
if ~all(ismember(indexModes, ["common_grid","reset_per_bundle","reset_per_region"]))
    error("sixgr:ran1ai10522:InvalidSequenceIndexing", ...
        "frequencyDomain.sequenceIndexingModes contains an unsupported mode.");
end
if logical(d.wideband.enabled)
    sixgr.studies.ran1ai10522.FrequencyStructure.bundles( ...
        double(d.wideband.processingRegionsPrb), ...
        double(d.frequencyDomain.bundleSizesPrb(1)));
end
interleaveMode = string(d.interleaving.mode);
if interleaveMode == "bundle_cross_region" && ...
        ~logical(d.wideband.receiverCapabilityCrossRegion)
    error("sixgr:ran1ai10522:CrossRegionCapabilityRequired", ...
        "bundle_cross_region requires receiverCapabilityCrossRegion=true.");
end
if string(d.ptrs.mode) == "common" && logical(d.wideband.enabled) && ...
        ~logical(d.wideband.coherentCrossRegion)
    error("sixgr:ran1ai10522:CommonPTRSRequiresCoherence", ...
        "Common PT-RS cannot be used across incoherent processing regions.");
end
if ~logical(d.tbMapping.independentEncodingRequired) || ...
        ~logical(d.codewordLayerMapping.prohibitSilentCollapse) || ...
        ~logical(d.mrss.noImplicitShift) || ~logical(d.mrss.noSequenceReset)
    error("sixgr:ran1ai10522:TruthGuardDisabled", ...
        "Independent coding/no-collapse/no-shift/no-reset guards must remain enabled.");
end
e = s.execution; o = s.output;
positiveInteger(e.transport_blocks_per_point, "transport_blocks_per_point");
positiveInteger(e.maximum_transport_blocks_per_point, "maximum_transport_blocks_per_point");
positiveInteger(e.channel_realizations_per_point, "channel_realizations_per_point");
snr = double(e.snr_points_db(:));
if isempty(snr) || any(~isfinite(snr)) || any(diff(snr) <= 0)
    error("sixgr:ran1ai10522:InvalidSNRGrid", ...
        "study.execution.snr_points_db must be finite and strictly increasing.");
end
if ~logical(o.save_csv) || ~logical(o.save_png) || ...
        logical(o.save_svg) || logical(o.save_pdf) || ~logical(o.raster_only)
    error("sixgr:ran1ai10522:RasterOutputContract", ...
        "The configured user contract requires CSV and PNG output with SVG/PDF disabled.");
end
end

function positiveInteger(value, name)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value >= 1 && value == fix(value))
    error("sixgr:ran1ai10522:InvalidExecutionCount", "%s must be a positive integer.", name);
end
end
