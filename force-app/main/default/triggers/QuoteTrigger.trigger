/**
 * @description Único trigger de Quote (SBQQ__Quote__c). No tiene lógica: solo mira en qué
 *              momento se ejecuta y llama al método que corresponde del QuoteTriggerHandler.
 *
 * Requirement DEV #1 (Parte A):
 *   - before insert -> la Quote se crea ya aprobada (carga de datos, tests)
 *   - before update -> el Status de la Quote pasa a Approved (Approval Process o edición)
 *
 * Requirement DEV #3 (Parte 3):
 *   - after insert  -> nace una Renewal Quote: email a su Owner con el link (en after porque
 *                      el link necesita el Id de la Quote)
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
