/**
 * @description Tests for DEV #1 (Part B): QuoteExpirationBatch.
 *              The pending approvals are REAL: they are submitted with Approval.process and
 *              the org's Approval Process (Quote_Approval_V2) also runs in the test.
 *              With Payment Terms = Net 60 the Quote is left pending on Finance (In Review).
 *
 *              In a test, the whole Batch runs in Test.stopTest() and its execute() runs
 *              only once (that is why the bulk test uses 200 Quotes, the size of one chunk).
 */
@IsTest
private class QuoteExpirationBatchTest {

    private static final Integer BULK_SIZE = 200;
    private static final String PAYMENT_TERMS_NEEDING_APPROVAL = 'Net 60';
    private static final Date YESTERDAY = Date.today().addDays( -1 );

    /**
     * @description Common data: an Account, an open Opportunity and a won one.
     */
    @testSetup
    static void setup() {
        Account acc = TestDataFactory.createAccount();
        TestDataFactory.createOpportunity( acc.Id, 'Prospecting' );
        TestDataFactory.createOpportunity( acc.Id, 'Closed Won' );
    }

    // ---------------------------------------------------------------------------------
    // Positive cases: the recall happens
    // ---------------------------------------------------------------------------------

    /**
     * @description Positive: pending Quote, expired yesterday, with the Opportunity open
     *              -> recall: it goes back to Draft and no longer has a pending approval.
     */
    @isTest
    static void recallExpiredQuoteTest() {
        List<SBQQ__Quote__c> quoteList = insertPendingQuotes( getOpportunityId( false ), 1, YESTERDAY );

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        System.assertEquals( 'Draft', getStatus( quoteList[0].Id ),
            'The expired Quote with the Opportunity open should go back to Draft (Recall Action)' );
        System.assertEquals( 0, countPendingApprovals( quoteList ),
            'The Quote should not have pending approvals after the recall' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c],
            'A successful recall should not create Error Logs' );
    }

    /**
     * @description Edge case: the Quote expires TODAY. "Reaches the Expiration Date" = the same day
     *              (SBQQ__ExpirationDate__c <= TODAY) -> recall.
     */
    @isTest
    static void recallQuoteExpiringTodayTest() {
        List<SBQQ__Quote__c> quoteList = insertPendingQuotes( getOpportunityId( false ), 1, Date.today() );

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        System.assertEquals( 'Draft', getStatus( quoteList[0].Id ),
            'A Quote that expires today has reached its expiration and should be recalled' );
    }

    /**
     * @description Bulk: 200 pending and expired Quotes -> all 200 go back to Draft.
     */
    @isTest
    static void recallBulkTest() {
        List<SBQQ__Quote__c> quoteList = insertPendingQuotes( getOpportunityId( false ), BULK_SIZE, YESTERDAY );

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        Integer draftCount = [SELECT COUNT() FROM SBQQ__Quote__c WHERE SBQQ__Status__c = 'Draft'];
        System.assertEquals( BULK_SIZE, draftCount, 'The 200 expired Quotes should go back to Draft' );
        System.assertEquals( 0, countPendingApprovals( quoteList ),
            'None of the 200 Quotes should be left with pending approvals' );
    }

    // ---------------------------------------------------------------------------------
    // Negative cases: the Quote is not touched
    // ---------------------------------------------------------------------------------

    /**
     * @description Negative: the Quote expires tomorrow -> it stays pending.
     */
    @isTest
    static void notRecalledWhenNotExpiredTest() {
        List<SBQQ__Quote__c> quoteList = insertPendingQuotes( getOpportunityId( false ), 1, Date.today().addDays( 1 ) );

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        System.assertEquals( 'In Review', getStatus( quoteList[0].Id ),
            'A Quote that has not expired yet should not be recalled' );
        System.assertEquals( 1, countPendingApprovals( quoteList ),
            'The approval of a Quote that has not expired should stay pending' );
    }

    /**
     * @description Negative: the Opportunity is already Closed Won -> no recall.
     */
    @isTest
    static void notRecalledWhenOpportunityWonTest() {
        List<SBQQ__Quote__c> quoteList = insertPendingQuotes( getOpportunityId( true ), 1, YESTERDAY );

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        System.assertEquals( 'In Review', getStatus( quoteList[0].Id ),
            'If the Opportunity is already Closed Won, the Quote should not be recalled' );
    }

    /**
     * @description Negative (mentor assumption): an already approved and expired Quote is not touched.
     *              It is inserted approved (the trigger sets today + 30) and then a past expiration
     *              is forced; since the Status does not change, the trigger does not recalculate it.
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
            'An already approved Quote should not be touched, even if it is expired' );
    }

    /**
     * @description Negative (documented assumption): a Quote without an Opportunity is left out.
     */
    @isTest
    static void notRecalledWithoutOpportunityTest() {
        List<SBQQ__Quote__c> quoteList = insertPendingQuotes( null, 1, YESTERDAY );

        Test.startTest();
        Database.executeBatch( new QuoteExpirationBatch() );
        Test.stopTest();

        System.assertEquals( 'In Review', getStatus( quoteList[0].Id ),
            'A Quote without an Opportunity should not be recalled' );
    }

    /**
     * @description Edge case: a Quote with Status "In Review" set manually, with no pending
     *              approval. The Batch finds it but there is nothing to recall: it does not touch it
     *              and does not create errors.
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
            'Without a pending approval there is no recall: the Quote should not change' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c],
            'A Quote without a pending approval should not create Error Logs' );
    }

    // ---------------------------------------------------------------------------------
    // Helper methods
    // ---------------------------------------------------------------------------------

    private static Id getAccountId() {
        return [SELECT Id FROM Account LIMIT 1].Id;
    }

    /**
     * @param isWon true for the Closed Won Opportunity, false for the open one
     * @return Id of the requested Opportunity
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
     * @description Inserts Quotes and really submits them for approval (Submit), so they are
     *              In Review with an approval pending on Finance.
     * @param opportunityId  Opportunity of the Quotes (null = no Opportunity)
     * @param numberOfQuotes Number of Quotes
     * @param expirationDate Expiration date of the Quotes
     * @return Quotes inserted and submitted for approval
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
