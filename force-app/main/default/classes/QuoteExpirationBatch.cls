/**
 * @description Parte B del DEV #1: todas las noches (lo lanza QuoteExpirationScheduler) busca
 *              las Quotes con una aprobación PENDIENTE que ya vencieron y cuya Opportunity no
 *              está ganada, y les hace recall.
 *
 *              "Recall" (definido con el mentor): retirar la aprobación pendiente, igual que el
 *              botón "Recall" de la UI. En Apex es un Approval.ProcessWorkitemRequest con la
 *              acción 'Removed'. Salesforce corre sola la Recall Action del Approval Process
 *              (Set_Quote_Status_Draft) y desbloquea la Quote: no hace falta Approval.unlock.
 *              Supuesto: las Quotes ya aprobadas no se tocan.
 *
 *              Por qué Batch: procesa las Quotes en tandas de 200 y cada tanda tiene sus propios
 *              governor limits, así que funciona con cualquier volumen.
 *
 * Requirement DEV #1 (textual, segunda parte): "If a Quote reaches the Quote Expiration Date
 * and the related Opportunity is still not 'Closed Won,' then the Quote approvals should be
 * recalled."
 * Partes del requirement y dónde se cubren:
 *   (C) "reaches the Quote Expiration Date"       -> start: SBQQ__ExpirationDate__c <= TODAY
 *   (D) "the related Opportunity is still not     -> start: con Opportunity y IsWon = false
 *        'Closed Won'"
 *   (E) "the Quote approvals should be recalled"  -> recallPendingApprovals (acción 'Removed')
 */
public with sharing class QuoteExpirationBatch implements Database.Batchable<SObject> {

    // Status que ponen los Approval Processes mientras la aprobación está pendiente
    public static final String STATUS_IN_REVIEW = 'In Review';

    // Req (E): 'Removed' es la acción del botón "Recall" sobre una aprobación pendiente
    public static final String RECALL_ACTION = 'Removed';

    private static final String RECALL_COMMENT = 'Recalled automatically: the Quote reached its Expiration Date and the Opportunity is not Closed Won.';
    private static final String CLASS_NAME = 'QuoteExpirationBatch';

    /**
     * @description Req (C) y (D). Trae las Quotes pendientes de aprobación, vencidas, con
     *              Opportunity y con la Opportunity sin ganar. Las Quotes sin Opportunity
     *              quedan afuera (supuesto documentado).
     * @param bc Contexto del Batch (lo pasa Salesforce)
     * @return QueryLocator con las Quotes a procesar
     */
    public Database.QueryLocator start( Database.BatchableContext bc ) {
        return Database.getQueryLocator( [
            SELECT Id
            FROM SBQQ__Quote__c
            WHERE SBQQ__Status__c = :STATUS_IN_REVIEW
            AND SBQQ__ExpirationDate__c <= TODAY
            AND SBQQ__Opportunity2__c != null
            AND SBQQ__Opportunity2__r.IsWon = false
        ] );
    }

    /**
     * @description Se ejecuta una vez por cada tanda de (hasta) 200 Quotes. Solo delega.
     * @param bc        Contexto del Batch
     * @param quoteList Quotes de esta tanda
     */
    public void execute( Database.BatchableContext bc, List<SBQQ__Quote__c> quoteList ) {
        recallPendingApprovals( quoteList );
    }

    /**
     * @description No hay nada que hacer al terminar: los errores ya se guardaron en cada tanda.
     * @param bc Contexto del Batch
     */
    public void finish( Database.BatchableContext bc ) {
        // Vacío a propósito: la interfaz Database.Batchable obliga a tener este método
    }

    /**
     * @description Req (E). Hace recall de las aprobaciones pendientes de estas Quotes.
     *              Una sola query de work items y un solo Approval.process para toda la tanda.
     *              Con allOrNone = false, si un recall falla los demás se hacen igual, y el
     *              error queda en Error_Log__c.
     * @param quoteList Quotes vencidas de esta tanda
     */
    private static void recallPendingApprovals( List<SBQQ__Quote__c> quoteList ) {
        Set<Id> quoteIdSet = new Set<Id>();
        for ( SBQQ__Quote__c quote : quoteList ) {
            quoteIdSet.add( quote.Id );
        }

        // Un work item = una aprobación esperando respuesta. Solo existen si está pendiente.
        List<Approval.ProcessWorkitemRequest> recallRequestList = new List<Approval.ProcessWorkitemRequest>();
        // Lista paralela: en la posición i, la Quote del request i (para el log de errores)
        List<Id> recalledQuoteIdList = new List<Id>();
        for ( ProcessInstanceWorkitem workitem : [
            SELECT Id, ProcessInstance.TargetObjectId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId IN :quoteIdSet
        ] ) {
            Approval.ProcessWorkitemRequest recallRequest = new Approval.ProcessWorkitemRequest();
            recallRequest.setWorkitemId( workitem.Id );
            recallRequest.setAction( RECALL_ACTION );
            recallRequest.setComments( RECALL_COMMENT );
            recallRequestList.add( recallRequest );
            recalledQuoteIdList.add( workitem.ProcessInstance.TargetObjectId );
        }

        // Una Quote puede estar "In Review" sin aprobación pendiente (por ejemplo, si alguien
        // cambió el Status a mano). En ese caso no hay nada que recallear.
        if ( recallRequestList.isEmpty() ) {
            return;
        }

        List<Approval.ProcessResult> resultList = Approval.process( recallRequestList, false );

        // Los resultados vuelven en el mismo orden que los requests: se recorren por posición
        List<Error_Log__c> errorLogList = new List<Error_Log__c>();
        for ( Integer i = 0; i < resultList.size(); i++ ) {
            if ( !resultList[i].isSuccess() ) {
                errorLogList.add( ErrorLogUtil.buildLog( CLASS_NAME, recalledQuoteIdList[i],
                    'Recall failed: ' + resultList[i].getErrors()[0].getMessage() ) );
            }
        }
        ErrorLogUtil.saveLogs( errorLogList );
    }
}
