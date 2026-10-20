/**
 * @description Single trigger for Quote (SBQQ__Quote__c). It has no logic: it only checks which
 *              context it is running in and calls the matching method of QuoteTriggerHandler.
 *
 * Requirement DEV #1 (Part A):
 *   - before insert -> the Quote is created already approved (data load, tests)
 *   - before update -> the Quote Status changes to Approved (Approval Process or manual edit)
 *
 * Requirement DEV #3 (Part 3):
 *   - after insert  -> a Renewal Quote is created: email to its Owner with the link (after,
 *                      because the link needs the Quote Id)
 */
trigger QuoteTrigger on SBQQ__Quote__c ( before insert, before update, after insert ) {
    if ( Trigger.isBefore && Trigger.isInsert ) {
        QuoteTriggerHandler.beforeInsert( Trigger.new );
    } else if ( Trigger.isBefore && Trigger.isUpdate ) {
        QuoteTriggerHandler.beforeUpdate( Trigger.new, Trigger.oldMap );
    } else if ( Trigger.isAfter && Trigger.isInsert ) {
        QuoteTriggerHandler.afterInsert( Trigger.new );
    }
}
