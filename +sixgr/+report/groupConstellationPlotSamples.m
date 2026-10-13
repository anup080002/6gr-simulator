function [groups,summary] = groupConstellationPlotSamples(T)
% Retain every finite, lineaged constellation group in one report figure.
% No largest-population selection, point truncation or modulation mixing.
groups={}; summary=table();
required=["direction","modulation","layer","snr_db","mcs_index", ...
    "reference_symbol_i","reference_symbol_q", ...
    "equalized_i","equalized_q","truth_status"];
if ~istable(T) || isempty(T) || ...
        ~all(ismember(required,string(T.Properties.VariableNames)))
    return;
end
% A missing SINR estimate does not invalidate measured complex symbols or
% their EVM. In particular, failed/low-SNR captures must remain observable.
numeric=["layer","snr_db","mcs_index", ...
    "reference_symbol_i","reference_symbol_q","equalized_i","equalized_q"];
valid=true(height(T),1);
for name=numeric
    valid=valid & isfinite(double(T.(name)));
end
valid=valid & strlength(strtrim(string(T.modulation)))>0 & ...
    ismember(upper(strtrim(string(T.direction))),["DL","UL"]) & ...
    ismember(lower(strtrim(string(T.truth_status))), ...
        ["real_lls_evidence","truth","runtime_measured"]);
T=T(valid,:);
if isempty(T), return; end
% Keep exact numeric sweep values in the grouping key. Display-rounded
% SNR strings can otherwise merge distinct physical operating points.
key=string(T.direction)+"|"+string(T.modulation)+ ...
    "|layer="+compose('%.17g',double(T.layer))+ ...
    "|snr="+compose('%.17g',double(T.snr_db))+ ...
    "|mcs="+compose('%.17g',double(T.mcs_index));
for name=["ue_id","normalization"]
    if ismember(name,string(T.Properties.VariableNames))
        key=key+"|"+name+"="+string(T.(name));
    end
end
keys=unique(key,'stable');
groups=cell(numel(keys),1);
for k=1:numel(keys)
    G=T(key==keys(k),:);
    groups{k}=G;
    eq=complex(double(G.equalized_i),double(G.equalized_q));
    ref=complex(double(G.reference_symbol_i),double(G.reference_symbol_q));
    errorEnergy=sum(abs(eq-ref).^2);
    referenceEnergy=sum(abs(ref).^2);
    evm=NaN;
    if referenceEnergy>0, evm=sqrt(errorEnergy/referenceEnergy); end
    % This is EVM of these plotted captured samples, not an arithmetic
    % mean of per-symbol percentages or a replacement for trial EVM.
    r=table(string(G.direction(1)),string(G.modulation(1)), ...
        double(G.layer(1)),double(G.snr_db(1)),double(G.mcs_index(1)), ...
        height(G),errorEnergy,referenceEnergy,100*evm,20*log10(evm), ...
        'VariableNames',{'Direction','Modulation','Layer','ConfiguredSNR_dB', ...
        'MCS','CapturedSampleCount','ErrorEnergy','ReferenceEnergy', ...
        'CaptureEVM_pct','CaptureEVM_dB'});
    summary=[summary;r]; %#ok<AGROW>
end
end
