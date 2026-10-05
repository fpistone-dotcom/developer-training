/**
 * @description Tests del DEV #5: QuoteProgressController (el controller del LWC quoteProgress).
 *              Cubre casos positivos, negativos y borde de cada uno de los 5 pasos, el orden y
 *              los textos de los pasos, la eficiencia (1 sola query) y la Quote no encontrada.
 *
 *              Sin test bulk de 200: el método recibe UNA Quote (una página muestra una sola).
 *              En su lugar, singleQueryTest verifica que use 1 sola SOQL.
 *
 *              El LWC no tiene tests propios (Jest no está en el training ni cuenta para la
 *              cobertura de Apex): se prueba en el org.
 */
@IsTest
private class QuoteProgressControllerTest {

    // Posición de cada paso en la lista que devuelve el controller
    private static final Integer QUOTE_LINES_INDEX = 0;
    private static final Integer APPROVED_INDEX = 1;
    private static final Integer DOCUMENT_INDEX = 2;
    private static final Integer CLOSED_WON_INDEX = 3;
    private static final Integer ORDERED_INDEX = 4;

    private static final Integer NUMBER_OF_STEPS = 5;
    private static final String STAGE_OPEN = 'Prospecting';
    private static final String STAGE_CLOSED_WON = 'Closed Won';

    /**
     * @description Datos comunes: una Account, una Opportunity abierta y un producto.
     */
    @testSetup
    static void setup() {
        Account acc = TestDataFactory.createAccount();
        TestDataFactory.createOpportunity( acc.Id, STAGE_OPEN );
        TestDataFactory.createProduct();
    }

    // ---------------------------------------------------------------------------------
    // Todos los pasos
    // ---------------------------------------------------------------------------------

    /**
     * @description Negativo: una Quote recién creada (Draft, sin líneas, sin documento,
     *              Opportunity abierta, no Ordered) tiene los 5 pasos en rojo.
     */
    @isTest
    static void newQuoteAllStepsPendingTest() {
        SBQQ__Quote__c quote = insertQuote( getOpenOpportunityId(), 'Draft' );

        Test.startTest();
        List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quote.Id );
        Test.stopTest();

        System.assertEquals( NUMBER_OF_STEPS, stepList.size(), 'Siempre se devuelven los 5 pasos' );
        for ( QuoteProgressController.ProgressStep step : stepList ) {
            System.assertEquals( false, step.isDone, 'En una Quote nueva el paso "' + step.label + '" debería estar en rojo' );
        }
    }

    /**
     * @description Positivo: Quote con líneas, aprobada, con documento, Opportunity Closed Won
     *              y Ordered tiene los 5 pasos en verde.
     */
    @isTest
    static void allStepsCompletedTest() {
        Opportunity wonOpportunity = TestDataFactory.createOpportunity( getAccountId(), STAGE_CLOSED_WON );
        SBQQ__Quote__c quote = insertQuote( wonOpportunity.Id, 'Approved' );
        insert TestDataFactory.buildQuoteLines( quote.Id, getProductId(), 1 );
        insert TestDataFactory.buildQuoteDocument( quote.Id, wonOpportunity.Id );
        // Solo para armar el dato: al tildar Ordered, CPQ intenta crear la Order real (exige
        // Primary, Pricebook, PricebookEntry...) y dispara toda la cadena del Req #31, que no es
        // parte del DEV #5 (se probó en el org en el DEV #2). Apagamos los triggers de CPQ solo
        // durante este update y los volvemos a prender: el controller corre con CPQ prendido.
        SBQQ.TriggerControl.disable();
        quote.SBQQ__Ordered__c = true;
        update quote;
        SBQQ.TriggerControl.enable();

        Test.startTest();
        List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quote.Id );
        Test.stopTest();

        for ( QuoteProgressController.ProgressStep step : stepList ) {
            System.assertEquals( true, step.isDone, 'Con todo completo, el paso "' + step.label + '" debería estar en verde' );
        }
    }

    /**
     * @description Positivo: los pasos vienen en el orden del requirement y con sus textos.
     */
    @isTest
    static void stepsOrderAndLabelsTest() {
        SBQQ__Quote__c quote = insertQuote( getOpenOpportunityId(), 'Draft' );

        Test.startTest();
        List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quote.Id );
        Test.stopTest();

        System.assertEquals( QuoteProgressController.STEP_QUOTE_LINES, stepList[QUOTE_LINES_INDEX].label, 'El paso 1 debería ser Quote Lines Added' );
        System.assertEquals( QuoteProgressController.STEP_APPROVED, stepList[APPROVED_INDEX].label, 'El paso 2 debería ser Quote Approved' );
        System.assertEquals( QuoteProgressController.STEP_DOCUMENT, stepList[DOCUMENT_INDEX].label, 'El paso 3 debería ser Quote Document Created' );
        System.assertEquals( QuoteProgressController.STEP_CLOSED_WON, stepList[CLOSED_WON_INDEX].label, 'El paso 4 debería ser Opportunity Closed Won' );
        System.assertEquals( QuoteProgressController.STEP_ORDERED, stepList[ORDERED_INDEX].label, 'El paso 5 debería ser Quote Ordered' );
    }

    // ---------------------------------------------------------------------------------
    // Un paso por vez (los pasos son independientes)
    // ---------------------------------------------------------------------------------

    /**
     * @description Borde: una Quote con líneas pero nada más tiene SOLO el paso 1 en verde.
     */
    @isTest
    static void quoteLinesAddedTest() {
        SBQQ__Quote__c quote = insertQuote( getOpenOpportunityId(), 'Draft' );
        insert TestDataFactory.buildQuoteLines( quote.Id, getProductId(), 2 );

        Test.startTest();
        List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quote.Id );
        Test.stopTest();

        assertOnlyStepDone( stepList, QUOTE_LINES_INDEX );
    }

    /**
     * @description Borde: una Quote con documento pero nada más tiene SOLO el paso 3 en verde.
     */
    @isTest
    static void quoteDocumentCreatedTest() {
        Id opportunityId = getOpenOpportunityId();
        SBQQ__Quote__c quote = insertQuote( opportunityId, 'Draft' );
        insert TestDataFactory.buildQuoteDocument( quote.Id, opportunityId );

        Test.startTest();
        List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quote.Id );
        Test.stopTest();

        assertOnlyStepDone( stepList, DOCUMENT_INDEX );
    }

    /**
     * @description Negativo: el documento de OTRA Quote de la misma Opportunity no cuenta.
     *              Por eso se filtra por SBQQ__Quote__c y no por SBQQ__Opportunity__c.
     */
    @isTest
    static void documentOfOtherQuoteNotCountedTest() {
        Id opportunityId = getOpenOpportunityId();
        SBQQ__Quote__c quote = insertQuote( opportunityId, 'Draft' );
        SBQQ__Quote__c otherQuote = insertQuote( opportunityId, 'Draft' );
        insert TestDataFactory.buildQuoteDocument( otherQuote.Id, opportunityId );

        Test.startTest();
        List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quote.Id );
        Test.stopTest();

        System.assertEquals( false, stepList[DOCUMENT_INDEX].isDone,
            'El documento de otra Quote de la misma Opportunity no debería contar' );
    }

    /**
     * @description Borde: una Quote de una Opportunity Closed Won (y nada más) tiene SOLO el
     *              paso 4 en verde.
     */
    @isTest
    static void opportunityClosedWonTest() {
        Opportunity wonOpportunity = TestDataFactory.createOpportunity( getAccountId(), STAGE_CLOSED_WON );
        SBQQ__Quote__c quote = insertQuote( wonOpportunity.Id, 'Draft' );

        Test.startTest();
        List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quote.Id );
        Test.stopTest();

        assertOnlyStepDone( stepList, CLOSED_WON_INDEX );
    }

    /**
     * @description Borde: una Quote sin Opportunity no rompe (sin NullPointerException) y el
     *              paso 4 queda en rojo.
     */
    @isTest
    static void quoteWithoutOpportunityTest() {
        SBQQ__Quote__c quote = insertQuote( null, 'Draft' );

        Test.startTest();
        List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quote.Id );
        Test.stopTest();

        System.assertEquals( false, stepList[CLOSED_WON_INDEX].isDone,
            'Sin Opportunity, el paso Opportunity Closed Won debería estar en rojo' );
    }

    // ---------------------------------------------------------------------------------
    // Paso 2: qué Status cuentan como aprobada
    // ---------------------------------------------------------------------------------

    /**
     * @description Positivo: Approved, Presented y Accepted cuentan como aprobada
     *              (Presented y Accepted son estados posteriores a la aprobación).
     */
    @isTest
    static void approvedStatusesTest() {
        List<String> statusList = new List<String>{ 'Approved', 'Presented', 'Accepted' };
        Map<String, Id> quoteIdByStatusMap = insertQuotesByStatus( statusList );

        Test.startTest();
        for ( String status : statusList ) {
            List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quoteIdByStatusMap.get( status ) );
            System.assertEquals( true, stepList[APPROVED_INDEX].isDone,
                'Una Quote en ' + status + ' debería tener el paso Quote Approved en verde' );
        }
        Test.stopTest();
    }

    /**
     * @description Negativo: Draft, In Review, Denied y Rejected no cuentan como aprobada.
     */
    @isTest
    static void notApprovedStatusesTest() {
        List<String> statusList = new List<String>{ 'Draft', 'In Review', 'Denied', 'Rejected' };
        Map<String, Id> quoteIdByStatusMap = insertQuotesByStatus( statusList );

        Test.startTest();
        for ( String status : statusList ) {
            List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quoteIdByStatusMap.get( status ) );
            System.assertEquals( false, stepList[APPROVED_INDEX].isDone,
                'Una Quote en ' + status + ' debería tener el paso Quote Approved en rojo' );
        }
        Test.stopTest();
    }

    // ---------------------------------------------------------------------------------
    // Eficiencia y errores
    // ---------------------------------------------------------------------------------

    /**
     * @description Eficiencia: el controller usa 1 sola SOQL (los 5 pasos salen de la misma
     *              query, con un lookup y una subquery).
     */
    @isTest
    static void singleQueryTest() {
        SBQQ__Quote__c quote = insertQuote( getOpenOpportunityId(), 'Draft' );

        Test.startTest();
        QuoteProgressController.getProgressSteps( quote.Id );
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        System.assertEquals( 1, queriesUsed, 'El controller debería usar una sola SOQL' );
    }

    /**
     * @description Negativo: si la Quote no existe (por ejemplo, la borraron), se lanza una
     *              AuraHandledException con un mensaje legible para el usuario.
     */
    @isTest
    static void quoteNotFoundTest() {
        SBQQ__Quote__c quote = insertQuote( getOpenOpportunityId(), 'Draft' );
        Id deletedQuoteId = quote.Id;
        delete quote;

        String errorMessage;
        Test.startTest();
        try {
            QuoteProgressController.getProgressSteps( deletedQuoteId );
        } catch ( AuraHandledException e ) {
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals( QuoteProgressController.QUOTE_NOT_FOUND_MESSAGE, errorMessage,
            'Una Quote inexistente debería lanzar una AuraHandledException con el mensaje para el usuario' );
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    /**
     * @description Inserta una Quote con la Opportunity y el Status indicados.
     */
    private static SBQQ__Quote__c insertQuote( Id opportunityId, String status ) {
        SBQQ__Quote__c quote = TestDataFactory.buildQuotes( getAccountId(), 1, status, Date.today().addDays( 30 ) )[0];
        quote.SBQQ__Opportunity2__c = opportunityId;
        insert quote;
        return quote;
    }

    /**
     * @description Inserta una Quote por cada Status (con un solo insert) y devuelve sus Ids
     *              por Status.
     */
    private static Map<String, Id> insertQuotesByStatus( List<String> statusList ) {
        Id accountId = getAccountId();
        Id opportunityId = getOpenOpportunityId();
        List<SBQQ__Quote__c> quoteList = new List<SBQQ__Quote__c>();
        for ( String status : statusList ) {
            SBQQ__Quote__c quote = TestDataFactory.buildQuotes( accountId, 1, status, Date.today().addDays( 30 ) )[0];
            quote.SBQQ__Opportunity2__c = opportunityId;
            quoteList.add( quote );
        }
        insert quoteList;

        Map<String, Id> quoteIdByStatusMap = new Map<String, Id>();
        for ( SBQQ__Quote__c quote : quoteList ) {
            quoteIdByStatusMap.put( quote.SBQQ__Status__c, quote.Id );
        }
        return quoteIdByStatusMap;
    }

    /**
     * @description Verifica que SOLO el paso de la posición indicada esté en verde.
     */
    private static void assertOnlyStepDone( List<QuoteProgressController.ProgressStep> stepList, Integer doneIndex ) {
        for ( Integer i = 0; i < stepList.size(); i++ ) {
            Boolean expectedIsDone = ( i == doneIndex );
            System.assertEquals( expectedIsDone, stepList[i].isDone,
                'El paso "' + stepList[i].label + '" debería estar ' + ( expectedIsDone ? 'en verde' : 'en rojo' ) );
        }
    }

    private static Id getAccountId() {
        return [SELECT Id FROM Account LIMIT 1].Id;
    }

    private static Id getOpenOpportunityId() {
        return [SELECT Id FROM Opportunity WHERE StageName = :STAGE_OPEN LIMIT 1].Id;
    }

    private static Id getProductId() {
        return [SELECT Id FROM Product2 LIMIT 1].Id;
    }
}
