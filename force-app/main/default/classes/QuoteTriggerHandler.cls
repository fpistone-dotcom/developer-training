/**
 * @description Lógica del QuoteTrigger. Resuelve la Parte A del DEV #1: cuando una Quote
 *              se aprueba, su fecha de vencimiento pasa a ser 30 días desde la aprobación,
 *              pisando el vencimiento por defecto de CPQ (30 días desde la creación).
 *
 *              "Se aprueba" = el campo SBQQ__Status__c pasa a 'Approved'. Lo pone el field
 *              update Set_Quote_Status_Approved de los Approval Processes, pero también puede
 *              cambiarlo un usuario o una carga de datos: el trigger reacciona al CAMBIO DEL
 *              CAMPO, no importa quién lo haga.
 *
 *              Todo corre en before: modificamos un campo del mismo registro, así que alcanza
 *              con asignarlo en memoria (sin DML, sin SOQL y sin recursión).
 *
 *              Estructura: los métodos públicos (beforeInsert, beforeUpdate) son la entrada
 *              por contexto y solo llaman a métodos private static que tienen la lógica.
 *
 * Requirement DEV #1 (textual, primera parte): "Whenever a Quote record is approved, the
 * Quote Expiration Date should be set to 30 days from the date in which it was approved."
 * Partes del requirement y dónde se cubren:
 *   (A) "whenever a Quote record is approved"   -> beforeUpdate (Status cambia a Approved)
 *                                                 y beforeInsert (Quote creada ya aprobada)
 *   (B) "Quote Expiration Date ... 30 days from -> setExpirationDate
 *        the date in which it was approved"
 */
public with sharing class QuoteTriggerHandler {

    public static final String STATUS_APPROVED = 'Approved';

    // Req (B): días de vigencia desde la aprobación
    public static final Integer DAYS_UNTIL_EXPIRATION = 30;

    // ---------------------------------------------------------------------------------
    // Métodos de entrada: uno por contexto de trigger. Solo llaman a la lógica.
    // ---------------------------------------------------------------------------------

    /**
     * @description Entrada del before insert. Req (A): la Quote se crea ya aprobada.
     * @param newQuoteList Trigger.new
     */
    public static void beforeInsert( List<SBQQ__Quote__c> newQuoteList ) {
        setExpirationDateOnInsert( newQuoteList );
    }

    /**
     * @description Entrada del before update. Req (A): el Status pasa a Approved.
     * @param newQuoteList    Trigger.new (los registros con los valores nuevos)
     * @param oldQuoteByIdMap Trigger.oldMap (los registros con los valores de antes)
     */
    public static void beforeUpdate( List<SBQQ__Quote__c> newQuoteList, Map<Id, SBQQ__Quote__c> oldQuoteByIdMap ) {
        setExpirationDateOnUpdate( newQuoteList, oldQuoteByIdMap );
    }

    // ---------------------------------------------------------------------------------
    // Lógica (private static)
    // ---------------------------------------------------------------------------------

    /**
     * @description Req (A). En el insert no hay valor anterior: alcanza con que la Quote
     *              se cree con Status = Approved.
     * @param newQuoteList Trigger.new
     */
    private static void setExpirationDateOnInsert( List<SBQQ__Quote__c> newQuoteList ) {
        List<SBQQ__Quote__c> approvedQuoteList = new List<SBQQ__Quote__c>();
        for ( SBQQ__Quote__c newQuote : newQuoteList ) {
            if ( newQuote.SBQQ__Status__c == STATUS_APPROVED ) {
                approvedQuoteList.add( newQuote );
            }
        }
        setExpirationDate( approvedQuoteList );
    }

    /**
     * @description Req (A). Solo procesa las Quotes cuyo Status CAMBIÓ a Approved.
     *              Si la Quote ya estaba aprobada y se edita otro campo, no se vuelve a
     *              calcular el vencimiento (la fecha de aprobación no cambió).
     * @param newQuoteList    Trigger.new
     * @param oldQuoteByIdMap Trigger.oldMap
     */
    private static void setExpirationDateOnUpdate( List<SBQQ__Quote__c> newQuoteList, Map<Id, SBQQ__Quote__c> oldQuoteByIdMap ) {
        List<SBQQ__Quote__c> approvedQuoteList = new List<SBQQ__Quote__c>();
        for ( SBQQ__Quote__c newQuote : newQuoteList ) {
            SBQQ__Quote__c oldQuote = oldQuoteByIdMap.get( newQuote.Id );
            // "Se aprueba" significa que el valor CAMBIÓ a Approved en esta transacción
            Boolean statusChanged = newQuote.SBQQ__Status__c != oldQuote.SBQQ__Status__c;
            if ( statusChanged && newQuote.SBQQ__Status__c == STATUS_APPROVED ) {
                approvedQuoteList.add( newQuote );
            }
        }
        setExpirationDate( approvedQuoteList );
    }

    /**
     * @description Req (B). La regla en un solo lugar: vencimiento = hoy + 30 días.
     *              "Hoy" es el día de la aprobación, porque este código corre en la misma
     *              transacción que aprueba la Quote. La fecha se calcula una sola vez,
     *              afuera del loop. Estamos en before: no hace falta DML.
     * @param approvedQuoteList Quotes recién aprobadas
     */
    private static void setExpirationDate( List<SBQQ__Quote__c> approvedQuoteList ) {
        if ( approvedQuoteList.isEmpty() ) {
            return;
        }
        Date expirationDate = Date.today().addDays( DAYS_UNTIL_EXPIRATION );
        for ( SBQQ__Quote__c approvedQuote : approvedQuoteList ) {
            approvedQuote.SBQQ__ExpirationDate__c = expirationDate;
        }
    }
}
