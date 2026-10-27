classdef PendingDRBEndpoints < handle
    % One original issued connection/configuration owns these handles for life.
    % Runtime endpoint gates, not possession of a handle, authorize traffic.
    properties (SetAccess=private)
        Connection struct
        OriginalMessage struct
        ConfigurationSHA256 string
    end
    properties (Access=private)
        Runtimes cell
        Scopes cell
        IssuedReceipts cell = {}
    end
    methods
        function obj=PendingDRBEndpoints(message,connection,coreContext,installed)
            sixgr.rrc.validateNewDRBRegistry(installed,connection,message);
            configs=sixgr.rrc.buildNewDRBProtocolConfigurations(message,connection,coreContext);
            scopes=cell(1,2);built=cell(1,2);
            fields={'ExecutionRunID','UEID','ServingCell','RNTI','ConfigurationEpoch','ClockEpoch','SampleRateHz','ConnectionReceiptSHA256'};
            assert(isstruct(connection)&&isscalar(connection)&&all(isfield(connection,fields)), ...
                'sixgr:rrc:DRBConnectionScope','Original stable connection scope is required.');
            for k=1:2
                c=configs{k};scope=struct();
                for j=1:numel(fields),scope.(fields{j})=connection.(fields{j});end
                scope.BearerID=c.BearerID;scope.DRBID=c.DRBID;scope.LCID=c.LCID;scope.Direction=c.Direction;
                scope.ProtocolConfigurationSHA256=sixgr.l2.mac.MACHash.of(orderfields(c));
                c.EndpointAdmissionMode="original_reconfiguration_required";
                c.EndpointAdmissionScope=scope;
                scopes{k}=scope;built{k}=sixgr.protocol.ProtocolRuntime(c);
            end
            % Publish only after BOTH complete constructors succeed.
            obj.Connection=connection;obj.OriginalMessage=message;
            obj.ConfigurationSHA256=sixgr.l2.mac.MACHash.of(configs);
            obj.Scopes=scopes;obj.Runtimes=built;
        end
        function scope=directionalScope(obj,direction)
            scope=obj.Scopes{obj.index(direction)};
        end
        function runtime=directionalRuntime(obj,direction)
            runtime=obj.Runtimes{obj.index(direction)};
        end
        function r=originalIssuedReceipt(obj,direction)
            assert(numel(obj.IssuedReceipts)==2,'sixgr:rrc:DRBIssuedRequired','Original issued configuration is required.');
            r=obj.IssuedReceipts{obj.index(direction)};
        end
        function states=snapshot(obj)
            states=cellfun(@(r)r.securityState(),obj.Runtimes,'UniformOutput',false);
        end
        function validateIssued(obj,receipts,sample)
            obj.validatePair(receipts);
            for k=1:2,obj.Runtimes{k}.validateIssuedReconfiguration(receipts{k},sample);end
        end
        function admitIssued(obj,receipts,sample)
            obj.validateIssued(receipts,sample);
            for k=1:2,obj.Runtimes{k}.admitIssuedReconfiguration(receipts{k},sample);end
            obj.IssuedReceipts=receipts;
        end
        function validateReceived(obj,receipts,sample)
            obj.validatePair(receipts);
            for k=1:2,obj.Runtimes{k}.validateReceivedReconfiguration(receipts{k},sample);end
        end
        function admitReceived(obj,receipts,sample)
            obj.validateReceived(receipts,sample);
            for k=1:2,obj.Runtimes{k}.admitReceivedReconfiguration(receipts{k},sample);end
        end
        function validateComplete(obj,receipts,sample)
            obj.validatePair(receipts);
            for k=1:2,obj.Runtimes{k}.validateReceivedReconfigurationComplete(receipts{k},sample);end
        end
        function admitComplete(obj,receipts,sample)
            % Deliberately no UE-local received-configuration prerequisite.
            obj.validateComplete(receipts,sample);
            for k=1:2,obj.Runtimes{k}.admitReceivedReconfigurationComplete(receipts{k},sample);end
        end
    end
    methods (Access=private)
        function k=index(~,direction)
            direction=string(direction);
            assert(isscalar(direction)&&any(direction==["DL","UL"]), ...
                'sixgr:rrc:DRBDirection','Require an original directional endpoint.');
            k=find(["DL","UL"]==direction);
        end
        function validatePair(obj,receipts)
            id='sixgr:rrc:DRBConnectionScope';
            assert(iscell(receipts)&&numel(receipts)==2,id,'Both directional admission receipts are required.');
            fields={'ConnectionReceiptSHA256','RRCTransactionID','RRCReconfigurationSHA256','ContractVersion'};
            for k=1:2
                r=receipts{k};
                assert(isstruct(r)&&isscalar(r)&&all(isfield(r,fields)),id,'Original paired configuration receipts are required.');
                assert(string(r.RRCReconfigurationSHA256)==string(obj.OriginalMessage.SHA256)&& ...
                    r.RRCTransactionID==obj.OriginalMessage.Semantic.transaction_id&& ...
                    string(r.ConnectionReceiptSHA256)==string(obj.Connection.ConnectionReceiptSHA256),id,'Original issued connection/configuration changed.');
            end
            for j=1:numel(fields)
                assert(isequaln(receipts{1}.(fields{j}),receipts{2}.(fields{j})),id,'Directional receipts are from different original procedures.');
            end
        end
    end
end
