/**
 * @description DEV #4, nightly path: every night (launched by ActiveSubscriptionRecountScheduler)
 *              it recalculates Active_Subscriptions__c on every Contract.
 *
 *              Why it is needed: a Subscription can START (an Amendment with a future date)
 *              or END (its end or termination date passes) without anyone editing it, so the
 *              trigger never finds out. The same happens if the Contract dates change, since the
 *              Subscriptions take their end date from them. This Batch fixes all of that every night.
 *
 *              It goes through ALL the Contracts (not only the ones with Subscriptions) because the
 *              query is simpler and it also fills with 0 the Contracts created before the field existed.
 *              The recount only updates if the number changed, so there is no extra DML.
 *
 *              The logic is not here: it reuses ActiveSubscriptionCounter, the same method the
 *              trigger uses (DRY). Run once manually after the deploy, it works as a backfill.
 */
public with sharing class ActiveSubscriptionRecountBatch implements Database.Batchable<SObject> {

    /**
     * @description Gets all the Contracts. Only the Id: the recount runs its own query.
     * @param bc Batch context (passed by Salesforce)
     * @return QueryLocator with the Contracts to recalculate
     */
    public Database.QueryLocator start( Database.BatchableContext bc ) {
        return Database.getQueryLocator( [
            SELECT Id
            FROM Contract
        ] );
    }

    /**
     * @description Runs once for each chunk of (up to) 200 Contracts. Each chunk
     *              has its own governor limits.
     * @param bc           Batch context
     * @param contractList Contracts in this chunk
     */
    public void execute( Database.BatchableContext bc, List<Contract> contractList ) {
        Set<Id> contractIdSet = new Set<Id>();
        for ( Contract con : contractList ) {
            contractIdSet.add( con.Id );
        }
        // The same method SubscriptionTriggerHandler uses
        ActiveSubscriptionCounter.recountActiveSubscriptions( contractIdSet );
    }

    /**
     * @description Nothing to do at the end: the errors were already saved in each chunk.
     * @param bc Batch context
     */
    public void finish( Database.BatchableContext bc ) {
        // Empty on purpose: the Database.Batchable interface requires this method
    }
}
