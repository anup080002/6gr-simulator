function [cfg, contract] = resolveSSBPowerContract(cfg)
% Bind SIB1's TS 38.331 ss-PBCH-BlockPower to transmitted SSS EPRE.
% Physical full-BWP budgets are total across unit-norm precoder branches.
% Normalized fixed-SNR instead retains the unit-grid IFFT sample reference:
% a device budget that applyPowerContext does not apply is not TX authority.
% Integer quantization is an explicit network implementation policy;
% TS 38.331 defines the IE range/meaning, not this budget allocation policy.
% Unconfigured legacy/unit-waveform callers remain explicitly unqualified.
root = 'lls6g.resolvedConfig.power_and_rf_frontend.';
policy = string(sixgr.util.structGet(cfg,[root 'ssb_power_reference_policy'], ...
    sixgr.util.structGet(cfg,'powerAndRF.ssbPowerReferencePolicy',"")));
contract = struct('Available',false,'Source',"unconfigured_ssb_power_reference", ...
    'Policy',policy,'SSPBCHBlockPower_dBm',NaN,'FullBWPUnitEPRE_dBm',NaN, ...
    'SSBRelativePower_dB',NaN,'NumSubcarriers',NaN,'TxPowerBudget_dBm',NaN, ...
    'ReferencePlane',"nominal_pre_rf_aggregate_sss_epre",'ProxyUsed',false, ...
    'FixedSNRNormalizedReference',false,'PhysicalDevicePowerClaim',false, ...
    'PowerReferenceDomain',"unavailable",'ReferenceFullBWPPower_dBm',NaN, ...
    'OFDMUnitReference',struct());
if strlength(policy)==0, return; end
normalization = string(sixgr.util.structGet(cfg,[root 'downlink_power_normalization_policy'], ...
    sixgr.util.structGet(cfg,'powerAndRF.downlinkPowerNormalizationPolicy',"")));
if normalization~="fixed_epre_over_configured_bwp"
    error('sixgr:rf:SSBPowerNormalizationMismatch', ...
        'Bound SSB power requires fixed_epre_over_configured_bwp, not allocation-dependent total-power normalization.');
end
if ~isempty(fieldnames(sixgr.util.structGet(cfg,'lls6g.runtimeScheduledPowerContext',struct())))
    error('sixgr:rf:SSBGrantPowerAuthority','Common SSB power cannot inherit a UE data-grant power budget.');
end
[carrier,~] = sixgr.phy.grid.makeCarrier(cfg);
ssbSCS = double(sixgr.util.structGet(cfg,'phy.ssb.scs_kHz',carrier.SubcarrierSpacing));
if ssbSCS~=carrier.SubcarrierSpacing
    error('sixgr:rf:SSBMixedNumerologyPowerUnqualified', ...
        'Mixed-numerology SSB/carrier EPRE normalization requires its own exact-grid power contract.');
end
powers = double(sixgr.util.structGet(cfg,'phy.ssb.perSSBPower_dB', ...
    sixgr.util.structGet(cfg,'reference_signals.ssb_power_offsets_db',0)));
if isempty(powers), powers=0; end
validateattributes(powers,{'numeric'},{'vector','real','finite'});
if any(abs(powers-powers(1))>1e-10)
    error('sixgr:rf:SSBCommonPowerMismatch', ...
        'A single broadcast power declaration cannot qualify unequal per-SSB EPRE in this contract.');
end
ctx = sixgr.rf.PowerContext(cfg,'DL');
nsc = 12*double(carrier.NSizeGrid);
base = ctx.TotalTxPower_dBm-10*log10(nsc);
normalized = upper(strtrim(string(sixgr.util.structGet(cfg,'integration.run_mode',""))))=="FIXED_SNR_SWEEP" && ...
    logical(sixgr.util.structGet(cfg,'integration.configured_snr_is_link_authority',false));
if normalized
    % A deterministic single-RE calibration measures the actual Toolbox
    % IFFT convention; it is not a PHY result or a noise/receiver input.
    % Under the retained sample-unit mapping |sample|^2 is mW, but this
    % reference does not claim an applied device/EIRP budget.
    grid=complex(zeros(nsc,carrier.SymbolsPerSlot)); grid(1,1)=1;
    [probe,info]=nrOFDMModulate(carrier,grid,'Windowing',0);
    useful=double(info.CyclicPrefixLengths(1))+(1:double(info.Nfft));
    unitPower=mean(abs(probe(useful,:)).^2,'all');
    validateattributes(unitPower,{'numeric'},{'scalar','real','finite','positive'});
    base=10*log10(unitPower);
    contract.OFDMUnitReference=struct('Source',"deterministic_single_RE_IFFT_useful_sample_power", ...
        'Nfft',double(info.Nfft),'SampleRateHz',double(info.SampleRate), ...
        'UnitREUsefulSamplePower_mW',unitPower,'DevicePowerApplied',false);
end
explicit = sixgr.util.structGet(cfg,[root 'ss_pbch_block_power_dbm'], ...
    sixgr.util.structGet(cfg,'powerAndRF.ssPBCHBlockPower_dBm',[]));
switch policy
    case "quantized_full_bwp_epre"
        if ~isempty(explicit)
            error('sixgr:rf:SSBPowerAuthorityConflict','Choose budget-derived or explicit SSB power, not both.');
        end
        target = floor(base+powers(1));
    case "explicit_ss_pbch_block_power"
        if normalized
            error('sixgr:rf:SSBExplicitPowerInNormalizedMode', ...
                'Absolute ss_pbch_block_power_dbm requires physical power authority, not normalized FIXED_SNR_SWEEP.');
        end
        if isempty(explicit)
            error('sixgr:rf:MissingSSBPowerDeclaration','Explicit policy requires ss_pbch_block_power_dbm.');
        end
        target = double(explicit);
    otherwise
        error('sixgr:rf:UnknownSSBPowerPolicy','Unsupported SSB power policy %s.',policy);
end
validateattributes(target,{'numeric'},{'scalar','real','finite','integer','>=',-60,'<=',50});
% This separate correction avoids adding the boost again on repeated config
% resolution. The authored per-SSB values and normalized precoders survive.
cfg = sixgr.util.structSet(cfg,'phy.ssb.referencePowerOffset_dB',target-base-powers(1));
cfg = sixgr.util.structSet(cfg,'rrc.sib1.ss_pbch_block_power_dbm',target);
contract.Available = true;
contract.Source = "configured_ssb_sss_epre_and_sib1_common_authority";
contract.FixedSNRNormalizedReference=normalized;
contract.PhysicalDevicePowerClaim=~normalized;
contract.PowerReferenceDomain="configured_device_full_bwp_budget";
if normalized
    contract.Source="normalized_unit_grid_sss_sample_reference_and_sib1_common_authority";
    contract.PowerReferenceDomain="normalized_IFFT_sample_unit_mapping_not_device_budget";
end
contract.SSPBCHBlockPower_dBm = target;
contract.FullBWPUnitEPRE_dBm = base;
contract.SSBRelativePower_dB = target-base;
contract.NumSubcarriers = nsc;
contract.ReferenceFullBWPPower_dBm=base+10*log10(nsc);
if ~normalized, contract.TxPowerBudget_dBm = ctx.TotalTxPower_dBm; end
cfg = sixgr.util.structSet(cfg,'phy.ssb.powerReferenceContract',contract);
end
