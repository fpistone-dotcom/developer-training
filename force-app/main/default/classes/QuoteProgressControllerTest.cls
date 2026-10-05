/**
 * @description Tests for DEV #5: QuoteProgressController (the controller of the quoteProgress LWC).
 *              Covers positive, negative and edge cases for each of the 5 steps, the order and
 *              the texts of the steps, the efficiency (only 1 query) and the Quote not found.
 *
 *              No 200-record bulk test: the method receives ONE Quote (a page shows only one).
 *              Instead, singleQueryTest checks that it uses only 1 SOQL.
 *
 *              The LWC has no tests of its own (Jest is not part of the training and does not count
 *              for Apex coverage): it is tested in the org.
 */
@IsTest
private class QuoteProgressControllerTest {

    // Position of each step in the list the controller returns
    private static final Integer QUOTE_LINES_INDEX = 0;
    private static final Integer APPROVED_INDEX = 1;
    private static final Integer DOCUMENT_INDEX = 2;
    private static final Integer CLOSED_WON_INDEX = 3;
    private static final Integer ORDERED_INDEX = 4;

    private static final Integer NUMBER_OF_STEPS = 5;
    private static final String STAGE_OPEN = 'Prospecting';
    private static final String STAGE_CLOSED_WON = 'Closed Won';

    /**
     * @description Common data: an Account, an open Opportunity and a product.
     */
    @testSetup
    static void setup() {
        Account acc = TestDataFactory.createAccount();
        TestDataFactory.createOpportunity( acc.Id, STAGE_OPEN );
        TestDataFactory.createProduct();
    }

    // ---------------------------------------------------------------------------------
    // All the steps
    // ---------------------------------------------------------------------------------

    /**
     * @description Negative: a newly created Quote (Draft, no lines, no document,
     *              open Opportunity, not Ordered) has all 5 steps in red.
     */
    @isTest
    static void newQuoteAllStepsPendingTest() {
        SBQQ__Quote__c quote = insertQuote( getOpenOpportunityId(), 'Draft' );

        Test.startTest();
        List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quote.Id );
        Test.stopTest();

        System.assertEquals( NUMBER_OF_STEPS, stepList.size(), 'The 5 steps are always returned' );
        for ( QuoteProgressController.ProgressStep step : stepList ) {
            System.assertEquals( false, step.isDone, 'In a new Quote the step "' + step.label + '" should be red' );
        }
    }

    /**
     * @description Positive: a Quote with lines, approved, with a document, Opportunity Closed Won
     *              and Ordered has all 5 steps in green.
     */
    @isTest
    static void allStepsCompletedTest() {
        Opportunity wonOpportunity = TestDataFactory.createOpportunity( getAccountId(), STAGE_CLOSED_WON );
        SBQQ__Quote__c quote = insertQuote( wonOpportunity.Id, 'Approved' );
        insert TestDataFactory.buildQuoteLines( quote.Id, getProductId(), 1 );
        insert TestDataFactory.buildQuoteDocument( quote.Id, wonOpportunity.Id );
        // Only to set up the data: when Ordered is checked, CPQ tries to create the real Order (it
        // requires Primary, Pricebook, PricebookEntry...) and fires the whole Req #31 chain, which is
        // not part of DEV #5 (it was tested in the org in DEV #2). We turn off the CPQ triggers only
        // during this update and turn them back on: the controller runs with CPQ turned on.
        SBQQ.TriggerControl.disable();
        quote.SBQQ__Ordered__c = true;
        update quote;
        SBQQ.TriggerControl.enable();

        Test.startTest();
        List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quote.Id );
        Test.stopTest();

        for ( QuoteProgressController.ProgressStep step : stepList ) {
            System.assertEquals( true, step.isDone, 'With everything done, the step "' + step.label + '" should be green' );
        }
    }

    /**
     * @description Positive: the steps come in the order of the requirement and with their texts.
     */
    @isTest
    static void stepsOrderAndLabelsTest() {
        SBQQ__Quote__c quote = insertQuote( getOpenOpportunityId(), 'Draft' );

        Test.startTest();
        List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quote.Id );
        Test.stopTest();

        System.assertEquals( QuoteProgressController.STEP_QUOTE_LINES, stepList[QUOTE_LINES_INDEX].label, 'Step 1 should be Quote Lines Added' );
        System.assertEquals( QuoteProgressController.STEP_APPROVED, stepList[APPROVED_INDEX].label, 'Step 2 should be Quote Approved' );
        System.assertEquals( QuoteProgressController.STEP_DOCUMENT, stepList[DOCUMENT_INDEX].label, 'Step 3 should be Quote Document Created' );
        System.assertEquals( QuoteProgressController.STEP_CLOSED_WON, stepList[CLOSED_WON_INDEX].label, 'Step 4 should be Opportunity Closed Won' );
        System.assertEquals( QuoteProgressController.STEP_ORDERED, stepList[ORDERED_INDEX].label, 'Step 5 should be Quote Ordered' );
    }

    // ---------------------------------------------------------------------------------
    // One step at a time (the steps are independent)
    // ---------------------------------------------------------------------------------

    /**
     * @description Edge case: a Quote with lines and nothing else has ONLY step 1 in green.
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
     * @description Edge case: a Quote with a document and nothing else has ONLY step 3 in green.
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
     * @description Negative: the document of ANOTHER Quote of the same Opportunity does not count.
     *              That is why it filters by SBQQ__Quote__c and not by SBQQ__Opportunity__c.
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
            'The document of another Quote of the same Opportunity should not count' );
    }

    /**
     * @description Edge case: a Quote of a Closed Won Opportunity (and nothing else) has ONLY
     *              step 4 in green.
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
     * @description Edge case: a Quote without an Opportunity does not break (no NullPointerException) and
     *              step 4 stays red.
     */
    @isTest
    static void quoteWithoutOpportunityTest() {
        SBQQ__Quote__c quote = insertQuote( null, 'Draft' );

        Test.startTest();
        List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quote.Id );
        Test.stopTest();

        System.assertEquals( false, stepList[CLOSED_WON_INDEX].isDone,
            'Without an Opportunity, the Opportunity Closed Won step should be red' );
    }

    // ---------------------------------------------------------------------------------
    // Step 2: which Status values count as approved
    // ---------------------------------------------------------------------------------

    /**
     * @description Positive: Approved, Presented and Accepted count as approved
     *              (Presented and Accepted are statuses after the approval).
     */
    @isTest
    static void approvedStatusesTest() {
        List<String> statusList = new List<String>{ 'Approved', 'Presented', 'Accepted' };
        Map<String, Id> quoteIdByStatusMap = insertQuotesByStatus( statusList );

        Test.startTest();
        for ( String status : statusList ) {
            List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quoteIdByStatusMap.get( status ) );
            System.assertEquals( true, stepList[APPROVED_INDEX].isDone,
                'A Quote in ' + status + ' should have the Quote Approved step in green' );
        }
        Test.stopTest();
    }

    /**
     * @description Negative: Draft, In Review, Denied and Rejected do not count as approved.
     */
    @isTest
    static void notApprovedStatusesTest() {
        List<String> statusList = new List<String>{ 'Draft', 'In Review', 'Denied', 'Rejected' };
        Map<String, Id> quoteIdByStatusMap = insertQuotesByStatus( statusList );

        Test.startTest();
        for ( String status : statusList ) {
            List<QuoteProgressController.ProgressStep> stepList = QuoteProgressController.getProgressSteps( quoteIdByStatusMap.get( status ) );
            System.assertEquals( false, stepList[APPROVED_INDEX].isDone,
                'A Quote in ' + status + ' should have the Quote Approved step in red' );
        }
        Test.stopTest();
    }

    // ---------------------------------------------------------------------------------
    // Efficiency and errors
    // ---------------------------------------------------------------------------------

    /**
     * @description Efficiency: the controller uses only 1 SOQL (the 5 steps come from the same
     *              query, with a lookup and a subquery).
     */
    @isTest
    static void singleQueryTest() {
        SBQQ__Quote__c quote = insertQuote( getOpenOpportunityId(), 'Draft' );

        Test.startTest();
        QuoteProgressController.getProgressSteps( quote.Id );
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        System.assertEquals( 1, queriesUsed, 'The controller should use a single SOQL' );
    }

    /**
     * @description Negative: if the Quote does not exist (for example, it was deleted), an
     *              AuraHandledException is thrown with a message the user can read.
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
            'A Quote that does not exist should throw an AuraHandledException with the user message' );
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    /**
     * @description Inserts a Quote with the given Opportunity and Status.
     */
    private static SBQQ__Quote__c insertQuote( Id opportunityId, String status ) {
        SBQQ__Quote__c quote = TestDataFactory.buildQuotes( getAccountId(), 1, status, Date.today().addDays( 30 ) )[0];
        quote.SBQQ__Opportunity2__c = opportunityId;
        insert quote;
        return quote;
    }

    /**
     * @description Inserts one Quote per Status (with a single insert) and returns their Ids
     *              by Status.
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
     * @description Checks that ONLY the step at the given position is green.
     */
    private static void assertOnlyStepDone( List<QuoteProgressController.ProgressStep> stepList, Integer doneIndex ) {
        for ( Integer i = 0; i < stepList.size(); i++ ) {
            Boolean expectedIsDone = ( i == doneIndex );
            System.assertEquals( expectedIsDone, stepList[i].isDone,
                'The step "' + stepList[i].label + '" should be ' + ( expectedIsDone ? 'green' : 'red' ) );
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
