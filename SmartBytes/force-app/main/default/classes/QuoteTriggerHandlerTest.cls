/**
 * @description Tests for DEV #1 (Part A): QuoteTrigger and QuoteTriggerHandler.
 *              Covers positive, negative and bulk (200 records) cases of both paths:
 *              - Update: the Status changes to Approved (that is what the Approval Process does).
 *              - Insert: the Quote is created already approved.
 *              It also covers DEV #3 (Part 3): the email to the Owner of a new Renewal Quote.
 *
 *              All the Quotes are created with an "original" expiration of today + 5, different
 *              from the one our trigger sets (today + 30). That way we can see whether the trigger
 *              overrode it or not: the CPQ default (30 days from creation) matches today + 30 and
 *              would not help to tell them apart.
 *
 *              The real Approval Process cannot run in this test: the Status is changed manually,
 *              which is exactly what its Set_Quote_Status_Approved field update does.
 */
@IsTest
private class QuoteTriggerHandlerTest {

    private static final Integer BULK_SIZE = 200;
    private static final Date ORIGINAL_EXPIRATION_DATE = Date.today().addDays( 5 );
    private static final Date EXPECTED_EXPIRATION_DATE = Date.today().addDays( QuoteTriggerHandler.DAYS_UNTIL_EXPIRATION );

    /**
     * @description Common data for all the tests: an Account.
     */
    @testSetup
    static void setup() {
        TestDataFactory.createAccount();
    }

    // ---------------------------------------------------------------------------------
    // UPDATE path
    // ---------------------------------------------------------------------------------

    /**
     * @description Positive: a Draft Quote that changes to Approved expires on today + 30.
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
            'When approved, the Quote should expire on today + 30 days' );
    }

    /**
     * @description Bulk: 200 Quotes approved together all expire on today + 30.
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
        System.assertEquals( BULK_SIZE, updatedCount, 'The 200 approved Quotes should expire on today + 30 days' );
    }

    /**
     * @description Negative: if the Status changes to another value (In Review), the expiration does not change.
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
            'If the Quote is not approved, the expiration should not change' );
    }

    /**
     * @description Negative: if the Quote was already approved and something else is edited (here, the
     *              expiration itself), the trigger does not recalculate it.
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
            'If the Status did not change, the expiration should not be recalculated' );
    }

    /**
     * @description Positive: a Quote that goes back to Draft (for example, after a recall)
     *              and is approved again recalculates the expiration from the new approval.
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
            'When approved again, the Quote should expire on today + 30 days' );
    }

    // ---------------------------------------------------------------------------------
    // INSERT path
    // ---------------------------------------------------------------------------------

    /**
     * @description Positive: a Quote created already approved expires on today + 30.
     */
    @isTest
    static void setExpirationOnInsertApprovedTest() {
        Test.startTest();
        List<SBQQ__Quote__c> quoteList = insertQuotes( 1, 'Approved' );
        Test.stopTest();

        SBQQ__Quote__c result = getQuote( quoteList[0].Id );
        System.assertEquals( EXPECTED_EXPIRATION_DATE, result.SBQQ__ExpirationDate__c,
            'A Quote created already approved should expire on today + 30 days' );
    }

    /**
     * @description Bulk: 200 Quotes created already approved all expire on today + 30.
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
        System.assertEquals( BULK_SIZE, updatedCount, 'The 200 Quotes created approved should expire on today + 30 days' );
    }

    /**
     * @description Negative: a Quote created in Draft keeps its expiration.
     */
    @isTest
    static void notSetOnInsertNotApprovedTest() {
        Test.startTest();
        List<SBQQ__Quote__c> quoteList = insertQuotes( 1, 'Draft' );
        Test.stopTest();

        SBQQ__Quote__c result = getQuote( quoteList[0].Id );
        System.assertEquals( ORIGINAL_EXPIRATION_DATE, result.SBQQ__ExpirationDate__c,
            'A Quote created in Draft should not change its expiration' );
    }

    // ---------------------------------------------------------------------------------
    // DEV #3 (Part 3): email to the Owner of a new Renewal Quote
    //
    // In a test the emails are not really sent, but Salesforce counts the calls to
    // Messaging.sendEmail. Limits.getEmailInvocations() is read BEFORE Test.stopTest(),
    // because it measures the transaction between startTest and stopTest.
    // ---------------------------------------------------------------------------------

    /**
     * @description Positive: creating a requested Renewal Quote (Contract with Renewal Quoted
     *              checked) sends the email, with no errors.
     */
    @isTest
    static void renewalQuoteSendsEmailTest() {
        Id opportunityId = createRenewalOpportunity( true );

        Test.startTest();
        insertRenewalQuotes( 1, opportunityId );
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals( 1, emailInvocations, 'A new Renewal Quote should fire one email send' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'The send should not create errors' );
    }

    /**
     * @description Bulk: 200 Renewal Quotes created together use ONE single send (with 200 emails),
     *              not 200 (the limit is 10 sends per transaction).
     */
    @isTest
    static void renewalQuoteBulkEmailTest() {
        Id opportunityId = createRenewalOpportunity( true );

        Test.startTest();
        insertRenewalQuotes( BULK_SIZE, opportunityId );
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals( 1, emailInvocations, 'The 200 Renewal Quotes should be sent in a single call' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'The send should not create errors' );
    }

    /**
     * @description Negative: a Quote that is not a Renewal does not send an email.
     */
    @isTest
    static void nonRenewalQuoteNoEmailTest() {
        Test.startTest();
        insertQuotes( 1, 'Draft' );
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals( 0, emailInvocations, 'A Quote that is not a Renewal should not send an email' );
    }

    /**
     * @description Negative: a Renewal Quote whose Contract does NOT have Renewal Quoted checked does not
     *              send an email. This is the case of the temporary Renewal Quote that CPQ creates when
     *              a Contract is activated (to calculate the Renewal Opportunity) and deletes seconds later.
     */
    @isTest
    static void renewalQuoteNotRequestedNoEmailTest() {
        Id opportunityId = createRenewalOpportunity( false );

        Test.startTest();
        insertRenewalQuotes( 1, opportunityId );
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals( 0, emailInvocations,
            'A Renewal Quote nobody requested (the CPQ temporary one) should not send an email' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'There should be no errors' );
    }

    // ---------------------------------------------------------------------------------
    // Helper methods
    // ---------------------------------------------------------------------------------

    private static Id getAccountId() {
        return [SELECT Id FROM Account LIMIT 1].Id;
    }

    private static SBQQ__Quote__c getQuote( Id quoteId ) {
        return [SELECT SBQQ__ExpirationDate__c FROM SBQQ__Quote__c WHERE Id = :quoteId];
    }

    /**
     * @description Inserts Quotes with the given Status and the original expiration (today + 5).
     * @param numberOfQuotes Number of Quotes
     * @param status         Value of SBQQ__Status__c
     * @return Inserted Quotes
     */
    private static List<SBQQ__Quote__c> insertQuotes( Integer numberOfQuotes, String status ) {
        List<SBQQ__Quote__c> quoteList = TestDataFactory.buildQuotes( getAccountId(), numberOfQuotes, status, ORIGINAL_EXPIRATION_DATE );
        insert quoteList;
        return quoteList;
    }

    /**
     * @description Creates a Contract and its Renewal Opportunity (like the one CPQ creates), with
     *              SBQQ__RenewalQuoted__c set to the given value. It is called BEFORE Test.startTest():
     *              whatever CPQ does when the Contract is created does not count in the limits the test measures.
     * @param renewalQuoted true = someone requested the Renewal Quote (the Batch or a user)
     * @return Id of the Renewal Opportunity
     */
    private static Id createRenewalOpportunity( Boolean renewalQuoted ) {
        Contract con = TestDataFactory.buildContracts( getAccountId(), Date.today(), 12, 1 )[0];
        con.SBQQ__RenewalQuoted__c = renewalQuoted;
        insert con;
        Opportunity opp = TestDataFactory.buildRenewalOpportunities( getAccountId(),
            new List<Contract>{ con }, 'Prospecting' )[0];
        insert opp;
        return opp.Id;
    }

    /**
     * @description Inserts Renewal type Quotes (like the ones CPQ generates) on the given Renewal
     *              Opportunity, with Owner = the user running the test.
     * @param numberOfQuotes Number of Quotes
     * @param opportunityId  Renewal Opportunity of the Quotes
     * @return Inserted Quotes
     */
    private static List<SBQQ__Quote__c> insertRenewalQuotes( Integer numberOfQuotes, Id opportunityId ) {
        List<SBQQ__Quote__c> quoteList = TestDataFactory.buildQuotes( getAccountId(), numberOfQuotes, 'Draft', ORIGINAL_EXPIRATION_DATE );
        for ( SBQQ__Quote__c quote : quoteList ) {
            quote.SBQQ__Type__c = QuoteTriggerHandler.TYPE_RENEWAL;
            quote.SBQQ__Opportunity2__c = opportunityId;
        }
        insert quoteList;
        return quoteList;
    }
}
