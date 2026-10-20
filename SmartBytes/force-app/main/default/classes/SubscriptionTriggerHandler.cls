/**
 * @description Logic for SubscriptionTrigger (DEV #4). Its only job is to decide WHICH
 *              Contracts must be recalculated and hand them to ActiveSubscriptionCounter, which
 *              does the recount (the same method the nightly Batch uses).
 *
 *              Structure: the public methods (afterInsert, afterUpdate, afterDelete,
 *              afterUndelete) are the entry point for each context and only call private static methods.
 *
 * Requirement DEV #4 (verbatim): "As a Sales User, I need a field on the Contract that quickly
 * identifies how many active Subscriptions are currently related to the Contract."
 * Requirement parts and where they are covered in this class:
 *   (D) "currently related" -> the 4 contexts; if the Subscription moves to another Contract
 *                              both are recalculated (the old one and the new one)
 */
public with sharing class SubscriptionTriggerHandler {

    // ---------------------------------------------------------------------------------
    // Entry methods: one per trigger context. They only call the logic.
    // ---------------------------------------------------------------------------------

    /**
     * @description After insert entry point: the Contracts of the new Subscriptions are recalculated.
     * @param newSubscriptionList Trigger.new
     */
    public static void afterInsert( List<SBQQ__Subscription__c> newSubscriptionList ) {
        ActiveSubscriptionCounter.recountActiveSubscriptions( getContractIds( newSubscriptionList ) );
    }

    /**
     * @description After update entry point: it only recalculates if a field that affects
     *              the count changed.
     * @param newSubscriptionList     Trigger.new
     * @param oldSubscriptionByIdMap  Trigger.oldMap
     */
    public static void afterUpdate( List<SBQQ__Subscription__c> newSubscriptionList, Map<Id, SBQQ__Subscription__c> oldSubscriptionByIdMap ) {
        ActiveSubscriptionCounter.recountActiveSubscriptions(
            getContractIdsWithRelevantChanges( newSubscriptionList, oldSubscriptionByIdMap ) );
    }

    /**
     * @description After delete entry point. On delete there is no Trigger.new: the Contracts
     *              come from Trigger.old. In after, the query no longer sees the deleted Subscription.
     * @param oldSubscriptionList Trigger.old
     */
    public static void afterDelete( List<SBQQ__Subscription__c> oldSubscriptionList ) {
        ActiveSubscriptionCounter.recountActiveSubscriptions( getContractIds( oldSubscriptionList ) );
    }

    /**
     * @description After undelete entry point: the Subscription came back from the Recycle Bin.
     * @param newSubscriptionList Trigger.new
     */
    public static void afterUndelete( List<SBQQ__Subscription__c> newSubscriptionList ) {
        ActiveSubscriptionCounter.recountActiveSubscriptions( getContractIds( newSubscriptionList ) );
    }

    // ---------------------------------------------------------------------------------
    // Logic (private static)
    // ---------------------------------------------------------------------------------

    /**
     * @description Collects the Contracts of these Subscriptions (no duplicates and no blanks).
     * @param subscriptionList Subscriptions from the trigger
     * @return Ids of the Contracts to recalculate
     */
    private static Set<Id> getContractIds( List<SBQQ__Subscription__c> subscriptionList ) {
        Set<Id> contractIdSet = new Set<Id>();
        for ( SBQQ__Subscription__c sub : subscriptionList ) {
            if ( sub.SBQQ__Contract__c != null ) {
                contractIdSet.add( sub.SBQQ__Contract__c );
            }
        }
        return contractIdSet;
    }

    /**
     * @description Req (D). Returns the Contracts to recalculate on an update: only those of the
     *              Subscriptions where a field that affects the count changed. If the Contract
     *              changed, BOTH are added: the new one (gains one) and the old one (loses one).
     *              The "real" fields are compared, not the SBQQ__StartDate__c / SBQQ__EndDate__c
     *              formulas, because formulas are not reliable in Trigger.new.
     * @param newSubscriptionList    Trigger.new
     * @param oldSubscriptionByIdMap Trigger.oldMap
     * @return Ids of the Contracts to recalculate
     */
    private static Set<Id> getContractIdsWithRelevantChanges( List<SBQQ__Subscription__c> newSubscriptionList, Map<Id, SBQQ__Subscription__c> oldSubscriptionByIdMap ) {
        Set<Id> contractIdSet = new Set<Id>();
        for ( SBQQ__Subscription__c newSub : newSubscriptionList ) {
            SBQQ__Subscription__c oldSub = oldSubscriptionByIdMap.get( newSub.Id );
            if ( !hasRelevantChange( newSub, oldSub ) ) {
                continue;
            }
            if ( newSub.SBQQ__Contract__c != null ) {
                contractIdSet.add( newSub.SBQQ__Contract__c );
            }
            // If it moved to another Contract, the old one also changes (it loses this Subscription)
            if ( oldSub.SBQQ__Contract__c != null ) {
                contractIdSet.add( oldSub.SBQQ__Contract__c );
            }
        }
        return contractIdSet;
    }

    /**
     * @description true if any field that can change the count was modified: the Contract, the
     *              quantity, the dates, the termination or the original Subscription it revises.
     * @param newSub Subscription with the new values
     * @param oldSub Subscription with the previous values
     * @return true if it has to be recalculated
     */
    private static Boolean hasRelevantChange( SBQQ__Subscription__c newSub, SBQQ__Subscription__c oldSub ) {
        if ( newSub.SBQQ__Contract__c != oldSub.SBQQ__Contract__c
            || newSub.SBQQ__Quantity__c != oldSub.SBQQ__Quantity__c
            || newSub.SBQQ__SubscriptionStartDate__c != oldSub.SBQQ__SubscriptionStartDate__c
            || newSub.SBQQ__SubscriptionEndDate__c != oldSub.SBQQ__SubscriptionEndDate__c
            || newSub.SBQQ__TerminatedDate__c != oldSub.SBQQ__TerminatedDate__c
            || newSub.SBQQ__RevisedSubscription__c != oldSub.SBQQ__RevisedSubscription__c ) {
            return true;
        } else {
            return false;
        }
    }
}
