classdef SLSDeferredFixtureProvider < SLSAbstractionFixtureProvider
    % TEST ONLY: fixed one-slot availability delay isolates runner/file/HARQ
    % accounting. This is not a propagation model or physical calibration.
    properties (Access=private)
        History
    end
    methods
        function obj=SLSDeferredFixtureProvider(varargin)
            obj@SLSAbstractionFixtureProvider(varargin{:});
            obj.History=sixgr.system.abstraction.ScheduledSlotHistory(0,1);
        end
        function commitSlotPopulation(obj,state)
            obj.History.append(state);
        end
        function [available,evidence,state]=receptionAvailability(obj,ctx)
            state=obj.History.scheduledState(ctx.TTI);
            grants=state.("Grants"+ctx.Direction); cells=state.("GrantCells"+ctx.Direction);
            matched=arrayfun(@(g)sixgr.system.abstraction.matchesScheduledGrant(g,ctx),grants);
            assert(sum(matched(:) & cells(:)==ctx.ServingCellID)==1,'test:ChangedIssuedGrant');
            available=obj.History.CommittedThroughTTI>=ctx.TTI+1;
            evidence=struct('TransmissionTTI',ctx.TTI,'RequiredCommittedThroughTTI',ctx.TTI+1);
        end
        function o=evaluate(obj,ctx,state)
            assert(obj.receptionAvailability(ctx),'test:EarlyReception');
            o=evaluate@SLSAbstractionFixtureProvider(obj,ctx,state);
            G=o.Channel*o.Precoder*sqrt(o.TotalTransmitPower);
            total=G*G';
            desired=struct('SameResourceEffectiveChannel',G,'SameResourceChannelIncludesTransmitPower',true, ...
                'OtherResourceCovariance',zeros(size(total)),'Covariance',total,'Coordinates0Based',[0 0], ...
                'SourceClassification',"modeled_finite_filter_independent_symbol_covariance", ...
                'BoundaryPolicy',"explicit_zero_outside_declared_observation_window", ...
                'WithinWindowISIICIIncluded',true,'FullNetworkInterferenceQualified',false, ...
                'CommonControlInterferenceQualified',false,'StatisticalBLERQualified',false,'PrimaryStudyAccepted',false);
            o.ReceiverProfileID="test_only_deferred_fixture_not_physical_calibration";
            o.Coordinates0Based=[0 0]; o.SINRPredictorModel="finite_committed_shared_data";
            o.ResidualISIICIIncluded=true;
            o.FiniteWindow=struct('SourceClassification',"modeled_committed_finite_window_shared_data", ...
                'ReceiveWindow',struct('ObservationTTI',ctx.TTI),'Coordinates0Based',[0 0], ...
                'DesiredObservation',desired,'ExternalCovariance',o.ExternalCovariance);
            o.FiniteWindow.ReferenceObservationOnly=false;
            o.FiniteWindow.WaveformMeasured=false;
            for channel=["SRS","CSIRS","PDCCH","SSB"]
                % This accounting fixture emits none of these channels.
                o.FiniteWindow.(channel+"InterferenceIncluded")=false;
                o.FiniteWindow.(channel+"EmissionPopulation")=struct([]);
                o.(channel+"InterferenceIncluded")=false;
                o.(channel+"EmissionCount")=0;
            end
            obj.LastObservation=o;
        end
    end
end
