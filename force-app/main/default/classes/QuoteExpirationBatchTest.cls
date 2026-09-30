/**
 * @description Tests del DEV #1 (Parte B): QuoteExpirationBatch.
 *              Las aprobaciones pendientes son REALES: se hace Submit con Approval.process y
 *              el Approval Process del org (Quote_Approval_V2) corre también en el test.
 *              Con Payment Terms = Net 60 la Quote queda pendiente de Finance (In Review).
 *
 *              En un test, el Batch corre completo en Test.stopTest() y su execute() se
 *              ejecuta una sola vez (por eso el bulk usa 200 Quotes, el tamaño de una tanda).
 */
@IsTest
private class QuoteExpirationBatchTest {

    private static final Integer BULK_SIZE = 200;
    private static final String PAYMENT_TERMS_NEEDING_APPROVAL = 'Net 60';
    private static final Date YESTERDAY = Date.today().addDays( -1 );

    /**
     * @description Datos comunes: una Account, una Opportunity abierta y una ganada.
     */
    @testSetup
    static void setup() {
        Account acc = TestDataFactory.createAccount();
        TestDataFactory.createOpportunity( acc.Id, 'Prospecting' );
        TestDataFactory.createOpportunity( acc.Id, 'Closed Won' );
    }

    // ---------------------------------------------------------------------------------
    // Positivos: se hace recall
    // ---------------------------------------------------------------------------------

    /**
     * @description Positivo: Quote pendiente, vencida ayer, con la Opportunity abierta
     *              -> recall: vuelve a Draft y ya no tiene aprobación pendiente.
     */
    @isTest
    static void recallExpiredQuoteTest() {
        List<SBQQ__Quote__c> quoteList = insertPendingQuotes( getOpportunityId( false ), 1, YESTERDAY );

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        System.assertEquals( 'Draft', getStatus( quoteList[0].Id ),
            'La Quote vencida con la Opportunity abierta debería volver a Draft (Recall Action)' );
        System.assertEquals( 0, countPendingApprovals( quoteList ),
            'La Quote no debería tener aprobaciones pendientes después del recall' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c],
            'Un recall exitoso no debería generar Error Logs' );
    }

    /**
     * @description Borde: la Quote vence HOY. "Reaches the Expiration Date" = el mismo día
     *              (SBQQ__ExpirationDate__c <= TODAY) -> recall.
     */
    @isTest
    static void recallQuoteExpiringTodayTest() {
        List<SBQQ__Quote__c> quoteList = insertPendingQuotes( getOpportunityId( false ), 1, Date.today() );

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        System.assertEquals( 'Draft', getStatus( quoteList[0].Id ),
            'Una Quote que vence hoy ya alcanzó su vencimiento y debería recallearse' );
    }

    /**
     * @description Bulk: 200 Quotes pendientes y vencidas -> las 200 vuelven a Draft.
     */
    @isTest
    static void recallBulkTest() {
        List<SBQQ__Quote__c> quoteList = insertPendingQuotes( getOpportunityId( false ), BULK_SIZE, YESTERDAY );

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        Integer draftCount = [SELECT COUNT() FROM SBQQ__Quote__c WHERE SBQQ__Status__c = 'Draft'];
        System.assertEquals( BULK_SIZE, draftCount, 'Las 200 Quotes vencidas deberían volver a Draft' );
        System.assertEquals( 0, countPendingApprovals( quoteList ),
            'Ninguna de las 200 Quotes debería quedar con aprobaciones pendientes' );
    }

    // ---------------------------------------------------------------------------------
    // Negativos: no se toca la Quote
    // ---------------------------------------------------------------------------------

    /**
     * @description Negativo: la Quote vence mañana -> sigue pendiente.
     */
    @isTest
    static void notRecalledWhenNotExpiredTest() {
        List<SBQQ__Quote__c> quoteList = insertPendingQuotes( getOpportunityId( false ), 1, Date.today().addDays( 1 ) );

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        System.assertEquals( 'In Review', getStatus( quoteList[0].Id ),
            'Una Quote que todavía no venció no debería recallearse' );
        System.assertEquals( 1, countPendingApprovals( quoteList ),
            'La aprobación de una Quote no vencida debería seguir pendiente' );
    }

    /**
     * @description Negativo: la Opportunity ya está Closed Won -> no se hace recall.
     */
    @isTest
    static void notRecalledWhenOpportunityWonTest() {
        List<SBQQ__Quote__c> quoteList = insertPendingQuotes( getOpportunityId( true ), 1, YESTERDAY );

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        System.assertEquals( 'In Review', getStatus( quoteList[0].Id ),
            'Si la Opportunity ya está Closed Won, la Quote no debería recallearse' );
    }

    /**
     * @description Negativo (supuesto del mentor): una Quote ya aprobada y vencida no se toca.
     *              Se inserta aprobada (el trigger le pone hoy + 30) y después se le fuerza un
     *              vencimiento pasado; como el Status no cambia, el trigger no lo recalcula.
     */
    @isTest
    static void notRecalledWhenAlreadyApprovedTest() {
        List<SBQQ__Quote__c> quoteList = TestDataFactory.buildQuotes( getAccountId(), 1, 'Approved', YESTERDAY );
        quoteList[0].SBQQ__Opportunity2__c = getOpportunityId( false );
        insert quoteList;
        quoteList[0].SBQQ__ExpirationDate__c = YESTERDAY;
        update quoteList;

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        System.assertEquals( 'Approved', getStatus( quoteList[0].Id ),
            'Una Quote ya aprobada no debería tocarse, aunque esté vencida' );
    }

    /**
     * @description Negativo (supuesto documentado): una Quote sin Opportunity queda afuera.
     */
    @isTest
    static void notRecalledWithoutOpportunityTest() {
        List<SBQQ__Quote__c> quoteList = insertPendingQuotes( null, 1, YESTERDAY );

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        System.assertEquals( 'In Review', getStatus( quoteList[0].Id ),
            'Una Quote sin Opportunity no debería recallearse' );
    }

    /**
     * @description Borde: una Quote con Status "In Review" puesto a mano, sin aprobación
     *              pendiente. El Batch la encuentra pero no hay nada que recallear: no la toca
     *              y no genera errores.
     */
    @isTest
    static void notRecalledWithoutPendingApprovalTest() {
        List<SBQQ__Quote__c> quoteList = TestDataFactory.buildQuotes( getAccountId(), 1, 'In Review', YESTERDAY );
        quoteList[0].SBQQ__Opportunity2__c = getOpportunityId( false );
        insert quoteList;

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        System.assertEquals( 'In Review', getStatus( quoteList[0].Id ),
            'Sin aprobación pendiente no hay recall: la Quote no debería cambiar' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c],
            'Una Quote sin aprobación pendiente no debería generar Error Logs' );
    }

    // ---------------------------------------------------------------------------------
    // Métodos de ayuda
    // ---------------------------------------------------------------------------------

    private static Id getAccountId() {
        return [SELECT Id FROM Account LIMIT 1].Id;
    }

    /**
     * @param isWon true para la Opportunity Closed Won, false para la abierta
     * @return Id de la Opportunity pedida
     */
    private static Id getOpportunityId( Boolean isWon ) {
        return [SELECT Id FROM Opportunity WHERE IsWon = :isWon LIMIT 1].Id;
    }

    private static String getStatus( Id quoteId ) {
        return [SELECT SBQQ__Status__c FROM SBQQ__Quote__c WHERE Id = :quoteId].SBQQ__Status__c;
    }

    private static Integer countPendingApprovals( List<SBQQ__Quote__c> quoteList ) {
        return [SELECT COUNT() FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId IN :quoteList];
    }

    /**
     * @description Inserta Quotes y las envía a aprobación de verdad (Submit), así quedan
     *              In Review con una aprobación pendiente de Finance.
     * @param opportunityId  Opportunity de las Quotes (null = sin Opportunity)
     * @param numberOfQuotes Cantidad de Quotes
     * @param expirationDate Vencimiento de las Quotes
     * @return Quotes insertadas y enviadas a aprobación
     */
    private static List<SBQQ__Quote__c> insertPendingQuotes( Id opportunityId, Integer numberOfQuotes, Date expirationDate ) {
        List<SBQQ__Quote__c> quoteList = TestDataFactory.buildQuotes( getAccountId(), numberOfQuotes, 'Draft', expirationDate );
        for ( SBQQ__Quote__c quote : quoteList ) {
            quote.SBQQ__Opportunity2__c = opportunityId;
            quote.SBQQ__PaymentTerms__c = PAYMENT_TERMS_NEEDING_APPROVAL;
        }
        insert quoteList;

        List<Approval.ProcessSubmitRequest> submitRequestList = new List<Approval.ProcessSubmitRequest>();
        for ( SBQQ__Quote__c quote : quoteList ) {
            Approval.ProcessSubmitRequest submitRequest = new Approval.ProcessSubmitRequest();
            submitRequest.setObjectId( quote.Id );
            submitRequestList.add( submitRequest );
        }
        Approval.process( submitRequestList );
        return quoteList;
    }
}
