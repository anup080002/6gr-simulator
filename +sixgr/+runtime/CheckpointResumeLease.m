classdef CheckpointResumeLease < handle
    % One owner of already verified native state between preflight and PHY.
    % Never placed in scientific config, artifacts, or another checkpoint.
    properties (Access=private, Transient)
        Payload = []
        Lineage
        Path
        ReceiptSHA256
        Available = false
    end
    methods (Access=?sixgr.runtime.SlotCheckpoint)
        function obj=CheckpointResumeLease(path,payload,lineage)
            obj.Path=sixgr.util.canonicalPath(string(path));
            obj.Payload=payload;
            obj.Lineage=lineage;
            obj.ReceiptSHA256=sixgr.util.sha256File(fullfile(fileparts(obj.Path),'checkpoint.json'));
            obj.Available=true;
        end
    end
    methods
        function [payload,lineage]=take(obj,path,scenario,repairReason)
            assert(obj.Available,'sixgr:checkpoint:ResumeLeaseConsumed', ...
                'Native checkpoint state may be transferred to the PHY owner only once.');
            assert(string(sixgr.util.canonicalPath(string(path)))==string(obj.Path), ...
                'sixgr:checkpoint:ResumeLeasePath','Prepared native state belongs to another checkpoint.');
            receiptPath=fullfile(fileparts(obj.Path),'checkpoint.json');
            assert(isfile(receiptPath) && ...
                string(sixgr.util.sha256File(receiptPath))==string(obj.ReceiptSHA256), ...
                'sixgr:checkpoint:ResumeLeaseReceiptChanged','Checkpoint receipt changed after preflight.');
            % Recheck bytes and current source, not the expensive loadobj graph.
            verifyTimer=tic;
            checked=sixgr.runtime.SlotCheckpoint.verify(path,repairReason);
            verifySeconds=toc(verifyTimer);
            assert(string(checked.StateSHA256)==string(obj.Lineage.StateSHA256) && ...
                string(checked.RestoredSource.SHA256)==string(obj.Lineage.RestoredSource.SHA256), ...
                'sixgr:checkpoint:ResumeLeaseSourceChanged', ...
                'Source/state changed after native checkpoint preparation; prepare again.');
            assert(isequaln(sixgr.runtime.SlotCheckpoint.scientificScenario(obj.Payload.Scenario), ...
                sixgr.runtime.SlotCheckpoint.scientificScenario(scenario)), ...
                'sixgr:checkpoint:ScenarioChanged', ...
                'Scientific configuration changed: restart from slot zero.');
            assert(string(sixgr.util.sha256File(receiptPath))==string(obj.ReceiptSHA256), ...
                'sixgr:checkpoint:ResumeLeaseReceiptChanged','Checkpoint receipt changed during handoff.');
            payload=obj.Payload;
            lineage=obj.Lineage;
            lineage.NativeStateTransfer="single_owner_preflight_to_PHY_no_second_deserialization";
            lineage.ResumePreparationTiming.HandoffByteAndSourceVerificationSeconds=verifySeconds;
            lineage.ResumePreparationTiming.HandoffNativeDeserializations=0;
            lineage.RepairReason=string(repairReason);
            lineage.RequestedOperationalSettings=sixgr.runtime.SlotCheckpoint.operationalSettings(scenario);
            lineage.RequestedConfigInheritance=sixgr.util.structGet(scenario,'config_inheritance',struct());
            obj.release();
        end
        function release(obj)
            obj.Payload=[];
            obj.Available=false;
        end
        function state=saveobj(~) %#ok<STOUT>
            error('sixgr:checkpoint:ResumeLeaseNotSerializable', ...
                'A transient resume owner must not be saved as configuration or checkpoint state.');
        end
    end
end
