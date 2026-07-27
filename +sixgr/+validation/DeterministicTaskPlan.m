classdef DeterministicTaskPlan
    %DETERMINISTICTASKPLAN Immutable validation campaign task identity.
    methods (Static)
        function out=build(campaignID,pointKeys,dropIDs,baseSeed,trialsPerTask)
            pointKeys=string(pointKeys(:)); dropIDs=string(dropIDs(:));
            rows=numel(pointKeys)*numel(dropIDs);
            campaign=strings(rows,1); taskID=strings(rows,1);
            point=strings(rows,1); drop=strings(rows,1);
            seed=zeros(rows,1); substream=zeros(rows,1);
            trialStart=zeros(rows,1); trialEnd=zeros(rows,1);
            inputHash=strings(rows,1);
            cursor=0;
            for p=1:numel(pointKeys)
                for d=1:numel(dropIDs)
                    cursor=cursor+1;
                    identity=string(campaignID)+"|"+pointKeys(p)+"|"+dropIDs(d);
                    hash=localHash(identity);
                    campaign(cursor)=string(campaignID); point(cursor)=pointKeys(p);
                    drop(cursor)=dropIDs(d); taskID(cursor)=extractBefore(hash,25);
                    seed(cursor)=double(sixgr.util.hierarchicalSeed( ...
                        baseSeed,p,d,0,"VALIDATION_TASK"));
                    substream(cursor)=double(sixgr.util.hierarchicalSeed( ...
                        baseSeed,p,d,1,"VALIDATION_SUBSTREAM"));
                    trialStart(cursor)=(cursor-1)*double(trialsPerTask)+1;
                    trialEnd(cursor)=cursor*double(trialsPerTask);
                    inputHash(cursor)=hash;
                end
            end
            out=table(campaign,taskID,point,drop,seed,substream, ...
                trialStart,trialEnd,inputHash,repmat("PASS",rows,1), ...
                'VariableNames',["CampaignID","TaskID","PointKey", ...
                "IndependentDropID","Seed","Substream","TrialStart", ...
                "TrialEnd","InputSHA256","Status"]);
        end
        function id=taskID(campaignID,pointID,dropID)
            id=extractBefore(localHash(string(campaignID)+"|"+ ...
                string(pointID)+"|"+string(dropID)),25);
        end
    end
end

function out=localHash(text)
out=string(sixgr.util.sha256Hex(uint8(unicode2native(char(text),"UTF-8"))));
end
