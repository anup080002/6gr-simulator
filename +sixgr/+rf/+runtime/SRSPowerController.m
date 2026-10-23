classdef SRSPowerController
%SRSPOWERCONTROLLER Exact SRS power-control facade.
    methods(Static)
        function result=resolve(state,request)
            if ~isa(state,"sixgr.rf.runtime.UplinkPowerControlState") || ...
                    ~isstruct(request)||~isfield(request,"Channel")|| ...
                    upper(string(request.Channel))~="SRS"
                error("RF:PowerControlChannelMismatch", ...
                    "Power-control request does not match SRS.");
            end
            % TS 38.213 V18.8.0 7.3.1 has the SRS adjustment h, not
            % PUSCH's modulation/coding-dependent DeltaTF. The common
            % arithmetic owner retains a DeltaTF field for other channels;
            % reject a nonzero value here instead of silently adding it.
            if ~isfield(request,"DeltaTF_dB") || ...
                    ~isnumeric(request.DeltaTF_dB) || ...
                    ~isscalar(request.DeltaTF_dB) || request.DeltaTF_dB~=0
                error("RF:SRSDeltaTFNotApplicable", ...
                    "SRS has no PUSCH DeltaTF term; the common request field must be zero.");
            end
            result=state.resolve(request);
        end

        function result=resolveSharedPUSCH(owner,cfg,request,sample,fs)
            assert(isa(owner,'sixgr.link.ReceivedULPowerControlState'), ...
                'sixgr:srs:MissingReceivedPowerState', ...
                'Same-as-PUSCH SRS requires the retained UE received-command owner.');
            adjustment=owner.adjustmentAt(cfg,double(sample),double(fs));
            % Use the common validated open-loop equation, then the retained
            % adjustment. No synthetic applyTPC event is introduced.
            zero=sixgr.rf.runtime.UplinkPowerControlState( ...
                double(cfg.rf.frontend.configuration_epoch));
            result=sixgr.rf.runtime.SRSPowerController.resolve(zero,request);
            result.RequestedPower_dBm=result.RequestedPower_dBm+adjustment.Adjustment_dB;
            result.AppliedPower_dBm=min(request.PCMAX_dBm,result.RequestedPower_dBm);
            result.PowerHeadroom_dB=request.PCMAX_dBm-result.RequestedPower_dBm;
            result.RemainingAppliedPowerMargin_dB=request.PCMAX_dBm-result.AppliedPower_dBm;
            result.Clipped=result.RequestedPower_dBm>request.PCMAX_dBm;
            result.AccumulatedTPC_dB=adjustment.Adjustment_dB;
            for name=string(fieldnames(adjustment)).'
                result.(name)=adjustment.(name);
            end
        end
    end
end
