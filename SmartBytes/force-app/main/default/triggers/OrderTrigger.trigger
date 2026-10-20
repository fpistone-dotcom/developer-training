/**
 * @description Single trigger for Order. It has no logic: it only checks which context
 *              it is running in and calls the matching method of OrderTriggerHandler.
 *
 * Requirement DEV #2:
 *   - before update -> covers "the Price Calculation Status on the Order is updated"
 *   - after insert  -> covers "whenever it is created"
 */
trigger OrderTrigger on Order ( before update, after insert ) {
    if ( Trigger.isBefore && Trigger.isUpdate ) {
        OrderTriggerHandler.beforeUpdate( Trigger.new, Trigger.oldMap );
    } else if ( Trigger.isAfter && Trigger.isInsert ) {
        OrderTriggerHandler.afterInsert( Trigger.new );
    }
}
