/**
 * @description Core logic of DEV #4: recounts the active Subscriptions of a group of
 *              Contracts and saves the number in Contract.Active_Subscriptions__c.
 *
 *              Both paths use it (DRY: the "active" rule lives in a single place):
 *              - SubscriptionTriggerHandler: when a Subscription is created, edited, deleted or restored.
 *              - ActiveSubscriptionRecountBatch: every night, because a Subscription can
 *                start or end as time passes, without anyone editing it.
 *
 *              It does not add or subtract 1: it always RECOUNTS from scratch with the current data.
 *              That way the number does not drift if an update fails or data is loaded externally.
 *
 *              Definition of "active" (confirmed assumption, see DEV4.md):
 *              - Already started: SBQQ__StartDate__c blank or <= today.
 *              - Not ended: SBQQ__EndDate__c blank (evergreen) or >= today.
 *              - Not terminated: SBQQ__TerminatedDate__c blank or > today.
 *              - The Contract status (Draft / Activated) is NOT checked: activating the Contract is part of DEV #3.
 *
 *              Amendments (verified in the org with Contract 00000108): CPQ does not modify the
 *              original Subscription, it creates a new one for the difference (+100 or -10) with
 *              SBQQ__RevisedSubscription__c pointing to the ORIGINAL. That is why each original
 *              Subscription is counted once if its net quantity in force (original + revisions
 *              that have already started) is greater than 0.
 *
 * Requirement DEV #4 (verbatim): "As a Sales User, I need a field on the Contract that quickly
 * identifies how many active Subscriptions are currently related to the Contract."
 * Requirement parts and where they are covered:
 *   (A) "a field on the Contract"                 -> Active_Subscriptions__c (written in recountActiveSubscriptions)
 *   (B) "how many Subscriptions ... related"      -> countActiveSubscriptions (one per original Subscription)
 *   (C) "active ... currently"                    -> isInForceToday + the nightly Batch
 */
public with sharing class ActiveSubscriptionCounter {

    private static final String CLASS_NAME = 'ActiveSubscriptionCounter';

    /**
     * @description Req (A), (B) and (C). Recounts the active Subscriptions of these Contracts and
     *              updates only the ones that changed. 1 SOQL (Contracts with their Subscriptions in
     *              a subquery) and at most 1 DML, no matter how many Contracts come in.
     * @param contractIdSet Contracts to recalculate
     */
    public static void recountActiveSubscriptions( Set<Id> contractIdSet ) {
        // Condition before the SOQL: if there are no Contracts, we do not spend a query
        if ( contractIdSet.isEmpty() ) {
            return;
        }

        Date today = Date.today();
        List<Contract> contractToUpdateList = new List<Contract>();

        // The dates are read from the SBQQ__StartDate__c / SBQQ__EndDate__c formulas: CPQ already
        // resolves there "the Subscription's own date or, if blank, the Contract's date".
        for ( Contract con : [
            SELECT Id, Active_Subscriptions__c,
                ( SELECT Id, SBQQ__RevisedSubscription__c, SBQQ__Quantity__c,
                         SBQQ__StartDate__c, SBQQ__EndDate__c, SBQQ__TerminatedDate__c
                  FROM SBQQ__Subscriptions__r )
            FROM Contract
            WHERE Id IN :contractIdSet
        ] ) {
            // Net quantity in force per original Subscription (key = Id of the original)
            Map<Id, Decimal> netQuantityByOriginalIdMap = new Map<Id, Decimal>();

            // The subquery is iterated with a for (and not passed whole to another method) because
            // this way Salesforce fetches it in parts and it does not fail if a Contract has more than 200 Subscriptions
            for ( SBQQ__Subscription__c sub : con.SBQQ__Subscriptions__r ) {
                if ( !isInForceToday( sub, today ) ) {
                    continue;
                }
                // An Amendment revision adds its quantity (+100 or -10) to its original's quantity
                Id originalId = sub.Id;
                if ( sub.SBQQ__RevisedSubscription__c != null ) {
                    originalId = sub.SBQQ__RevisedSubscription__c;
                }
                Decimal quantity = 0;
                if ( sub.SBQQ__Quantity__c != null ) {
                    quantity = sub.SBQQ__Quantity__c;
                }
                Decimal netQuantity = 0;
                if ( netQuantityByOriginalIdMap.containsKey( originalId ) ) {
                    netQuantity = netQuantityByOriginalIdMap.get( originalId );
                }
                netQuantityByOriginalIdMap.put( originalId, netQuantity + quantity );
            }

            Integer activeCount = countActiveSubscriptions( netQuantityByOriginalIdMap );

            // Only update if the number changed: less DML and CPQ's Contract triggers
            // are not fired unnecessarily
            if ( con.Active_Subscriptions__c != activeCount ) {
                con.Active_Subscriptions__c = activeCount;
                contractToUpdateList.add( con );
            }
        }

        updateContracts( contractToUpdateList );
    }

    /**
     * @description Req (C). A Subscription is in force TODAY if it has started, has not ended and
     *              was not terminated. Blank dates do not exclude it (for example, an evergreen
     *              Contract has no end date).
     * @param sub   Subscription to evaluate (with the date fields queried)
     * @param today Today's date
     * @return true if it is in force today
     */
    private static Boolean isInForceToday( SBQQ__Subscription__c sub, Date today ) {
        Boolean hasStarted = sub.SBQQ__StartDate__c == null || sub.SBQQ__StartDate__c <= today;
        Boolean hasNotEnded = sub.SBQQ__EndDate__c == null || sub.SBQQ__EndDate__c >= today;
        Boolean isNotTerminated = sub.SBQQ__TerminatedDate__c == null || sub.SBQQ__TerminatedDate__c > today;
        if ( hasStarted && hasNotEnded && isNotTerminated ) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @description Req (B). Counts the original Subscriptions that still have a positive net
     *              quantity. Example: 125 + 100 - 10 = 215 -> counts 1. If an Amendment brings it
     *              down to 0 (125 - 125), it stops counting.
     * @param netQuantityByOriginalIdMap Net quantity in force per original Subscription
     * @return Number of active Subscriptions
     */
    private static Integer countActiveSubscriptions( Map<Id, Decimal> netQuantityByOriginalIdMap ) {
        Integer activeCount = 0;
        for ( Decimal netQuantity : netQuantityByOriginalIdMap.values() ) {
            if ( netQuantity > 0 ) {
                activeCount++;
            }
        }
        return activeCount;
    }

    /**
     * @description Saves the Contracts with a single update. With allOrNone = false, if one fails
     *              the others are still saved and the error is stored in Error_Log__c, without
     *              cancelling the transaction that called us (for example, CPQ's contracting).
     * @param contractToUpdateList Contracts with the new number
     */
    private static void updateContracts( List<Contract> contractToUpdateList ) {
        if ( contractToUpdateList.isEmpty() ) {
            return;
        }
        List<Database.SaveResult> resultList = Database.update( contractToUpdateList, false );

        // The results come back in the same order as the list: they are read by position
        List<Error_Log__c> errorLogList = new List<Error_Log__c>();
        for ( Integer i = 0; i < resultList.size(); i++ ) {
            if ( !resultList[i].isSuccess() ) {
                errorLogList.add( ErrorLogUtil.buildLog( CLASS_NAME, contractToUpdateList[i].Id,
                    'Active Subscriptions recount failed: ' + resultList[i].getErrors()[0].getMessage() ) );
            }
        }
        ErrorLogUtil.saveLogs( errorLogList );
    }
}
