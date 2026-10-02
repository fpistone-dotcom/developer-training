/**
 * @description Lógica central del DEV #4: recuenta las Subscriptions activas de un grupo de
 *              Contracts y guarda el número en Contract.Active_Subscriptions__c.
 *
 *              La usan los dos caminos (DRY: la regla de "activa" vive en un solo lugar):
 *              - SubscriptionTriggerHandler: cuando se crea, edita, borra o recupera una Subscription.
 *              - ActiveSubscriptionRecountBatch: todas las noches, porque una Subscription puede
 *                empezar o vencer con el paso del tiempo, sin que nadie la edite.
 *
 *              No suma ni resta 1: siempre RECUENTA desde cero con los datos actuales. Así el
 *              número no se desfasa si un update falla o si se cargan datos por fuera.
 *
 *              Definición de "activa" (supuesto confirmado, ver DEV4.md):
 *              - Ya empezó: SBQQ__StartDate__c vacío o <= hoy.
 *              - No venció: SBQQ__EndDate__c vacío (evergreen) o >= hoy.
 *              - No fue terminada: SBQQ__TerminatedDate__c vacío o > hoy.
 *              - El estado del Contract (Draft / Activated) NO se mira: activar el Contract es parte del DEV #3.
 *
 *              Amendments (verificado en el org con el Contract 00000108): CPQ no modifica la
 *              Subscription original, crea una nueva por la diferencia (+100 o -10) con
 *              SBQQ__RevisedSubscription__c apuntando a la ORIGINAL. Por eso se cuenta una vez cada
 *              Subscription original cuya cantidad neta vigente (original + revisiones que ya
 *              empezaron) sea mayor a 0.
 *
 * Requirement DEV #4 (textual): "As a Sales User, I need a field on the Contract that quickly
 * identifies how many active Subscriptions are currently related to the Contract."
 * Partes del requirement y dónde se cubren:
 *   (A) "a field on the Contract"                 -> Active_Subscriptions__c (se escribe en recountActiveSubscriptions)
 *   (B) "how many Subscriptions ... related"      -> countActiveSubscriptions (una por Subscription original)
 *   (C) "active ... currently"                    -> isInForceToday + el Batch nocturno
 */
public with sharing class ActiveSubscriptionCounter {

    private static final String CLASS_NAME = 'ActiveSubscriptionCounter';

    /**
     * @description Req (A), (B) y (C). Recuenta las Subscriptions activas de estos Contracts y
     *              actualiza solo los que cambiaron. 1 SOQL (Contracts con sus Subscriptions en
     *              una subquery) y como máximo 1 DML, sin importar cuántos Contracts lleguen.
     * @param contractIdSet Contracts a recalcular
     */
    public static void recountActiveSubscriptions( Set<Id> contractIdSet ) {
        // Condicional antes de la SOQL: si no hay Contracts, no gastamos una query
        if ( contractIdSet.isEmpty() ) {
            return;
        }

        Date today = Date.today();
        List<Contract> contractToUpdateList = new List<Contract>();

        // Las fechas se leen de las fórmulas SBQQ__StartDate__c / SBQQ__EndDate__c: CPQ ya resuelve
        // ahí "la fecha propia de la Subscription o, si está vacía, la del Contract".
        for ( Contract con : [
            SELECT Id, Active_Subscriptions__c,
                ( SELECT Id, SBQQ__RevisedSubscription__c, SBQQ__Quantity__c,
                         SBQQ__StartDate__c, SBQQ__EndDate__c, SBQQ__TerminatedDate__c
                  FROM SBQQ__Subscriptions__r )
            FROM Contract
            WHERE Id IN :contractIdSet
        ] ) {
            // Cantidad neta vigente por Subscription original (clave = Id de la original)
            Map<Id, Decimal> netQuantityByOriginalIdMap = new Map<Id, Decimal>();

            // Se recorre la subquery con un for (y no pasándola entera a otro método) porque así
            // Salesforce la trae por partes y no falla si un Contract tiene más de 200 Subscriptions
            for ( SBQQ__Subscription__c sub : con.SBQQ__Subscriptions__r ) {
                if ( !isInForceToday( sub, today ) ) {
                    continue;
                }
                // Una revisión de Amendment suma su cantidad (+100 o -10) a la de su original
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

            // Solo se actualiza si el número cambió: menos DML y no se disparan de más los
            // triggers de CPQ sobre Contract
            if ( con.Active_Subscriptions__c != activeCount ) {
                con.Active_Subscriptions__c = activeCount;
                contractToUpdateList.add( con );
            }
        }

        updateContracts( contractToUpdateList );
    }

    /**
     * @description Req (C). Una Subscription está en vigencia HOY si ya empezó, no venció y no
     *              fue terminada. Las fechas vacías no la excluyen (por ejemplo, un Contract
     *              evergreen no tiene fecha de fin).
     * @param sub   Subscription a evaluar (con los campos de fecha consultados)
     * @param today Fecha de hoy
     * @return true si está en vigencia hoy
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
     * @description Req (B). Cuenta las Subscriptions originales que siguen teniendo cantidad
     *              neta positiva. Ejemplo: 125 + 100 - 10 = 215 -> cuenta 1. Si un Amendment la
     *              baja a 0 (125 - 125), deja de contar.
     * @param netQuantityByOriginalIdMap Cantidad neta vigente por Subscription original
     * @return Cantidad de Subscriptions activas
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
     * @description Guarda los Contracts con un solo update. Con allOrNone = false, si uno falla
     *              los demás se guardan igual y el error queda en Error_Log__c, sin cancelar la
     *              transacción que nos llamó (por ejemplo, el contracting de CPQ).
     * @param contractToUpdateList Contracts con el número nuevo
     */
    private static void updateContracts( List<Contract> contractToUpdateList ) {
        if ( contractToUpdateList.isEmpty() ) {
            return;
        }
        List<Database.SaveResult> resultList = Database.update( contractToUpdateList, false );

        // Los resultados vuelven en el mismo orden que la lista: se recorren por posición
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
