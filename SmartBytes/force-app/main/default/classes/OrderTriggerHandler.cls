/**
 * @description Logic for OrderTrigger. Solves DEV #2: automatically activate the Order
 *              when its Price Calculation Status is (or changes to) 'Completed' or
 *              'Not Needed'.
 *
 *              Salesforce does not allow activating an Order without products, so there are two paths:
 *              - When it is created (after insert): CPQ creates the Order before its products,
 *                so the activation is left for later, in OrderActivationQueueable.
 *              - When it is updated (before update): the products already exist, so the
 *                Status is changed directly on the record, with no DML.
 *              Once activated, the Auto_Contract_Order_On_Activation Flow marks it as Contracted.
 *
 *              Structure: the public methods (beforeUpdate, afterInsert) are the entry point
 *              for each context and only call private static methods that hold the logic.
 *
 * Requirement DEV #2 (verbatim): "I want the ability to automatically activate an Order
 * record whenever it is created and the Price Calculation Status on the Order is updated
 * to either 'Completed' or 'Not Needed'."
 * Requirement parts and where they are covered:
 *   (A) "automatically activate an Order"        -> Status = 'Activated'
 *   (B) "whenever it is created"                  -> afterInsert + OrderActivationQueueable
 *   (C) "the Price Calculation Status is updated" -> beforeUpdate (only if the value changes)
 *   (D) "to either 'Completed' or 'Not Needed'"   -> READY_PRICE_CALC_STATUSES
 */
public with sharing class OrderTriggerHandler {

    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_ACTIVATED = 'Activated';

    // Req (D): the two values the requirement asks for to activate the Order
    public static final Set<String> READY_PRICE_CALC_STATUSES = new Set<String>{ 'Completed', 'Not Needed' };

    private static final String CLASS_NAME = 'OrderTriggerHandler';

    // ---------------------------------------------------------------------------------
    // Entry methods: one per trigger context. They only call the logic.
    // ---------------------------------------------------------------------------------

    /**
     * @description Before update entry point. Req (C).
     * @param newOrderList    Trigger.new (the records with the new values)
     * @param oldOrderByIdMap Trigger.oldMap (the records with the previous values)
     */
    public static void beforeUpdate( List<Order> newOrderList, Map<Id, Order> oldOrderByIdMap ) {
        activateOrdersWithChangedPriceCalcStatus( newOrderList, oldOrderByIdMap );
    }

    /**
     * @description After insert entry point. Req (B).
     * @param newOrderList Trigger.new
     */
    public static void afterInsert( List<Order> newOrderList ) {
        enqueueActivationForNewOrders( newOrderList );
    }

    // ---------------------------------------------------------------------------------
    // Logic (private static)
    // ---------------------------------------------------------------------------------

    /**
     * @description Req (C). Activates the Orders whose Price Calculation Status has just
     *              changed to 'Completed' or 'Not Needed', as long as they already have products.
     * @param newOrderList    Trigger.new
     * @param oldOrderByIdMap Trigger.oldMap
     */
    private static void activateOrdersWithChangedPriceCalcStatus( List<Order> newOrderList, Map<Id, Order> oldOrderByIdMap ) {
        List<Order> readyOrderList = filterOrdersReadyOnUpdate( newOrderList, oldOrderByIdMap );
        // Condition before the SOQL: if no Order qualifies, we do not spend any queries
        if ( readyOrderList.isEmpty() ) {
            return;
        }

        // Collect the Ids of the candidate Orders to run a single query for all of them
        Set<Id> readyOrderIdSet = new Set<Id>();
        for ( Order ord : readyOrderList ) {
            readyOrderIdSet.add( ord.Id );
        }

        // Not part of the requirement: Salesforce rule, an Order without products cannot be activated.
        // Covers the case where CPQ changes the status before creating the products.
        Set<Id> orderIdWithItemsSet = getOrderIdsWithItems( readyOrderIdSet );
        for ( Order ord : readyOrderList ) {
            if ( orderIdWithItemsSet.contains( ord.Id ) ) {
                // Req (A): activate. In before it is enough to set the field; Salesforce saves it.
                ord.Status = STATUS_ACTIVATED;
            }
        }
    }

    /**
     * @description Req (B). When the Order is created with a ready status, its activation is
     *              scheduled for a few seconds later, because it does not have products yet.
     * @param newOrderList Trigger.new
     */
    private static void enqueueActivationForNewOrders( List<Order> newOrderList ) {
        Set<Id> orderIdToActivateSet = new Set<Id>();
        for ( Order newOrder : newOrderList ) {
            if ( isReadyToActivate( newOrder ) ) {
                orderIdToActivateSet.add( newOrder.Id );
            }
        }
        if ( orderIdToActivateSet.isEmpty() ) {
            return;
        }

        // Not part of the requirement: if we go over the Queueable limit, Salesforce throws
        // an error that cannot be caught and the whole Order creation is rolled back.
        // It happens if the Order is created from an async process. In that case we log the error and exit.
        if ( Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs() ) {
            List<Error_Log__c> errorLogList = new List<Error_Log__c>();
            for ( Id orderId : orderIdToActivateSet ) {
                errorLogList.add( ErrorLogUtil.buildLog( CLASS_NAME, orderId,
                    'Queueable limit reached: the Order was not activated automatically.' ) );
            }
            ErrorLogUtil.saveLogs( errorLogList );
            return;
        }
        System.enqueueJob( new OrderActivationQueueable( orderIdToActivateSet ) );
    }

    /**
     * @description Req (D). The rule in a single place: the Order is in Draft and its
     *              status is 'Completed' or 'Not Needed'.
     *              Our assumption (not in the requirement): only Draft Orders are activated.
     * @param ord Order to evaluate
     * @return true if the Order can be activated
     */
    private static Boolean isReadyToActivate( Order ord ) {
        if ( ord.Status == STATUS_DRAFT && READY_PRICE_CALC_STATUSES.contains( ord.SBQQ__PriceCalcStatus__c ) ) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @description Req (C). Returns the Orders to activate: the ones whose Price Calculation
     *              Status has just changed to a ready value and that are still in Draft.
     * @param newOrderList    Trigger.new
     * @param oldOrderByIdMap Trigger.oldMap
     * @return Orders ready to activate
     */
    private static List<Order> filterOrdersReadyOnUpdate( List<Order> newOrderList, Map<Id, Order> oldOrderByIdMap ) {
        List<Order> readyOrderList = new List<Order>();
        for ( Order newOrder : newOrderList ) {
            Order oldOrder = oldOrderByIdMap.get( newOrder.Id );
            // "Is updated to" means the value CHANGED. If it did not change, it is not processed again.
            Boolean priceCalcStatusChanged = newOrder.SBQQ__PriceCalcStatus__c != oldOrder.SBQQ__PriceCalcStatus__c;
            if ( priceCalcStatusChanged && isReadyToActivate( newOrder ) ) {
                readyOrderList.add( newOrder );
            }
        }
        return readyOrderList;
    }

    /**
     * @description Not part of the requirement: Salesforce rule. Returns which of these
     *              Orders have at least one product. A single query for all of them;
     *              the subquery brings at most 1 product per Order (LIMIT 1), because
     *              we only care whether it has any or not.
     * @param orderIdSet Orders to check
     * @return Ids of the Orders that have products
     */
    private static Set<Id> getOrderIdsWithItems( Set<Id> orderIdSet ) {
        Set<Id> orderIdWithItemsSet = new Set<Id>();
        for ( Order ord : [
            SELECT Id, ( SELECT Id FROM OrderItems LIMIT 1 )
            FROM Order
            WHERE Id IN :orderIdSet
        ] ) {
            if ( !ord.OrderItems.isEmpty() ) {
                orderIdWithItemsSet.add( ord.Id );
            }
        }
        return orderIdWithItemsSet;
    }
}
