/**
 * @description Logic for ContractTrigger. Solves Part 1 of DEV #3: when a Contract is
 *              activated, its Renewal Opportunity is generated.
 *
 *              We do not create the Opportunity manually: we check CPQ's native field
 *              SBQQ__RenewalForecast__c and CPQ's trigger (SBQQ.ContractAfter) builds it with
 *              its products and quantities (Amendments included). Verified in the org
 *              (Contract 00000107): the Opportunity is created in the SAME save, in Prospecting.
 *
 *              Everything runs in before: we change a field on the same record, so setting it
 *              in memory is enough (no DML, no SOQL and no recursion).
 *
 *              STATUS_ACTIVATED is public so RenewalQuoteBatch can reuse it (DRY).
 *
 * Requirement DEV #3 (verbatim, first part): "As a Sales User, I would like a Renewal
 * Opportunity to automatically be generated when a Contract is activated so that I can
 * accurately forecast future sales."
 * Requirement parts and where they are covered:
 *   (A) "when a Contract is activated"           -> setRenewalForecastOnActivation (Status CHANGES to Activated)
 *   (B) "a Renewal Opportunity ... generated"    -> SBQQ__RenewalForecast__c = true (CPQ generates it)
 */
public with sharing class ContractTriggerHandler {

    public static final String STATUS_ACTIVATED = 'Activated';

    // ---------------------------------------------------------------------------------
    // Entry methods: one per trigger context. They only call the logic.
    // ---------------------------------------------------------------------------------

    /**
     * @description Before update entry point. Req (A): the Status changes to Activated.
     * @param newContractList    Trigger.new (the records with the new values)
     * @param oldContractByIdMap Trigger.oldMap (the records with the previous values)
     */
    public static void beforeUpdate( List<Contract> newContractList, Map<Id, Contract> oldContractByIdMap ) {
        setRenewalForecastOnActivation( newContractList, oldContractByIdMap );
    }

    // ---------------------------------------------------------------------------------
    // Logic (private static)
    // ---------------------------------------------------------------------------------

    /**
     * @description Req (A) and (B). Checks SBQQ__RenewalForecast__c on the Contracts whose Status
     *              CHANGED to Activated in this transaction and that do not have it checked yet.
     *              If the Contract was already activated and another field is edited (for example,
     *              the DEV #4 recount or the DEV #3 Batch), it does nothing.
     * @param newContractList    Trigger.new
     * @param oldContractByIdMap Trigger.oldMap
     */
    private static void setRenewalForecastOnActivation( List<Contract> newContractList, Map<Id, Contract> oldContractByIdMap ) {
        for ( Contract newContract : newContractList ) {
            Contract oldContract = oldContractByIdMap.get( newContract.Id );
            // "Is activated" means the value CHANGED to Activated in this transaction
            Boolean statusChanged = newContract.Status != oldContract.Status;
            if ( statusChanged && newContract.Status == STATUS_ACTIVATED && !newContract.SBQQ__RenewalForecast__c ) {
                // We are in before: it is set in memory and Salesforce saves it in this same save
                newContract.SBQQ__RenewalForecast__c = true;
            }
        }
    }
}
