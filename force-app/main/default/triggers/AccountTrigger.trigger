/* 
If the Account record's Type field changes, update the Type field accordingly on all child Opportunity records that are not in a "Closed Won" or "Closed Lost" Stage.
 */

trigger AccountTrigger on Account (before insert, after insert, before update, after update) {

    if (Trigger.isAfter && Trigger.isUpdate) {
        AccountTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    } 

}