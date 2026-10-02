/**
 * @description DEV #4, camino nocturno: todas las noches (lo lanza ActiveSubscriptionRecountScheduler)
 *              recalcula Active_Subscriptions__c en todos los Contracts.
 *
 *              Por qué hace falta: una Subscription puede EMPEZAR (un Amendment con fecha futura)
 *              o VENCER (pasa su fecha de fin o de terminación) sin que nadie la edite, y entonces
 *              el trigger no se entera. Lo mismo si cambian las fechas del Contract, de donde las
 *              Subscriptions toman su fecha de fin. Este Batch corrige todo eso cada noche.
 *
 *              Recorre TODOS los Contracts (y no solo los que tienen Subscriptions) porque la
 *              query es más simple y además completa con 0 los Contracts creados antes del campo.
 *              El recuento solo hace update si el número cambió, así que no hay DML de más.
 *
 *              La lógica no está acá: reutiliza ActiveSubscriptionCounter, el mismo método que
 *              usa el trigger (DRY). Corrido una vez a mano después del deploy, sirve de backfill.
 */
public with sharing class ActiveSubscriptionRecountBatch implements Database.Batchable<SObject> {

    /**
     * @description Trae todos los Contracts. Solo el Id: el recuento hace su propia query.
     * @param bc Contexto del Batch (lo pasa Salesforce)
     * @return QueryLocator con los Contracts a recalcular
     */
    public Database.QueryLocator start( Database.BatchableContext bc ) {
        return Database.getQueryLocator( [
            SELECT Id
            FROM Contract
        ] );
    }

    /**
     * @description Se ejecuta una vez por cada tanda de (hasta) 200 Contracts. Cada tanda
     *              tiene sus propios governor limits.
     * @param bc           Contexto del Batch
     * @param contractList Contracts de esta tanda
     */
    public void execute( Database.BatchableContext bc, List<Contract> contractList ) {
        Set<Id> contractIdSet = new Set<Id>();
        for ( Contract con : contractList ) {
            contractIdSet.add( con.Id );
        }
        // El mismo método que usa SubscriptionTriggerHandler
        ActiveSubscriptionCounter.recountActiveSubscriptions( contractIdSet );
    }

    /**
     * @description No hay nada que hacer al terminar: los errores ya se guardaron en cada tanda.
     * @param bc Contexto del Batch
     */
    public void finish( Database.BatchableContext bc ) {
        // Vacío a propósito: la interfaz Database.Batchable obliga a tener este método
    }
}
