/**
 * @description Único trigger de Contract. No tiene lógica: solo mira en qué momento se
 *              ejecuta y llama al método que corresponde del ContractTriggerHandler.
 *
 * Requirement DEV #3 (Parte 1):
 *   - before update -> el Status pasa a Activated: se tilda SBQQ__RenewalForecast__c en el
 *                      mismo save y CPQ (SBQQ.ContractAfter) genera la Renewal Opportunity.
 *   No hay before insert: Salesforce no deja crear un Contract ya Activated
 *   (FAILED_ACTIVATION, verificado en el org), así que la activación siempre es un update.
 */
trigger ContractTrigger on Contract ( before update ) {
    if ( Trigger.isBefore && Trigger.isUpdate ) {
        ContractTriggerHandler.beforeUpdate( Trigger.new, Trigger.oldMap );
    }
}
