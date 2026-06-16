trigger InvitationTrigger on Invitation__c (before insert, after insert, before update, after update) {

    if (Trigger.isBefore && Trigger.isInsert) {
        InvitationTriggerHandler.beforeInsert(Trigger.new);
    } 
    else if (Trigger.isAfter && Trigger.isInsert) {
        InvitationTriggerHandler.afterInsert(Trigger.new);
    } 
    else if (Trigger.isBefore && Trigger.isUpdate) {
        InvitationTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    } 
    else if (Trigger.isAfter && Trigger.isUpdate) {
        InvitationTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }

}