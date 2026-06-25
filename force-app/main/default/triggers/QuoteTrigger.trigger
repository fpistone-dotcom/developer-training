trigger QuoteTrigger on Quote__c (before insert, before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore && Trigger.isInsert) {
        QuoteTriggerHandler.beforeInsert(Trigger.new);
    } else if (Trigger.isBefore && Trigger.isUpdate) {
        QuoteTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
    else if (Trigger.isAfter && Trigger.isInsert) {
        QuoteTriggerHandler.afterInsert(Trigger.new);
    } 
    else if (Trigger.isAfter && Trigger.isUpdate) {
        QuoteTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    } 
    else if (Trigger.isAfter && Trigger.isDelete) {
        QuoteTriggerHandler.afterDelete(Trigger.oldMap);
    } 
    else if (Trigger.isAfter && Trigger.isUndelete) {
        QuoteTriggerHandler.afterUndelete(Trigger.new);
    }
}