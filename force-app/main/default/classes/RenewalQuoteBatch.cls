/**
 * @description Part 2 of DEV #3: every night (launched by RenewalQuoteScheduler) it finds the
 *              activated Contracts that have 30 days or less left, generates their Renewal Quote
 *              and updates their Renewal Opportunity.
 *
 *              As in Part 1, we do not create the Quote manually: we check CPQ's native field
 *              SBQQ__RenewalQuoted__c and CPQ (SBQQ.ContractAfter) generates it in the same save,
 *              Primary and with the current quantities (Amendments included). Verified in the
 *              org (Contract 00000107 -> Q-00085, Type = Renewal).
 *
 *              "Update the Renewal Opportunity" (confirmed decision): CPQ leaves the Opportunity
 *              in Prospecting, so we move it to 'Proposal/Price Quote' so the forecast shows
 *              that there is already a Quote. Only if it is still in Prospecting: if a sales rep
 *              already moved it forward or closed it, we do not override it.
 *
 *              Window "30 days or less" (and not "exactly 30"): if the job fails one night, or if
 *              a Contract is activated when it already has less than 30 days left, the next night
 *              still processes it. SBQQ__RenewalQuoted__c = true works as an "already processed"
 *              mark, so a Contract is never processed twice.
 *
 *              The Status filter reuses ContractTriggerHandler.STATUS_ACTIVATED (DRY: the
 *              'Activated' value is defined only once).
 *
 *              It runs with chunks of 1 Contract (RenewalQuoteScheduler.BATCH_SIZE): CPQ enqueues
 *              one calculation Queueable per Renewal Quote, and from a Batch only 1 can be
 *              enqueued per execute.
 *
 * Requirement DEV #3 (verbatim, second part): "In addition, 30 days before the end of a
 * Contract, I would like the Renewal Opportunity to be updated and a Renewal Quote generated so
 * that my team can start preparing for the renewal sale."
 * Requirement parts and where they are covered:
 *   (C) "30 days before the end of a Contract"     -> start: Activated, EndDate between today and today + 30
 *   (D) "a Renewal Quote generated"                -> requestRenewalQuotes (SBQQ__RenewalQuoted__c = true)
 *   (E) "the Renewal Opportunity to be updated"    -> updateRenewalOpportunityStage
 */
public with sharing class RenewalQuoteBatch implements Database.Batchable<SObject> {

    // Req (C): days before the end of the Contract
    public static final Integer DAYS_BEFORE_END = 30;

    // Req (E): stage CPQ creates the Renewal Opportunity with, and stage we move it to
    public static final String STAGE_PROSPECTING = 'Prospecting';
    public static final String STAGE_PROPOSAL = 'Proposal/Price Quote';

    private static final String CLASS_NAME = 'RenewalQuoteBatch';

    /**
     * @description Req (C). Gets the activated Contracts that end between today and today + 30 and
     *              that do not have a Renewal Quote yet. Expired ones (EndDate < today) and evergreen
     *              ones (no EndDate) are left out (confirmed assumptions).
     * @param bc Batch context (passed by Salesforce)
     * @return QueryLocator with the Contracts to process
     */
    public Database.QueryLocator start( Database.BatchableContext bc ) {
        Date today = Date.today();
        Date windowEndDate = today.addDays( DAYS_BEFORE_END );
        return Database.getQueryLocator( [
            SELECT Id
            FROM Contract
            WHERE Status = :ContractTriggerHandler.STATUS_ACTIVATED
            AND SBQQ__RenewalQuoted__c = false
            AND EndDate >= :today
            AND EndDate <= :windowEndDate
        ] );
    }

    /**
     * @description Runs once for each chunk (of 1 Contract, see BATCH_SIZE). First it
     *              generates the Renewal Quotes and then it updates the Opportunities of the
     *              Contracts that were saved successfully.
     * @param bc           Batch context
     * @param contractList Contracts in this chunk
     */
    public void execute( Database.BatchableContext bc, List<Contract> contractList ) {
        Set<Id> quotedContractIdSet = requestRenewalQuotes( contractList );
        updateRenewalOpportunityStage( quotedContractIdSet );
    }

    /**
     * @description Nothing to do at the end: the errors were already saved in each chunk.
     * @param bc Batch context
     */
    public void finish( Database.BatchableContext bc ) {
        // Empty on purpose: the Database.Batchable interface requires this method
    }

    /**
     * @description Req (D). Checks SBQQ__RenewalQuoted__c so CPQ generates the Renewal Quote.
     *              It also checks SBQQ__RenewalForecast__c as a safety net: if the Contract
     *              was activated before the trigger existed (or Part 1 failed), CPQ creates
     *              the Opportunity and the Quote in the same save.
     *              A single update for the whole chunk; with allOrNone = false, if one fails the
     *              others are still saved and the error is stored in Error_Log__c.
     * @param contractList Contracts in this chunk
     * @return Ids of the Contracts that were saved successfully (only those have a Renewal Quote)
     */
    private static Set<Id> requestRenewalQuotes( List<Contract> contractList ) {
        for ( Contract con : contractList ) {
            con.SBQQ__RenewalForecast__c = true;
            con.SBQQ__RenewalQuoted__c = true;
        }
        List<Database.SaveResult> resultList = Database.update( contractList, false );

        // The results come back in the same order as the list: they are read by position
        Set<Id> quotedContractIdSet = new Set<Id>();
        for ( Integer i = 0; i < resultList.size(); i++ ) {
            if ( resultList[i].isSuccess() ) {
                quotedContractIdSet.add( contractList[i].Id );
            }
        }
        saveLogsForFailures( resultList, contractList, 'Renewal Quote request failed: ' );
        return quotedContractIdSet;
    }

    /**
     * @description Req (E). Moves to 'Proposal/Price Quote' the Renewal Opportunities of these
     *              Contracts that are still in Prospecting. One query and one update for the whole chunk.
     * @param quotedContractIdSet Contracts that already have their Renewal Quote
     */
    private static void updateRenewalOpportunityStage( Set<Id> quotedContractIdSet ) {
        // Condition before the SOQL: if no Contract was saved successfully, there is nothing to update
        if ( quotedContractIdSet.isEmpty() ) {
            return;
        }

        // SBQQ__RenewedContract__c: the Contract this Opportunity renews (filled in by CPQ)
        List<Opportunity> opportunityToUpdateList = new List<Opportunity>();
        for ( Opportunity opp : [
            SELECT Id, StageName
            FROM Opportunity
            WHERE SBQQ__RenewedContract__c IN :quotedContractIdSet
            AND StageName = :STAGE_PROSPECTING
        ] ) {
            opp.StageName = STAGE_PROPOSAL;
            opportunityToUpdateList.add( opp );
        }

        if ( opportunityToUpdateList.isEmpty() ) {
            return;
        }
        List<Database.SaveResult> resultList = Database.update( opportunityToUpdateList, false );
        saveLogsForFailures( resultList, opportunityToUpdateList, 'Renewal Opportunity stage update failed: ' );
    }

    /**
     * @description Builds an Error_Log__c for each record that could not be saved and saves them
     *              with a single insert. Both updates of the Batch use it (DRY).
     * @param resultList    Results of Database.update
     * @param recordList    Records that were sent to save (in the same order as resultList)
     * @param messagePrefix Text that explains what failed
     */
    private static void saveLogsForFailures( List<Database.SaveResult> resultList, List<SObject> recordList, String messagePrefix ) {
        List<Error_Log__c> errorLogList = new List<Error_Log__c>();
        for ( Integer i = 0; i < resultList.size(); i++ ) {
            if ( !resultList[i].isSuccess() ) {
                errorLogList.add( ErrorLogUtil.buildLog( CLASS_NAME, recordList[i].Id,
                    messagePrefix + resultList[i].getErrors()[0].getMessage() ) );
            }
        }
        ErrorLogUtil.saveLogs( errorLogList );
    }
}
