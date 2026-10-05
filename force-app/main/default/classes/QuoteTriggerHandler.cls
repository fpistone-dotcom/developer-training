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
 *              DEV #1 corre en before: modificamos un campo del mismo registro, así que alcanza
 *              con asignarlo en memoria (sin DML, sin SOQL y sin recursión).
 *
 *              También resuelve la Parte 3 del DEV #3 (after insert): el email al Owner de una
 *              Renewal Quote nueva.
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
 *
 * Requirement DEV #3 (textual, tercera parte): "When this happens, the Owner of the Quote should
 * have an email notification sent to them indicating that a Renewal Quote has been created, and
 * the email should include a link to the Quote."
 * Partes del requirement y dónde se cubren:
 *   (F) "a Renewal Quote has been created"         -> afterInsert, Quotes con SBQQ__Type__c = 'Renewal'
 *   (G) "the Owner of the Quote ... email ... link" -> sendRenewalQuoteNotifications
 */
public with sharing class QuoteTriggerHandler {

    public static final String STATUS_APPROVED = 'Approved';

    // Req (B): días de vigencia desde la aprobación
    public static final Integer DAYS_UNTIL_EXPIRATION = 30;

    // Req (F): tipo con el que CPQ crea las Renewal Quotes (verificado en el org, Q-00085)
    public static final String TYPE_RENEWAL = 'Renewal';

    private static final String CLASS_NAME = 'QuoteTriggerHandler';

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

    /**
     * @description Entrada del after insert. Req (F): nace una Renewal Quote. En after porque
     *              el link del email necesita el Id de la Quote.
     * @param newQuoteList Trigger.new
     */
    public static void afterInsert( List<SBQQ__Quote__c> newQuoteList ) {
        sendRenewalQuoteNotifications( newQuoteList );
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

    /**
     * @description Req (F) y (G). Manda un email al Owner de cada Renewal Quote nueva, con un
     *              link a la Quote. Avisa por cualquier Renewal Quote, la genere el Batch del
     *              DEV #3 o un usuario a mano (supuesto confirmado).
     *
     *              - Destinatario: setTargetObjectId( OwnerId ). Los emails a usuarios internos
     *                no cuentan para el límite diario de emails del org (15 en Developer Edition).
     *              - Un solo Messaging.sendEmail para todas las Quotes (nunca dentro del loop:
     *                el límite es de 10 envíos por transacción).
     *              - try/catch: este código corre DENTRO del save en el que CPQ crea la Quote.
     *                Una excepción sin atrapar haría rollback de la Renewal Quote. El error queda
     *                en Error_Log__c (no falla en silencio).
     * @param newQuoteList Trigger.new
     */
    private static void sendRenewalQuoteNotifications( List<SBQQ__Quote__c> newQuoteList ) {
        Set<Id> renewalQuoteIdSet = new Set<Id>();
        for ( SBQQ__Quote__c newQuote : newQuoteList ) {
            if ( newQuote.SBQQ__Type__c == TYPE_RENEWAL ) {
                renewalQuoteIdSet.add( newQuote.Id );
            }
        }
        // Condicional antes de la SOQL: la mayoría de las Quotes no son Renewal
        if ( renewalQuoteIdSet.isEmpty() ) {
            return;
        }

        // El link abre el registro en Lightning: https://<dominio del org>/<Id de la Quote>
        String orgUrl = URL.getOrgDomainUrl().toExternalForm();

        // Query para traer los nombres del Account y de la Opportunity (no vienen en Trigger.new)
        List<SBQQ__Quote__c> renewalQuoteList = [
            SELECT Id, Name, OwnerId, SBQQ__Account__r.Name, SBQQ__Opportunity2__r.Name
            FROM SBQQ__Quote__c
            WHERE Id IN :renewalQuoteIdSet
        ];

        List<Messaging.SingleEmailMessage> emailList = new List<Messaging.SingleEmailMessage>();
        for ( SBQQ__Quote__c renewalQuote : renewalQuoteList ) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId( renewalQuote.OwnerId );
            // Con un User como destinatario, Salesforce exige no guardarlo como Activity
            email.setSaveAsActivity( false );
            email.setSubject( 'Renewal Quote created: ' + renewalQuote.Name );
            email.setPlainTextBody( buildEmailBody( renewalQuote, orgUrl ) );
            emailList.add( email );
        }

        List<Error_Log__c> errorLogList = new List<Error_Log__c>();
        try {
            List<Messaging.SendEmailResult> resultList = Messaging.sendEmail( emailList, false );
            // Los resultados vuelven en el mismo orden que los emails: se recorren por posición
            for ( Integer i = 0; i < resultList.size(); i++ ) {
                if ( !resultList[i].isSuccess() ) {
                    errorLogList.add( ErrorLogUtil.buildLog( CLASS_NAME, renewalQuoteList[i].Id,
                        'Renewal Quote email failed: ' + resultList[i].getErrors()[0].getMessage() ) );
                }
            }
        } catch ( Exception e ) {
            // Por ejemplo, si el org tiene el envío de emails desactivado (Deliverability)
            for ( SBQQ__Quote__c renewalQuote : renewalQuoteList ) {
                errorLogList.add( ErrorLogUtil.buildLog( CLASS_NAME, renewalQuote.Id,
                    'Renewal Quote email failed: ' + e.getMessage() ) );
            }
        }
        ErrorLogUtil.saveLogs( errorLogList );
    }

    /**
     * @description Req (G). Arma el texto del email: qué se creó, para qué Account y el link.
     * @param renewalQuote Renewal Quote (con Account y Opportunity consultados)
     * @param orgUrl       Dominio del org, por ejemplo https://firstchair-dev-ed.develop.my.salesforce.com
     * @return Cuerpo del email en texto plano
     */
    private static String buildEmailBody( SBQQ__Quote__c renewalQuote, String orgUrl ) {
        String body = 'Hello,\n\n'
            + 'A Renewal Quote has been created and you are its Owner. '
            + 'Your team can start preparing for the renewal sale.\n\n'
            + 'Quote: ' + renewalQuote.Name + '\n'
            + 'Account: ' + renewalQuote.SBQQ__Account__r.Name + '\n'
            + 'Renewal Opportunity: ' + renewalQuote.SBQQ__Opportunity2__r.Name + '\n\n'
            + 'Open the Quote: ' + orgUrl + '/' + renewalQuote.Id + '\n\n'
            + 'This is an automatic notification from Salesforce.';
        return body;
    }
}
