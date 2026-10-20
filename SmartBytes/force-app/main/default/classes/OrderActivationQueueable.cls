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
     * @description Receives the Orders to activate. They are checked again in execute(),
     *              because they could change while the job waits in the queue.
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
        // Not part of the requirement: no error should fail silently (one Error Log per error)
        ErrorLogUtil.saveLogsForFailedResults( saveResultList, orderToActivateList, CLASS_NAME, 'Order activation failed: ' );
    }
}
