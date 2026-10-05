/**
 * @description Lógica del ContractTrigger. Resuelve la Parte 1 del DEV #3: cuando un Contract
 *              se activa, se genera su Renewal Opportunity.
 *
 *              No creamos la Opportunity a mano: tildamos el campo nativo de CPQ
 *              SBQQ__RenewalForecast__c y el trigger de CPQ (SBQQ.ContractAfter) la arma con
 *              sus productos y cantidades (incluidos los Amendments). Verificado en el org
 *              (Contract 00000107): la Opportunity se crea en el MISMO save, en Prospecting.
 *
 *              Todo corre en before: modificamos un campo del mismo registro, así que alcanza
 *              con asignarlo en memoria (sin DML, sin SOQL y sin recursión).
 *
 * Requirement DEV #3 (textual, primera parte): "As a Sales User, I would like a Renewal
 * Opportunity to automatically be generated when a Contract is activated so that I can
 * accurately forecast future sales."
 * Partes del requirement y dónde se cubren:
 *   (A) "when a Contract is activated"           -> setRenewalForecastOnActivation (Status CAMBIA a Activated)
 *   (B) "a Renewal Opportunity ... generated"    -> SBQQ__RenewalForecast__c = true (lo genera CPQ)
 */
public with sharing class ContractTriggerHandler {

    public static final String STATUS_ACTIVATED = 'Activated';

    // ---------------------------------------------------------------------------------
    // Métodos de entrada: uno por contexto de trigger. Solo llaman a la lógica.
    // ---------------------------------------------------------------------------------

    /**
     * @description Entrada del before update. Req (A): el Status pasa a Activated.
     * @param newContractList    Trigger.new (los registros con los valores nuevos)
     * @param oldContractByIdMap Trigger.oldMap (los registros con los valores de antes)
     */
    public static void beforeUpdate( List<Contract> newContractList, Map<Id, Contract> oldContractByIdMap ) {
        setRenewalForecastOnActivation( newContractList, oldContractByIdMap );
    }

    // ---------------------------------------------------------------------------------
    // Lógica (private static)
    // ---------------------------------------------------------------------------------

    /**
     * @description Req (A) y (B). Tilda SBQQ__RenewalForecast__c en los Contracts cuyo Status
     *              CAMBIÓ a Activated en esta transacción y que todavía no lo tienen tildado.
     *              Si el Contract ya estaba activado y se edita otro campo (por ejemplo, el
     *              recuento del DEV #4 o el Batch del DEV #3), no hace nada.
     * @param newContractList    Trigger.new
     * @param oldContractByIdMap Trigger.oldMap
     */
    private static void setRenewalForecastOnActivation( List<Contract> newContractList, Map<Id, Contract> oldContractByIdMap ) {
        for ( Contract newContract : newContractList ) {
            Contract oldContract = oldContractByIdMap.get( newContract.Id );
            // "Se activa" significa que el valor CAMBIÓ a Activated en esta transacción
            Boolean statusChanged = newContract.Status != oldContract.Status;
            if ( statusChanged && newContract.Status == STATUS_ACTIVATED && !newContract.SBQQ__RenewalForecast__c ) {
                // Estamos en before: se asigna en memoria y Salesforce lo guarda en este mismo save
                newContract.SBQQ__RenewalForecast__c = true;
            }
        }
    }
}
