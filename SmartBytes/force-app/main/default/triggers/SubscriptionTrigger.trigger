/**
 * @description Single trigger for SBQQ__Subscription__c. It has no logic: it only checks which
 *              context it is running in and calls the matching method of SubscriptionTriggerHandler.
 *
 * Requirement DEV #4: every context is AFTER, because the record being changed is a RELATED one
 * (the Contract), with DML, and the recount query has to see the change already saved.
 *   - after insert   -> CPQ creates Subscriptions when contracting and on every Amendment
 *   - after update   -> something that affects whether it is active changed (or it moved Contract)
 *   - after delete   -> the deleted Subscription must stop counting
 *   - after undelete -> the Subscription restored from the Recycle Bin counts again
 */
trigger SubscriptionTrigger on SBQQ__Subscription__c ( after insert, after update, after delete, after undelete ) {
    if ( Trigger.isAfter && Trigger.isInsert ) {
        SubscriptionTriggerHandler.afterInsert( Trigger.new );
    } else if ( Trigger.isAfter && Trigger.isUpdate ) {
        SubscriptionTriggerHandler.afterUpdate( Trigger.new, Trigger.oldMap );
    } else if ( Trigger.isAfter && Trigger.isDelete ) {
        SubscriptionTriggerHandler.afterDelete( Trigger.old );
    } else if ( Trigger.isAfter && Trigger.isUndelete ) {
        SubscriptionTriggerHandler.afterUndelete( Trigger.new );
    }
}
