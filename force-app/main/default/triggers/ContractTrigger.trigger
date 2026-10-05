/**
 * @description Single trigger for Contract. It has no logic: it only checks which context it is
 *              running in and calls the matching method of ContractTriggerHandler.
 *
 * Requirement DEV #3 (Part 1):
 *   - before update -> the Status changes to Activated: SBQQ__RenewalForecast__c is checked in the
 *                      same save and CPQ (SBQQ.ContractAfter) generates the Renewal Opportunity.
 *   There is no before insert: Salesforce does not allow creating a Contract that is already
 *   Activated (FAILED_ACTIVATION, verified in the org), so activation is always an update.
 */
trigger ContractTrigger on Contract ( before update ) {
    if ( Trigger.isBefore && Trigger.isUpdate ) {
        ContractTriggerHandler.beforeUpdate( Trigger.new, Trigger.oldMap );
    }
}
