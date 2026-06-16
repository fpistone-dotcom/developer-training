/*
Requirement #2.2: Convert "Syncing Types" Code
Convert the code that you wrote for Requirement #2.1: Convert Syncing Types to use the Trigger Handler design pattern introduced in this lesson.
 */

trigger OpportunityTrigger on Opportunity (before insert, after insert, before update, after update) {

    if (Trigger.isBefore && Trigger.isInsert) {
        OpportunityTriggerHandler.beforeInsert(Trigger.new);
    } 
    else if (Trigger.isAfter && Trigger.isUpdate) {
        OpportunityTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    } 

}