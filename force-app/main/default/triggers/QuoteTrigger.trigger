/**
 * @description Único trigger de Quote (SBQQ__Quote__c). No tiene lógica: solo mira en qué
 *              momento se ejecuta y llama al método que corresponde del QuoteTriggerHandler.
 *
 * Requirement DEV #1 (Parte A):
 *   - before insert -> la Quote se crea ya aprobada (carga de datos, tests)
 *   - before update -> el Status de la Quote pasa a Approved (Approval Process o edición)
 */
trigger QuoteTrigger on SBQQ__Quote__c ( before insert, before update ) {
    if ( Trigger.isBefore && Trigger.isInsert ) {
        QuoteTriggerHandler.beforeInsert( Trigger.new );
    } else if ( Trigger.isBefore && Trigger.isUpdate ) {
        QuoteTriggerHandler.beforeUpdate( Trigger.new, Trigger.oldMap );
    }
}
