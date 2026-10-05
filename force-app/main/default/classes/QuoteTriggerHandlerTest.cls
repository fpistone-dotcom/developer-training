/**
 * @description Tests del DEV #1 (Parte A): QuoteTrigger y QuoteTriggerHandler.
 *              Cubre casos positivos, negativos y bulk (200 registros) de los dos caminos:
 *              - Update: el Status pasa a Approved (es lo que hace el Approval Process).
 *              - Insert: la Quote se crea ya aprobada.
 *
 *              Todas las Quotes nacen con un vencimiento "original" de hoy + 5, distinto del
 *              que pone nuestro trigger (hoy + 30). Así se ve si el trigger lo pisó o no:
 *              el default de CPQ (30 días desde la creación) coincide con hoy + 30 y no
 *              serviría para distinguirlo.
 *
 *              En un test no se puede correr el Approval Process real: se cambia el Status
 *              a mano, que es exactamente lo que hace su field update Set_Quote_Status_Approved.
 */
@IsTest
private class QuoteTriggerHandlerTest {

    private static final Integer BULK_SIZE = 200;
    private static final Date ORIGINAL_EXPIRATION_DATE = Date.today().addDays( 5 );
    private static final Date EXPECTED_EXPIRATION_DATE = Date.today().addDays( QuoteTriggerHandler.DAYS_UNTIL_EXPIRATION );

    /**
     * @description Datos comunes para todos los tests: una Account.
     */
    @testSetup
    static void setup() {
        TestDataFactory.createAccount();
    }

    // ---------------------------------------------------------------------------------
    // Camino UPDATE
    // ---------------------------------------------------------------------------------

    /**
     * @description Positivo: una Quote en Draft que pasa a Approved vence en hoy + 30.
     */
    @isTest
    static void setExpirationOnApproveTest() {
        List<SBQQ__Quote__c> quoteList = insertQuotes( 1, 'Draft' );

        Test.startTest();
        quoteList[0].SBQQ__Status__c = 'Approved';
        update quoteList;
        Test.stopTest();

        SBQQ__Quote__c result = getQuote( quoteList[0].Id );
        System.assertEquals( EXPECTED_EXPIRATION_DATE, result.SBQQ__ExpirationDate__c,
            'Al aprobarse, la Quote debería vencer en hoy + 30 días' );
    }

    /**
     * @description Bulk: 200 Quotes aprobadas juntas vencen todas en hoy + 30.
     */
    @isTest
    static void setExpirationOnApproveBulkTest() {
        List<SBQQ__Quote__c> quoteList = insertQuotes( BULK_SIZE, 'Draft' );

        Test.startTest();
        for ( SBQQ__Quote__c quote : quoteList ) {
            quote.SBQQ__Status__c = 'Approved';
        }
        update quoteList;
        Test.stopTest();

        Integer updatedCount = [
            SELECT COUNT()
            FROM SBQQ__Quote__c
            WHERE SBQQ__ExpirationDate__c = :EXPECTED_EXPIRATION_DATE
        ];
        System.assertEquals( BULK_SIZE, updatedCount, 'Las 200 Quotes aprobadas deberían vencer en hoy + 30 días' );
    }

    /**
     * @description Negativo: si el Status pasa a otro valor (In Review), el vencimiento no cambia.
     */
    @isTest
    static void notSetOnOtherStatusTest() {
        List<SBQQ__Quote__c> quoteList = insertQuotes( 1, 'Draft' );

        Test.startTest();
        quoteList[0].SBQQ__Status__c = 'In Review';
        update quoteList;
        Test.stopTest();

        SBQQ__Quote__c result = getQuote( quoteList[0].Id );
        System.assertEquals( ORIGINAL_EXPIRATION_DATE, result.SBQQ__ExpirationDate__c,
            'Si la Quote no se aprueba, el vencimiento no debería cambiar' );
    }

    /**
     * @description Negativo: si la Quote ya estaba aprobada y se edita otra cosa (acá, el
     *              propio vencimiento), el trigger no lo vuelve a calcular.
     */
    @isTest
    static void notRecalculatedWhenAlreadyApprovedTest() {
        List<SBQQ__Quote__c> quoteList = insertQuotes( 1, 'Approved' );
        Date manualExpirationDate = Date.today().addDays( 10 );

        Test.startTest();
        quoteList[0].SBQQ__ExpirationDate__c = manualExpirationDate;
        update quoteList;
        Test.stopTest();

        SBQQ__Quote__c result = getQuote( quoteList[0].Id );
        System.assertEquals( manualExpirationDate, result.SBQQ__ExpirationDate__c,
            'Si el Status no cambió, el vencimiento no debería recalcularse' );
    }

    /**
     * @description Positivo: una Quote que vuelve a Draft (por ejemplo, después de un recall)
     *              y se aprueba de nuevo recalcula el vencimiento desde la nueva aprobación.
     */
    @isTest
    static void recalculatedOnReapprovalTest() {
        List<SBQQ__Quote__c> quoteList = insertQuotes( 1, 'Approved' );
        quoteList[0].SBQQ__Status__c = 'Draft';
        quoteList[0].SBQQ__ExpirationDate__c = ORIGINAL_EXPIRATION_DATE;
        update quoteList;

        Test.startTest();
        quoteList[0].SBQQ__Status__c = 'Approved';
        update quoteList;
        Test.stopTest();

        SBQQ__Quote__c result = getQuote( quoteList[0].Id );
        System.assertEquals( EXPECTED_EXPIRATION_DATE, result.SBQQ__ExpirationDate__c,
            'Al volver a aprobarse, la Quote debería vencer en hoy + 30 días' );
    }

    // ---------------------------------------------------------------------------------
    // Camino INSERT
    // ---------------------------------------------------------------------------------

    /**
     * @description Positivo: una Quote que se crea ya aprobada vence en hoy + 30.
     */
    @isTest
    static void setExpirationOnInsertApprovedTest() {
        Test.startTest();
        List<SBQQ__Quote__c> quoteList = insertQuotes( 1, 'Approved' );
        Test.stopTest();

        SBQQ__Quote__c result = getQuote( quoteList[0].Id );
        System.assertEquals( EXPECTED_EXPIRATION_DATE, result.SBQQ__ExpirationDate__c,
            'Una Quote creada ya aprobada debería vencer en hoy + 30 días' );
    }

    /**
     * @description Bulk: 200 Quotes creadas ya aprobadas vencen todas en hoy + 30.
     */
    @isTest
    static void setExpirationOnInsertApprovedBulkTest() {
        Test.startTest();
        insertQuotes( BULK_SIZE, 'Approved' );
        Test.stopTest();

        Integer updatedCount = [
            SELECT COUNT()
            FROM SBQQ__Quote__c
            WHERE SBQQ__ExpirationDate__c = :EXPECTED_EXPIRATION_DATE
        ];
        System.assertEquals( BULK_SIZE, updatedCount, 'Las 200 Quotes creadas aprobadas deberían vencer en hoy + 30 días' );
    }

    /**
     * @description Negativo: una Quote que se crea en Draft conserva su vencimiento.
     */
    @isTest
    static void notSetOnInsertNotApprovedTest() {
        Test.startTest();
        List<SBQQ__Quote__c> quoteList = insertQuotes( 1, 'Draft' );
        Test.stopTest();

        SBQQ__Quote__c result = getQuote( quoteList[0].Id );
        System.assertEquals( ORIGINAL_EXPIRATION_DATE, result.SBQQ__ExpirationDate__c,
            'Una Quote creada en Draft no debería cambiar su vencimiento' );
    }

    // ---------------------------------------------------------------------------------
    // DEV #3 (Parte 3): email al Owner de una Renewal Quote nueva
    //
    // En un test los emails no se envían de verdad, pero Salesforce cuenta las llamadas a
    // Messaging.sendEmail. Limits.getEmailInvocations() se lee ANTES de Test.stopTest(),
    // porque mide la transacción que está entre startTest y stopTest.
    // ---------------------------------------------------------------------------------

    /**
     * @description Positivo: al crear una Renewal Quote se manda el email, sin errores.
     */
    @isTest
    static void renewalQuoteSendsEmailTest() {
        Test.startTest();
        insertRenewalQuotes( 1 );
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals( 1, emailInvocations, 'Una Renewal Quote nueva debería disparar un envío de email' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'El envío no debería generar errores' );
    }

    /**
     * @description Bulk: 200 Renewal Quotes creadas juntas usan UN solo envío (con 200 emails),
     *              no 200 (el límite es 10 envíos por transacción).
     */
    @isTest
    static void renewalQuoteBulkEmailTest() {
        Test.startTest();
        insertRenewalQuotes( BULK_SIZE );
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals( 1, emailInvocations, 'Las 200 Renewal Quotes deberían enviarse en una sola llamada' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'El envío no debería generar errores' );
    }

    /**
     * @description Negativo: una Quote que no es Renewal no manda email.
     */
    @isTest
    static void nonRenewalQuoteNoEmailTest() {
        Test.startTest();
        insertQuotes( 1, 'Draft' );
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals( 0, emailInvocations, 'Una Quote que no es Renewal no debería mandar email' );
    }

    // ---------------------------------------------------------------------------------
    // Métodos de ayuda
    // ---------------------------------------------------------------------------------

    private static Id getAccountId() {
        return [SELECT Id FROM Account LIMIT 1].Id;
    }

    private static SBQQ__Quote__c getQuote( Id quoteId ) {
        return [SELECT SBQQ__ExpirationDate__c FROM SBQQ__Quote__c WHERE Id = :quoteId];
    }

    /**
     * @description Inserta Quotes con el Status indicado y el vencimiento original (hoy + 5).
     * @param numberOfQuotes Cantidad de Quotes
     * @param status         Valor de SBQQ__Status__c
     * @return Quotes insertadas
     */
    private static List<SBQQ__Quote__c> insertQuotes( Integer numberOfQuotes, String status ) {
        List<SBQQ__Quote__c> quoteList = TestDataFactory.buildQuotes( getAccountId(), numberOfQuotes, status, ORIGINAL_EXPIRATION_DATE );
        insert quoteList;
        return quoteList;
    }

    /**
     * @description Inserta Quotes de tipo Renewal (como las que genera CPQ), con Owner = el
     *              usuario que corre el test.
     * @param numberOfQuotes Cantidad de Quotes
     * @return Quotes insertadas
     */
    private static List<SBQQ__Quote__c> insertRenewalQuotes( Integer numberOfQuotes ) {
        List<SBQQ__Quote__c> quoteList = TestDataFactory.buildQuotes( getAccountId(), numberOfQuotes, 'Draft', ORIGINAL_EXPIRATION_DATE );
        for ( SBQQ__Quote__c quote : quoteList ) {
            quote.SBQQ__Type__c = QuoteTriggerHandler.TYPE_RENEWAL;
        }
        insert quoteList;
        return quoteList;
    }
}
