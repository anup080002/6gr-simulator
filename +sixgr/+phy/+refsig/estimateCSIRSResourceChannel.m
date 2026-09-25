function [H,nVar,info]=estimateCSIRSResourceChannel(carrier,grid,indices,symbols,cfg,ports,cdm,execution)
% One installed CSI-RS resource, practical received-pilot estimation only.
% Flat model eligibility uses executed operator/RF metadata, never gains or
% configured/injected noise. Generic/fading estimation remains per-resource.
if nargin<8, execution=struct(); end
estimator=string(sixgr.util.structGet(cfg,'phy.csirs.runtimeChannelEstimator','nr_channel_estimate'));
switch estimator
    case "flat_static_awgn_ls"
        eligibility=sixgr.phy.rx.assertFlatStaticAWGNObservation(execution);
        [H,nVar,info]=sixgr.phy.rx.estimateFlatAWGNReferenceGrid(carrier,grid,indices,symbols,ports);
        info.ObservationEligibility=eligibility;
        info.CDMLengths=cdm;
    case "nr_channel_estimate"
        [H,nVar,info]=sixgr.phy.rx.channelEstimate(carrier,grid,indices,symbols, ...
            'UseFastMex',false,'StrictMode',logical(sixgr.util.structGet(cfg,'run.strictMode',false)), ...
            'ChannelModel',string(sixgr.util.structGet(cfg,'channel.model','AWGN')), ...
            'ExpectedTxPorts',ports,'CDMLengths',cdm,'ContextLabel','received_CSI_RS_resource');
    otherwise
        error('sixgr:refsig:InvalidCSIRSEstimator','Unsupported CSI-RS runtime estimator: %s.',estimator);
end
end
