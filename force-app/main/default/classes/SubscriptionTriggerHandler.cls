/**
 * @description Lógica del SubscriptionTrigger (DEV #4). Su único trabajo es decidir QUÉ
 *              Contracts hay que recalcular y pasárselos a ActiveSubscriptionCounter, que hace
 *              el recuento (el mismo método que usa el Batch nocturno).
 *
 *              Estructura: los métodos públicos (afterInsert, afterUpdate, afterDelete,
 *              afterUndelete) son la entrada por contexto y solo llaman a métodos private static.
 *
 * Requirement DEV #4 (textual): "As a Sales User, I need a field on the Contract that quickly
 * identifies how many active Subscriptions are currently related to the Contract."
 * Partes del requirement y dónde se cubren en esta clase:
 *   (D) "currently related" -> los 4 contextos; si la Subscription cambia de Contract se
 *                              recalculan los dos (el viejo y el nuevo)
 */
public with sharing class SubscriptionTriggerHandler {

    // ---------------------------------------------------------------------------------
    // Métodos de entrada: uno por contexto de trigger. Solo llaman a la lógica.
    // ---------------------------------------------------------------------------------

    /**
     * @description Entrada del after insert: se recalculan los Contracts de las Subscriptions nuevas.
     * @param newSubscriptionList Trigger.new
     */
    public static void afterInsert( List<SBQQ__Subscription__c> newSubscriptionList ) {
        ActiveSubscriptionCounter.recountActiveSubscriptions( getContractIds( newSubscriptionList ) );
    }

    /**
     * @description Entrada del after update: solo se recalcula si cambió un campo que afecta
     *              el conteo.
     * @param newSubscriptionList     Trigger.new
     * @param oldSubscriptionByIdMap  Trigger.oldMap
     */
    public static void afterUpdate( List<SBQQ__Subscription__c> newSubscriptionList, Map<Id, SBQQ__Subscription__c> oldSubscriptionByIdMap ) {
        ActiveSubscriptionCounter.recountActiveSubscriptions(
            getContractIdsWithRelevantChanges( newSubscriptionList, oldSubscriptionByIdMap ) );
    }

    /**
     * @description Entrada del after delete. En delete no existe Trigger.new: los Contracts
     *              salen de Trigger.old. En after la query ya no ve la Subscription borrada.
     * @param oldSubscriptionList Trigger.old
     */
    public static void afterDelete( List<SBQQ__Subscription__c> oldSubscriptionList ) {
        ActiveSubscriptionCounter.recountActiveSubscriptions( getContractIds( oldSubscriptionList ) );
    }

    /**
     * @description Entrada del after undelete: la Subscription volvió de la papelera.
     * @param newSubscriptionList Trigger.new
     */
    public static void afterUndelete( List<SBQQ__Subscription__c> newSubscriptionList ) {
        ActiveSubscriptionCounter.recountActiveSubscriptions( getContractIds( newSubscriptionList ) );
    }

    // ---------------------------------------------------------------------------------
    // Lógica (private static)
    // ---------------------------------------------------------------------------------

    /**
     * @description Junta los Contracts de estas Subscriptions (sin repetir y sin vacíos).
     * @param subscriptionList Subscriptions del trigger
     * @return Ids de los Contracts a recalcular
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
     * @description Req (D). Devuelve los Contracts a recalcular en un update: solo los de las
     *              Subscriptions donde cambió un campo que afecta el conteo. Si cambió el
     *              Contract, se agregan los DOS: el nuevo (gana una) y el viejo (pierde una).
     *              Se comparan los campos "reales" y no las fórmulas SBQQ__StartDate__c /
     *              SBQQ__EndDate__c, porque las fórmulas no son confiables en Trigger.new.
     * @param newSubscriptionList    Trigger.new
     * @param oldSubscriptionByIdMap Trigger.oldMap
     * @return Ids de los Contracts a recalcular
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
            // Si se movió de Contract, el viejo también cambia (pierde esta Subscription)
            if ( oldSub.SBQQ__Contract__c != null ) {
                contractIdSet.add( oldSub.SBQQ__Contract__c );
            }
        }
        return contractIdSet;
    }

    /**
     * @description true si cambió algún campo que puede cambiar el conteo: el Contract, la
     *              cantidad, las fechas, la terminación o la Subscription original que revisa.
     * @param newSub Subscription con los valores nuevos
     * @param oldSub Subscription con los valores de antes
     * @return true si hay que recalcular
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
