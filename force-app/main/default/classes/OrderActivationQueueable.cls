/**
 * @description Req (B) of DEV #2, "whenever it is created". CPQ creates the Order before
 *              its products, so the activation happens here, a few seconds later, when
 *              the products already exist.
 *
 *              Activating it fires the Auto_Contract_Order_On_Activation Flow,
 *              which marks it as Contracted.
 */
public with sharing class OrderActivationQueueable implements Queueable {

    private static final String CLASS_NAME = 'OrderActivationQueueable';

    private final Set<Id> orderIdSet;

    /**
     * @param orderIdSet Orders to activate
     */
    public OrderActivationQueueable( Set<Id> orderIdSet ) {
        this.orderIdSet = orderIdSet;
    }

    /**
     * @description Checks each Order again with its current data (it could have changed
     *              while waiting) and activates the ones that still meet the rule.
     * @param context Queueable context
     */
    public void execute( QueueableContext context ) {
        List<Order> orderToActivateList = new List<Order>();
        // Req (D): still in Draft and with 'Completed' or 'Not Needed'.
        // The subquery brings at most 1 product per Order: we only care whether it has any.
        for ( Order ord : [
            SELECT Id, ( SELECT Id FROM OrderItems LIMIT 1 )
            FROM Order
            WHERE Id IN :orderIdSet
            AND Status = :OrderTriggerHandler.STATUS_DRAFT
            AND SBQQ__PriceCalcStatus__c IN :OrderTriggerHandler.READY_PRICE_CALC_STATUSES
        ] ) {
            // Not part of the requirement: without products it cannot be activated (Salesforce rule)
            if ( !ord.OrderItems.isEmpty() ) {
                // Req (A): activate the Order
                ord.Status = OrderTriggerHandler.STATUS_ACTIVATED;
                orderToActivateList.add( ord );
            }
        }
        if ( orderToActivateList.isEmpty() ) {
            return;
        }

        // false = if one Order fails, the others are still activated
        List<Database.SaveResult> saveResultList = Database.update( orderToActivateList, false );
        logFailures( orderToActivateList, saveResultList );
    }

    /**
     * @description Not part of the requirement: no error should fail silently.
     *              The results come back in the same order as the list, and a failed result
     *              has no Id, so the Order is found by position (i).
     *              The logs are collected in a list and saved with a single insert at the end.
     * @param orderList      Orders that were sent to update
     * @param saveResultList Results of Database.update
     */
    private static void logFailures( List<Order> orderList, List<Database.SaveResult> saveResultList ) {
        List<Error_Log__c> errorLogList = new List<Error_Log__c>();
        for ( Integer i = 0; i < saveResultList.size(); i++ ) {
            if ( saveResultList[i].isSuccess() ) {
                continue;
            }
            for ( Database.Error error : saveResultList[i].getErrors() ) {
                errorLogList.add( ErrorLogUtil.buildLog( CLASS_NAME, orderList[i].Id,
                    String.valueOf( error.getStatusCode() ) + ' - ' + error.getMessage() ) );
            }
        }
        ErrorLogUtil.saveLogs( errorLogList );
    }
}
