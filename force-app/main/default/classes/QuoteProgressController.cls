/**
 * @description Controller del LWC quoteProgress (DEV #5). Calcula los 5 pasos del proceso de
 *              cotización de UNA Quote y los devuelve en orden, cada uno con su estado
 *              (completado o no). El LWC solo los dibuja: toda la regla de negocio vive acá,
 *              en Apex, para poder testearla y para cambiarla en un solo lugar.
 *
 *              Eficiencia: 1 sola SOQL y 0 DML por llamada. Cada llamada desde el LWC es una
 *              transacción nueva con sus propios governor limits.
 *
 * Requirement DEV #5 (textual): "As a Sales User, I would like to be able to see a User-friendly
 * UI on the Quote record that shows my current progress in the Quoting process. Specifically, I
 * would like the following tasks to either have a green checkmark or red 'X': Quote Lines Added,
 * Quote Approved, Quote Document Created, Opportunity Closed Won, Quote Ordered."
 * Partes del requirement y dónde se cubren:
 *   (A) "Quote Lines Added"        -> SBQQ__LineItemCount__c > 0 (Roll-Up Summary de CPQ)
 *   (B) "Quote Approved"           -> SBQQ__Status__c en APPROVED_STATUS_SET
 *   (C) "Quote Document Created"   -> existe al menos un SBQQ__QuoteDocument__c de esta Quote
 *   (D) "Opportunity Closed Won"   -> SBQQ__Opportunity2__r.IsWon = true
 *   (E) "Quote Ordered"            -> SBQQ__Ordered__c = true
 *   (F) "green checkmark or red X" -> isDone de cada paso; el LWC elige el ícono
 */
public with sharing class QuoteProgressController {

    // Textos de cada paso, tal cual el requirement. Públicos para usarlos en los tests.
    public static final String STEP_QUOTE_LINES = 'Quote Lines Added';
    public static final String STEP_APPROVED = 'Quote Approved';
    public static final String STEP_DOCUMENT = 'Quote Document Created';
    public static final String STEP_CLOSED_WON = 'Opportunity Closed Won';
    public static final String STEP_ORDERED = 'Quote Ordered';

    // Req (B): Presented y Accepted son estados POSTERIORES a la aprobación en el ciclo de CPQ.
    // Si una Quote aprobada pasa a Presented, el paso tiene que seguir en verde (supuesto
    // confirmado por Francisco). Set y no List: solo preguntamos "¿está adentro?" (contains).
    public static final Set<String> APPROVED_STATUS_SET = new Set<String>{ 'Approved', 'Presented', 'Accepted' };

    public static final String QUOTE_NOT_FOUND_MESSAGE = 'The Quote was not found or you do not have access to it.';

    /**
     * @description Un paso de la barra de progreso. Clase mínima de 2 campos: es la forma de
     *              mandarle al navegador datos con estructura. @AuraEnabled en cada campo hace
     *              que viaje en el JSON que recibe el LWC.
     */
    public class ProgressStep {
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isDone;

        public ProgressStep( String label, Boolean isDone ) {
            this.label = label;
            this.isDone = isDone;
        }
    }

    /**
     * @description Devuelve los 5 pasos de la Quote, en el orden del requirement.
     *              @AuraEnabled: permite llamarlo desde el LWC. Sin cacheable=true a propósito:
     *              así cada llamada (al abrir la página o con el botón Refresh) trae datos frescos.
     * @param quoteId Id de la Quote que se está mirando (el recordId de la página)
     * @return Lista ordenada de 5 ProgressStep
     */
    @AuraEnabled
    public static List<ProgressStep> getProgressSteps( Id quoteId ) {
        // Una sola query: los campos de la Quote, el IsWon del padre (lookup) y los documentos
        // hijos (subquery). SBQQ__R00N70000001lX7YEAU__r es el nombre de la relación
        // SBQQ__QuoteDocument__c -> SBQQ__Quote__c: CPQ es un paquete viejo y nunca le puso un
        // nombre legible (verificado con sf sobject describe). LIMIT 1 porque solo importa si
        // existe al menos uno, no cuántos.
        List<SBQQ__Quote__c> quoteList = [
            SELECT Id, SBQQ__LineItemCount__c, SBQQ__Status__c, SBQQ__Ordered__c,
                SBQQ__Opportunity2__c, SBQQ__Opportunity2__r.IsWon,
                ( SELECT Id FROM SBQQ__R00N70000001lX7YEAU__r LIMIT 1 )
            FROM SBQQ__Quote__c
            WHERE Id = :quoteId
        ];

        // La Quote no existe (borrada) o el usuario no la ve (with sharing): error legible.
        if ( quoteList.isEmpty() ) {
            AuraHandledException notFoundException = new AuraHandledException( QUOTE_NOT_FOUND_MESSAGE );
            // setMessage: sin esto, getMessage() devuelve "Script-thrown exception" y el test no
            // puede verificar el texto. El navegador recibe el mensaje del constructor igual.
            notFoundException.setMessage( QUOTE_NOT_FOUND_MESSAGE );
            throw notFoundException;
        }

        return buildSteps( quoteList[0] );
    }

    /**
     * @description Evalúa cada paso por separado. Los pasos NO son secuenciales: por ejemplo,
     *              una Amendment está Ordered sin estar aprobada ni Closed Won (visto en el org).
     * @param quote Quote con los campos de la query
     * @return Lista ordenada de 5 ProgressStep
     */
    private static List<ProgressStep> buildSteps( SBQQ__Quote__c quote ) {
        // Req (A): un Roll-Up Summary nunca es null (vale 0 sin líneas)
        Boolean hasQuoteLines = quote.SBQQ__LineItemCount__c > 0;

        // Req (B)
        Boolean isApproved = APPROVED_STATUS_SET.contains( quote.SBQQ__Status__c );

        // Req (C): el resultado de una subquery nunca es null (sin hijos es una lista vacía)
        Boolean hasDocument = !quote.SBQQ__R00N70000001lX7YEAU__r.isEmpty();

        // Req (D): primero se mira el lookup. Sin Opportunity, SBQQ__Opportunity2__r es null y
        // leer su IsWon tiraría NullPointerException.
        Boolean isClosedWon = false;
        if ( quote.SBQQ__Opportunity2__c != null ) {
            isClosedWon = quote.SBQQ__Opportunity2__r.IsWon;
        }

        // Req (E)
        Boolean isOrdered = quote.SBQQ__Ordered__c;

        List<ProgressStep> stepList = new List<ProgressStep>();
        stepList.add( new ProgressStep( STEP_QUOTE_LINES, hasQuoteLines ) );
        stepList.add( new ProgressStep( STEP_APPROVED, isApproved ) );
        stepList.add( new ProgressStep( STEP_DOCUMENT, hasDocument ) );
        stepList.add( new ProgressStep( STEP_CLOSED_WON, isClosedWon ) );
        stepList.add( new ProgressStep( STEP_ORDERED, isOrdered ) );
        return stepList;
    }
}
