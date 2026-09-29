/**
 * @description Lógica del OrderTrigger. Resuelve el DEV #2: activar la Order
 *              automáticamente cuando su Price Calculation Status es (o pasa a ser)
 *              'Completed' o 'Not Needed'.
 *
 *              Salesforce no deja activar una Order sin productos, por eso hay dos caminos:
 *              - Cuando se crea (after insert): CPQ crea la Order antes que sus productos,
 *                así que la activación se deja para después, en OrderActivationQueueable.
 *              - Cuando se actualiza (before update): los productos ya existen, así que
 *                se cambia el Status directo en el registro, sin DML.
 *              Una vez activada, el Flow Auto_Contract_Order_On_Activation la marca como Contracted.
 *
 *              Estructura: los métodos públicos (beforeUpdate, afterInsert) son la entrada
 *              por contexto y solo llaman a métodos private static que tienen la lógica.
 *
 * Requirement DEV #2 (textual): "I want the ability to automatically activate an Order
 * record whenever it is created and the Price Calculation Status on the Order is updated
 * to either 'Completed' or 'Not Needed'."
 * Partes del requirement y dónde se cubren:
 *   (A) "activar la Order automáticamente"         -> Status = 'Activated'
 *   (B) "cuando se crea"                            -> afterInsert + OrderActivationQueueable
 *   (C) "cuando el Price Calculation Status cambia" -> beforeUpdate (solo si el valor cambia)
 *   (D) "a 'Completed' o 'Not Needed'"              -> READY_PRICE_CALC_STATUSES
 */
public with sharing class OrderTriggerHandler {

    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_ACTIVATED = 'Activated';

    // Req (D): los dos valores que pide el requirement para activar la Order
    public static final Set<String> READY_PRICE_CALC_STATUSES = new Set<String>{ 'Completed', 'Not Needed' };

    private static final String CLASS_NAME = 'OrderTriggerHandler';

    // ---------------------------------------------------------------------------------
    // Métodos de entrada: uno por contexto de trigger. Solo llaman a la lógica.
    // ---------------------------------------------------------------------------------

    /**
     * @description Entrada del before update. Req (C).
     * @param newOrderList    Trigger.new (los registros con los valores nuevos)
     * @param oldOrderByIdMap Trigger.oldMap (los registros con los valores de antes)
     */
    public static void beforeUpdate( List<Order> newOrderList, Map<Id, Order> oldOrderByIdMap ) {
        activateOrdersWithChangedPriceCalcStatus( newOrderList, oldOrderByIdMap );
    }

    /**
     * @description Entrada del after insert. Req (B).
     * @param newOrderList Trigger.new
     */
    public static void afterInsert( List<Order> newOrderList ) {
        enqueueActivationForNewOrders( newOrderList );
    }

    // ---------------------------------------------------------------------------------
    // Lógica (private static)
    // ---------------------------------------------------------------------------------

    /**
     * @description Req (C). Activa las Orders cuyo Price Calculation Status acaba de
     *              cambiar a 'Completed' o 'Not Needed', siempre que ya tengan productos.
     * @param newOrderList    Trigger.new
     * @param oldOrderByIdMap Trigger.oldMap
     */
    private static void activateOrdersWithChangedPriceCalcStatus( List<Order> newOrderList, Map<Id, Order> oldOrderByIdMap ) {
        List<Order> readyOrderList = filterOrdersReadyOnUpdate( newOrderList, oldOrderByIdMap );
        // Condicional antes de la SOQL: si ninguna Order califica, no gastamos queries
        if ( readyOrderList.isEmpty() ) {
            return;
        }

        // Juntamos los Ids de las Orders candidatas para hacer una sola query con todas
        Set<Id> readyOrderIdSet = new Set<Id>();
        for ( Order ord : readyOrderList ) {
            readyOrderIdSet.add( ord.Id );
        }

        // No es parte del requirement: regla de Salesforce, una Order sin productos no se puede activar.
        // Cubre el caso en que CPQ cambie el status antes de crear los productos.
        Set<Id> orderIdWithItemsSet = getOrderIdsWithItems( readyOrderIdSet );
        for ( Order ord : readyOrderList ) {
            if ( orderIdWithItemsSet.contains( ord.Id ) ) {
                // Req (A): activar. En before alcanza con asignar el campo, Salesforce lo guarda solo.
                ord.Status = STATUS_ACTIVATED;
            }
        }
    }

    /**
     * @description Req (B). Cuando la Order se crea con un status listo, deja anotada su
     *              activación para unos segundos después, porque todavía no tiene productos.
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

        // No es parte del requirement: si nos pasamos del límite de Queueables, Salesforce tira
        // un error que no se puede atrapar y se cancela la creación de la Order entera.
        // Pasa si la Order se crea desde un proceso async. En ese caso registramos el error y salimos.
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
     * @description Req (D). La regla en un solo lugar: la Order está en Draft y su
     *              status es 'Completed' o 'Not Needed'.
     *              Supuesto nuestro (no está en el requirement): solo se activan Orders en Draft.
     * @param ord Order a evaluar
     * @return true si la Order se puede activar
     */
    private static Boolean isReadyToActivate( Order ord ) {
        if ( ord.Status == STATUS_DRAFT && READY_PRICE_CALC_STATUSES.contains( ord.SBQQ__PriceCalcStatus__c ) ) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @description Req (C). Devuelve las Orders que hay que activar: las que tienen el
     *              Price Calculation Status recién cambiado a un valor listo y siguen en Draft.
     * @param newOrderList    Trigger.new
     * @param oldOrderByIdMap Trigger.oldMap
     * @return Orders listas para activar
     */
    private static List<Order> filterOrdersReadyOnUpdate( List<Order> newOrderList, Map<Id, Order> oldOrderByIdMap ) {
        List<Order> readyOrderList = new List<Order>();
        for ( Order newOrder : newOrderList ) {
            Order oldOrder = oldOrderByIdMap.get( newOrder.Id );
            // "Se actualiza a" significa que el valor CAMBIÓ. Si no cambió, no se vuelve a procesar.
            Boolean priceCalcStatusChanged = newOrder.SBQQ__PriceCalcStatus__c != oldOrder.SBQQ__PriceCalcStatus__c;
            if ( priceCalcStatusChanged && isReadyToActivate( newOrder ) ) {
                readyOrderList.add( newOrder );
            }
        }
        return readyOrderList;
    }

    /**
     * @description No es parte del requirement: regla de Salesforce. Devuelve cuáles de
     *              estas Orders tienen al menos un producto. Una sola query para todas;
     *              la subquery trae como máximo 1 producto por Order (LIMIT 1), porque
     *              solo nos importa saber si tiene o no.
     * @param orderIdSet Orders a revisar
     * @return Ids de las Orders que tienen productos
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
