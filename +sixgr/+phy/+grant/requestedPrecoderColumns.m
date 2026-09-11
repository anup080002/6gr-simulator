function [pmi,source]=requestedPrecoderColumns(rows,direction)
% Keep the transmit request separate from CSI measured by the same trial.
% A configured reference is labelled as such, never as measured feedback.
arguments
    rows table
    direction (1,1) string {mustBeMember(direction,["DL","UL"])}
end
n=height(rows); pmi=nan(n,1); source=strings(n,1);
if ismember('ConfiguredPMI',rows.Properties.VariableNames)
    configured=double(rows.ConfiguredPMI);
    mask=isfinite(configured);
    pmi(mask)=configured(mask);
    source(mask)="configured_pmi_reference";
    if direction=="UL", source(mask)="configured_pusch_tpmi_runtime_request"; end
end
if all(ismember({'RequestedPrecoderPMI','RequestedPrecoderSource'},rows.Properties.VariableNames))
    frozen=string(rows.RequestedPrecoderSource)=="frozen_PHYGrant_precoding_state";
    % Preserve an explicit matrix's unavailable scalar PMI as unavailable,
    % even if a configured or newly measured index happens to be finite.
    pmi(frozen)=double(rows.RequestedPrecoderPMI(frozen));
    source(frozen)="frozen_PHYGrant_precoding_state";
end
end
