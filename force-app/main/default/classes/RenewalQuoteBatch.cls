/**
 * @description Parte 2 del DEV #3: todas las noches (lo lanza RenewalQuoteScheduler) busca los
 *              Contracts activados a los que les quedan 30 días o menos, genera su Renewal Quote
 *              y actualiza su Renewal Opportunity.
 *
 *              Igual que en la Parte 1, no creamos la Quote a mano: tildamos el campo nativo de
 *              CPQ SBQQ__RenewalQuoted__c y CPQ (SBQQ.ContractAfter) la genera en el mismo save,
 *              Primary y con las cantidades actuales (incluidos los Amendments). Verificado en el
 *              org (Contract 00000107 -> Q-00085, Type = Renewal).
 *
 *              "Actualizar la Renewal Opportunity" (decisión confirmada): CPQ deja la Opportunity
 *              en Prospecting, así que la pasamos a 'Proposal/Price Quote' para que el forecast
 *              muestre que ya hay una Quote. Solo si sigue en Prospecting: si un vendedor ya la
 *              avanzó o la cerró, no la pisamos.
 *
 *              Ventana "30 días o menos" (y no "exactamente 30"): si el job falla una noche, o si
 *              un Contract se activa cuando ya le quedan menos de 30 días, la noche siguiente lo
 *              procesa igual. SBQQ__RenewalQuoted__c = true funciona como marca de "ya procesado",
 *              así que un Contract nunca se procesa dos veces.
 *
 *              Se ejecuta con tandas de 1 Contract (RenewalQuoteScheduler.BATCH_SIZE): CPQ encola
 *              un Queueable de cálculo por cada Renewal Quote, y desde un Batch solo se puede
 *              encolar 1 por execute.
 *
 * Requirement DEV #3 (textual, segunda parte): "In addition, 30 days before the end of a
 * Contract, I would like the Renewal Opportunity to be updated and a Renewal Quote generated so
 * that my team can start preparing for the renewal sale."
 * Partes del requirement y dónde se cubren:
 *   (C) "30 days before the end of a Contract"     -> start: Activated, EndDate entre hoy y hoy + 30
 *   (D) "a Renewal Quote generated"                -> requestRenewalQuotes (SBQQ__RenewalQuoted__c = true)
 *   (E) "the Renewal Opportunity to be updated"    -> updateRenewalOpportunityStage
 */
public with sharing class RenewalQuoteBatch implements Database.Batchable<SObject> {

    public static final String STATUS_ACTIVATED = 'Activated';

    // Req (C): días antes del fin del Contract
    public static final Integer DAYS_BEFORE_END = 30;

    // Req (E): etapa con la que CPQ crea la Renewal Opportunity y etapa a la que la pasamos
    public static final String STAGE_PROSPECTING = 'Prospecting';
    public static final String STAGE_PROPOSAL = 'Proposal/Price Quote';

    private static final String CLASS_NAME = 'RenewalQuoteBatch';

    /**
     * @description Req (C). Trae los Contracts activados que vencen entre hoy y hoy + 30 y que
     *              todavía no tienen Renewal Quote. Los vencidos (EndDate < hoy) y los evergreen
     *              (sin EndDate) quedan afuera (supuestos confirmados).
     * @param bc Contexto del Batch (lo pasa Salesforce)
     * @return QueryLocator con los Contracts a procesar
     */
    public Database.QueryLocator start( Database.BatchableContext bc ) {
        Date today = Date.today();
        Date windowEndDate = today.addDays( DAYS_BEFORE_END );
        return Database.getQueryLocator( [
            SELECT Id
            FROM Contract
            WHERE Status = :STATUS_ACTIVATED
            AND SBQQ__RenewalQuoted__c = false
            AND EndDate >= :today
            AND EndDate <= :windowEndDate
        ] );
    }

    /**
     * @description Se ejecuta una vez por cada tanda (de 1 Contract, ver BATCH_SIZE). Primero
     *              genera las Renewal Quotes y después actualiza las Opportunities de los
     *              Contracts que se guardaron bien.
     * @param bc           Contexto del Batch
     * @param contractList Contracts de esta tanda
     */
    public void execute( Database.BatchableContext bc, List<Contract> contractList ) {
        Set<Id> quotedContractIdSet = requestRenewalQuotes( contractList );
        updateRenewalOpportunityStage( quotedContractIdSet );
    }

    /**
     * @description No hay nada que hacer al terminar: los errores ya se guardaron en cada tanda.
     * @param bc Contexto del Batch
     */
    public void finish( Database.BatchableContext bc ) {
        // Vacío a propósito: la interfaz Database.Batchable obliga a tener este método
    }

    /**
     * @description Req (D). Tilda SBQQ__RenewalQuoted__c para que CPQ genere la Renewal Quote.
     *              También tilda SBQQ__RenewalForecast__c como red de seguridad: si el Contract
     *              se activó antes de que existiera el trigger (o la Parte 1 falló), CPQ crea
     *              la Opportunity y la Quote en el mismo save.
     *              Un solo update para toda la tanda; con allOrNone = false, si uno falla los
     *              demás se guardan igual y el error queda en Error_Log__c.
     * @param contractList Contracts de esta tanda
     * @return Ids de los Contracts que se guardaron bien (solo esos tienen Renewal Quote)
     */
    private static Set<Id> requestRenewalQuotes( List<Contract> contractList ) {
        for ( Contract con : contractList ) {
            con.SBQQ__RenewalForecast__c = true;
            con.SBQQ__RenewalQuoted__c = true;
        }
        List<Database.SaveResult> resultList = Database.update( contractList, false );

        // Los resultados vuelven en el mismo orden que la lista: se recorren por posición
        Set<Id> quotedContractIdSet = new Set<Id>();
        for ( Integer i = 0; i < resultList.size(); i++ ) {
            if ( resultList[i].isSuccess() ) {
                quotedContractIdSet.add( contractList[i].Id );
            }
        }
        saveLogsForFailures( resultList, contractList, 'Renewal Quote request failed: ' );
        return quotedContractIdSet;
    }

    /**
     * @description Req (E). Pasa a 'Proposal/Price Quote' las Renewal Opportunities de estos
     *              Contracts que siguen en Prospecting. Una query y un update para toda la tanda.
     * @param quotedContractIdSet Contracts que ya tienen su Renewal Quote
     */
    private static void updateRenewalOpportunityStage( Set<Id> quotedContractIdSet ) {
        // Condicional antes de la SOQL: si ningún Contract se guardó bien, no hay nada que actualizar
        if ( quotedContractIdSet.isEmpty() ) {
            return;
        }

        // SBQQ__RenewedContract__c: el Contract que renueva esta Opportunity (lo completa CPQ)
        List<Opportunity> opportunityToUpdateList = new List<Opportunity>();
        for ( Opportunity opp : [
            SELECT Id, StageName
            FROM Opportunity
            WHERE SBQQ__RenewedContract__c IN :quotedContractIdSet
            AND StageName = :STAGE_PROSPECTING
        ] ) {
            opp.StageName = STAGE_PROPOSAL;
            opportunityToUpdateList.add( opp );
        }

        if ( opportunityToUpdateList.isEmpty() ) {
            return;
        }
        List<Database.SaveResult> resultList = Database.update( opportunityToUpdateList, false );
        saveLogsForFailures( resultList, opportunityToUpdateList, 'Renewal Opportunity stage update failed: ' );
    }

    /**
     * @description Arma un Error_Log__c por cada registro que no se pudo guardar y los guarda con
     *              un solo insert. Lo usan los dos updates del Batch (DRY).
     * @param resultList    Resultados del Database.update
     * @param recordList    Registros que se intentaron guardar (en el mismo orden que resultList)
     * @param messagePrefix Texto que explica qué falló
     */
    private static void saveLogsForFailures( List<Database.SaveResult> resultList, List<SObject> recordList, String messagePrefix ) {
        List<Error_Log__c> errorLogList = new List<Error_Log__c>();
        for ( Integer i = 0; i < resultList.size(); i++ ) {
            if ( !resultList[i].isSuccess() ) {
                errorLogList.add( ErrorLogUtil.buildLog( CLASS_NAME, recordList[i].Id,
                    messagePrefix + resultList[i].getErrors()[0].getMessage() ) );
            }
        }
        ErrorLogUtil.saveLogs( errorLogList );
    }
}
