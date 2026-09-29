/**
 * @description Req (B) del DEV #2, "cuando la Order se crea". CPQ crea la Order antes
 *              que sus productos, así que la activación se hace acá, unos segundos
 *              después, cuando los productos ya existen.
 *
 *              Al activarla se dispara el Flow Auto_Contract_Order_On_Activation,
 *              que la marca como Contracted.
 */
public with sharing class OrderActivationQueueable implements Queueable {

    private static final String CLASS_NAME = 'OrderActivationQueueable';

    private final Set<Id> orderIdSet;

    /**
     * @param orderIdSet Orders a activar
     */
    public OrderActivationQueueable( Set<Id> orderIdSet ) {
        this.orderIdSet = orderIdSet;
    }

    /**
     * @description Vuelve a revisar cada Order con los datos actuales (pudo cambiar
     *              mientras esperaba) y activa las que todavía cumplen la regla.
     * @param context Contexto del Queueable
     */
    public void execute( QueueableContext context ) {
        List<Order> orderToActivateList = new List<Order>();
        // Req (D): sigue en Draft y con 'Completed' o 'Not Needed'.
        // La subquery trae como máximo 1 producto por Order: solo importa saber si tiene.
        for ( Order ord : [
            SELECT Id, ( SELECT Id FROM OrderItems LIMIT 1 )
            FROM Order
            WHERE Id IN :orderIdSet
            AND Status = :OrderTriggerHandler.STATUS_DRAFT
            AND SBQQ__PriceCalcStatus__c IN :OrderTriggerHandler.READY_PRICE_CALC_STATUSES
        ] ) {
            // No es parte del requirement: sin productos no se puede activar (regla de Salesforce)
            if ( !ord.OrderItems.isEmpty() ) {
                // Req (A): activar la Order
                ord.Status = OrderTriggerHandler.STATUS_ACTIVATED;
                orderToActivateList.add( ord );
            }
        }
        if ( orderToActivateList.isEmpty() ) {
            return;
        }

        // false = si una Order falla, las demás se activan igual
        List<Database.SaveResult> saveResultList = Database.update( orderToActivateList, false );
        logFailures( orderToActivateList, saveResultList );
    }

    /**
     * @description No es parte del requirement: que ningún error pase en silencio.
     *              Los resultados vuelven en el mismo orden que la lista, y un resultado
     *              con error no trae Id, por eso se busca la Order por posición (i).
     *              Los logs se juntan en una lista y se guardan con un solo insert al final.
     * @param orderList      Orders que se mandaron a actualizar
     * @param saveResultList Resultados de Database.update
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
