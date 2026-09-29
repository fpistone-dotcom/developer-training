/**
 * @description Único trigger de Order. No tiene lógica: solo mira en qué momento
 *              se ejecuta y llama al método que corresponde del OrderTriggerHandler.
 *
 * Requirement DEV #2:
 *   - before update -> cubre "cuando el Price Calculation Status se actualiza"
 *   - after insert  -> cubre "cuando la Order se crea"
 */
trigger OrderTrigger on Order ( before update, after insert ) {
    if ( Trigger.isBefore && Trigger.isUpdate ) {
        OrderTriggerHandler.beforeUpdate( Trigger.new, Trigger.oldMap );
    } else if ( Trigger.isAfter && Trigger.isInsert ) {
        OrderTriggerHandler.afterInsert( Trigger.new );
    }
}
