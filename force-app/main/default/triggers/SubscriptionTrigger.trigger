/**
 * @description Único trigger de SBQQ__Subscription__c. No tiene lógica: solo mira en qué
 *              momento se ejecuta y llama al método que corresponde del SubscriptionTriggerHandler.
 *
 * Requirement DEV #4: todos los contextos son AFTER, porque lo que se modifica es un registro
 * RELACIONADO (el Contract) con DML, y la query de recuento tiene que ver el cambio ya guardado.
 *   - after insert   -> CPQ crea Subscriptions al contratar y en cada Amendment
 *   - after update   -> cambió algo que afecta si está activa (o se movió de Contract)
 *   - after delete   -> la Subscription borrada tiene que dejar de contar
 *   - after undelete -> la Subscription recuperada de la papelera vuelve a contar
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
