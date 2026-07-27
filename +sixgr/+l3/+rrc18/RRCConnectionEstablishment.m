classdef RRCConnectionEstablishment
    %RRCCONNECTIONESTABLISHMENT Wave-message-driven bounded setup.
    methods (Static)
        function result=run(ue,gnb,transactionID)
            arguments
                ue sixgr.l3.rrc18.RRCUE
                gnb sixgr.l3.rrc18.RRCGNB
                transactionID (1,1) double {mustBeInteger}=0
            end
            request=ue.encode("RRCSetupRequest",0);
            requestTree=gnb.decode("UL-CCCH",request);
            if requestTree.MessageType~="RRCSetupRequest"
                error("sixgr:rrc:UPERDecodeFailed", ...
                    "gNB did not decode RRCSetupRequest.");
            end
            ue.transition("RRC_SETUP_REQUEST_SENT",0);
            gnb.transition("RRC_SETUP_REQUEST_SENT",0);
            setup=gnb.encode("RRCSetup",transactionID);
            setupTree=ue.decode("DL-CCCH",setup);
            ue.transition("RRC_SETUP_DECODED",1, ...
                setupTree.TransactionID);
            gnb.transition("RRC_SETUP_DECODED",1, ...
                setupTree.TransactionID);
            complete=ue.encode("RRCSetupComplete",transactionID);
            completeTree=gnb.decode("UL-DCCH",complete);
            ue.transition("RRC_SETUP_COMPLETE_DECODED",2, ...
                completeTree.TransactionID);
            gnb.transition("RRC_SETUP_COMPLETE_DECODED",2, ...
                completeTree.TransactionID);
            result=struct("RequestBytes",request,"SetupBytes",setup, ...
                "CompleteBytes",complete,"TransactionID",transactionID, ...
                "UEState",ue.StateMachine.State, ...
                "GNBState",gnb.StateMachine.State, ...
                "Converged",ue.StateMachine.State==gnb.StateMachine.State && ...
                ue.StateMachine.State=="RRC_CONNECTED");
        end
    end
end
