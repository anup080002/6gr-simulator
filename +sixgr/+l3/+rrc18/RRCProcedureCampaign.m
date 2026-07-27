classdef RRCProcedureCampaign
    %RRCPROCEDURECAMPAIGN Execute every enabled bounded RRC procedure.
    methods (Static)
        function result=run(vectorRoot,transactionID)
            timers=struct("T300",1000,"T301",1000,"T304",1000, ...
                "T310",1000,"T311",3000,"T319",1000);
            ue=sixgr.l3.rrc18.RRCUE("UE-CAMPAIGN",vectorRoot,timers);
            gnb=sixgr.l3.rrc18.RRCGNB("UE-CAMPAIGN",vectorRoot,timers);
            setup=sixgr.l3.rrc18.RRCConnectionEstablishment.run( ...
                ue,gnb,transactionID);
            messages=3;bytes=numel(setup.RequestBytes)+ ...
                numel(setup.SetupBytes)+numel(setup.CompleteBytes);
            now=3;

            [ue,gnb,n]=localExchange(ue,gnb,"SecurityModeCommand", ...
                "DL-DCCH",transactionID);messages=messages+2;bytes=bytes+n;
            ue.transition("SECURITY_MODE_COMMAND_DECODED",now,transactionID);
            gnb.transition("SECURITY_MODE_COMMAND_DECODED",now,transactionID);
            [ue,gnb,n]=localExchange(ue,gnb,"SecurityModeComplete", ...
                "UL-DCCH",transactionID);messages=messages+0;bytes=bytes+n;
            now=now+1;
            ue.transition("SECURITY_MODE_COMPLETE_DECODED",now,transactionID);
            gnb.transition("SECURITY_MODE_COMPLETE_DECODED",now,transactionID);

            [~,~,n]=localExchange(ue,gnb,"UECapabilityEnquiry", ...
                "DL-DCCH",transactionID);messages=messages+1;bytes=bytes+n;
            [~,~,n]=localExchange(ue,gnb,"UECapabilityInformation", ...
                "UL-DCCH",transactionID);messages=messages+1;bytes=bytes+n;

            [~,~,n]=localExchange(ue,gnb,"RRCReconfiguration", ...
                "DL-DCCH",transactionID);messages=messages+1;bytes=bytes+n;
            now=now+1;
            ue.transition("RRC_RECONFIGURATION_DECODED",now,transactionID);
            gnb.transition("RRC_RECONFIGURATION_DECODED",now,transactionID);
            [~,~,n]=localExchange(ue,gnb,"RRCReconfigurationComplete", ...
                "UL-DCCH",transactionID);messages=messages+1;bytes=bytes+n;
            now=now+1;
            ue.transition("RRC_RECONFIGURATION_COMPLETE_DECODED",now,transactionID);
            gnb.transition("RRC_RECONFIGURATION_COMPLETE_DECODED",now,transactionID);

            [~,~,n]=localExchange(ue,gnb,"RRCRelease", ...
                "DL-DCCH",transactionID);messages=messages+1;bytes=bytes+n;
            now=now+1;
            ue.transition("RRC_RELEASE_WITH_SUSPEND",now);
            gnb.transition("RRC_RELEASE_WITH_SUSPEND",now);
            [~,~,n]=localExchange(ue,gnb,"RRCResumeRequest", ...
                "UL-CCCH",0);messages=messages+1;bytes=bytes+n;
            now=now+1;ue.transition("RRC_RESUME_REQUEST_SENT",now);
            gnb.transition("RRC_RESUME_REQUEST_SENT",now);
            [~,~,n]=localExchange(ue,gnb,"RRCResume", ...
                "DL-DCCH",transactionID);messages=messages+1;bytes=bytes+n;
            [~,~,n]=localExchange(ue,gnb,"RRCResumeComplete", ...
                "UL-DCCH",transactionID);messages=messages+1;bytes=bytes+n;
            now=now+1;
            ue.transition("RRC_RESUME_COMPLETE_DECODED",now,transactionID);
            gnb.transition("RRC_RESUME_COMPLETE_DECODED",now,transactionID);

            now=now+1;ue.transition("RLF_DECLARED",now);
            gnb.transition("RLF_DECLARED",now);
            [~,~,n]=localExchange(ue,gnb,"RRCReestablishmentRequest", ...
                "UL-CCCH",0);messages=messages+1;bytes=bytes+n;
            [~,~,n]=localExchange(ue,gnb,"RRCReestablishment", ...
                "DL-DCCH",transactionID);messages=messages+1;bytes=bytes+n;
            [~,~,n]=localExchange(ue,gnb,"RRCReestablishmentComplete", ...
                "UL-DCCH",transactionID);messages=messages+1;bytes=bytes+n;
            now=now+1;
            ue.transition("RRC_REESTABLISHMENT_COMPLETE_DECODED",now,transactionID);
            gnb.transition("RRC_REESTABLISHMENT_COMPLETE_DECODED",now,transactionID);

            [~,~,n]=localExchange(ue,gnb,"RRCRelease", ...
                "DL-DCCH",transactionID);messages=messages+1;bytes=bytes+n;
            now=now+1;ue.transition("RRC_RELEASE",now);
            gnb.transition("RRC_RELEASE",now);
            result=struct("Messages",messages,"SignalingBytes",bytes, ...
                "CompletionTime_ms",now,"SecurityActive", ...
                ue.SecurityActive&&gnb.SecurityActive, ...
                "UEState",ue.StateMachine.State, ...
                "GNBState",gnb.StateMachine.State, ...
                "Converged",ue.StateMachine.State==gnb.StateMachine.State);
        end
    end
end

function [ue,gnb,nbytes]=localExchange(ue,gnb,message,channel,transactionID)
if startsWith(channel,"DL")
    bytes=gnb.encode(message,transactionID);ue.decode(channel,bytes);
else
    bytes=ue.encode(message,transactionID);gnb.decode(channel,bytes);
end
nbytes=numel(bytes);
end
