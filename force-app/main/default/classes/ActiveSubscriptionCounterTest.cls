/**
 * @description Tests for DEV #4: ActiveSubscriptionCounter, the "active" rule and the Amendments.
 *              The Subscriptions are really inserted, so SubscriptionTrigger calls the
 *              recount by itself (it is the real path). At the end the number saved on the Contract is read.
 *
 *              The Amendment revisions are built the same way CPQ created them in the org:
 *              a new record for the difference (+100 / -10), with SBQQ__RevisedSubscription__c
 *              pointing to the original Subscription.
 */
@IsTest
private class ActiveSubscriptionCounterTest {

    private static final Date TODAY = Date.today();

    /**
     * @description Common data: an Account, a product and a 12-month Contract starting today.
     */
    @testSetup
    static void setup() {
        Account acc = TestDataFactory.createAccount();
        TestDataFactory.createProduct();
        TestDataFactory.createContract( acc.Id, TODAY, 12 );
    }

    // ---------------------------------------------------------------------------------
    // Definition of "active" (dates and termination)
    // ---------------------------------------------------------------------------------

    /**
     * @description Positive: Subscription without its own dates (it takes the Contract dates, in force) -> counts 1.
     */
    @isTest
    static void activeSubscriptionCountsTest() {
        Test.startTest();
        insert TestDataFactory.buildSubscriptions( getContractId(), getProductId(), 1, 125 );
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( getContractId() ),
            'A Subscription in force should count 1' );
    }

    /**
     * @description Negative: Subscription that starts tomorrow -> it does not count yet.
     */
    @isTest
    static void futureSubscriptionNotCountedTest() {
        List<SBQQ__Subscription__c> subList = TestDataFactory.buildSubscriptions( getContractId(), getProductId(), 1, 125 );
        subList[0].SBQQ__SubscriptionStartDate__c = TODAY.addDays( 1 );

        Test.startTest();
        insert subList;
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( getContractId() ),
            'A Subscription that starts tomorrow should not count today' );
    }

    /**
     * @description Negative and edge case: one that ended yesterday does not count; one that ends TODAY still counts.
     */
    @isTest
    static void endDateBoundaryTest() {
        List<SBQQ__Subscription__c> subList = TestDataFactory.buildSubscriptions( getContractId(), getProductId(), 2, 10 );
        subList[0].SBQQ__SubscriptionEndDate__c = TODAY.addDays( -1 );
        subList[1].SBQQ__SubscriptionEndDate__c = TODAY;

        Test.startTest();
        insert subList;
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( getContractId() ),
            'Only the one ending today should count: the one that ended yesterday is no longer active' );
    }

    /**
     * @description Negative and edge case: terminated today does not count; terminated from tomorrow still counts.
     */
    @isTest
    static void terminatedDateBoundaryTest() {
        List<SBQQ__Subscription__c> subList = TestDataFactory.buildSubscriptions( getContractId(), getProductId(), 2, 10 );
        subList[0].SBQQ__TerminatedDate__c = TODAY;
        subList[1].SBQQ__TerminatedDate__c = TODAY.addDays( 1 );

        Test.startTest();
        insert subList;
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( getContractId() ),
            'Only the one terminated tomorrow should count: the one terminated today is no longer active' );
    }

    /**
     * @description Positive: evergreen Contract (no term and no end date) -> the Subscription counts.
     */
    @isTest
    static void evergreenContractTest() {
        Contract evergreenContract = TestDataFactory.createContract( getAccountId(), TODAY, null );

        Test.startTest();
        insert TestDataFactory.buildSubscriptions( evergreenContract.Id, getProductId(), 1, 5 );
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( evergreenContract.Id ),
            'Without an end date the Subscription does not expire, so it should count' );
    }

    // ---------------------------------------------------------------------------------
    // Amendments (option C: one per original Subscription with net quantity > 0)
    // ---------------------------------------------------------------------------------

    /**
     * @description Demo case: original 125, Amendment +100 and Amendment -10, already in force
     *              -> 125 + 100 - 10 = 215 > 0 -> counts 1 (not 3).
     */
    @isTest
    static void amendmentRevisionsCountOnceTest() {
        SBQQ__Subscription__c original = insertOriginal( 125 );

        Test.startTest();
        insert buildRevision( original.Id, 100, TODAY );
        insert buildRevision( original.Id, -10, TODAY );
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( getContractId() ),
            'The Amendment revisions change the quantity of the original: it should count 1, not 3' );
    }

    /**
     * @description Negative: an Amendment brings the quantity down to 0 (125 - 125) -> it stops counting.
     */
    @isTest
    static void fullCancellationNotCountedTest() {
        SBQQ__Subscription__c original = insertOriginal( 125 );

        Test.startTest();
        insert buildRevision( original.Id, -125, TODAY );
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( getContractId() ),
            'With a net quantity of 0 the Subscription is no longer active' );
    }

    /**
     * @description Edge case: the full cancellation starts tomorrow -> today the Subscription still counts.
     */
    @isTest
    static void futureCancellationStillCountsTest() {
        SBQQ__Subscription__c original = insertOriginal( 125 );

        Test.startTest();
        insert buildRevision( original.Id, -125, TODAY.addDays( 1 ) );
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( getContractId() ),
            'The cancellation has not started yet: today the Subscription is still active' );
    }

    // ---------------------------------------------------------------------------------
    // Efficiency
    // ---------------------------------------------------------------------------------

    /**
     * @description Negative: without Contracts no query is spent.
     */
    @isTest
    static void emptySetSkipsQueryTest() {
        Test.startTest();
        ActiveSubscriptionCounter.recountActiveSubscriptions( new Set<Id>() );
        Integer queryCount = Limits.getQueries();
        Test.stopTest();

        System.assertEquals( 0, queryCount, 'With an empty Set no query should run' );
    }

    /**
     * @description Negative: if the saved number is already correct, no update is done.
     */
    @isTest
    static void unchangedCountSkipsUpdateTest() {
        insert TestDataFactory.buildSubscriptions( getContractId(), getProductId(), 1, 125 );

        Test.startTest();
        ActiveSubscriptionCounter.recountActiveSubscriptions( new Set<Id>{ getContractId() } );
        Integer dmlCount = Limits.getDmlStatements();
        Test.stopTest();

        System.assertEquals( 0, dmlCount, 'If the number did not change no update should run' );
        System.assertEquals( 1, getActiveCount( getContractId() ), 'The number should stay at 1' );
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    private static SBQQ__Subscription__c insertOriginal( Decimal quantity ) {
        List<SBQQ__Subscription__c> subList = TestDataFactory.buildSubscriptions( getContractId(), getProductId(), 1, quantity );
        insert subList;
        return subList[0];
    }

    // Amendment revision: same structure as the ones CPQ created in the org (SUB-0000012 / 13)
    private static List<SBQQ__Subscription__c> buildRevision( Id originalId, Decimal quantity, Date startDate ) {
        List<SBQQ__Subscription__c> subList = TestDataFactory.buildSubscriptions( getContractId(), getProductId(), 1, quantity );
        subList[0].SBQQ__RevisedSubscription__c = originalId;
        subList[0].SBQQ__SubscriptionStartDate__c = startDate;
        return subList;
    }

    private static Id getAccountId() {
        return [SELECT Id FROM Account LIMIT 1].Id;
    }

    private static Id getProductId() {
        return [SELECT Id FROM Product2 LIMIT 1].Id;
    }

    // The @testSetup Contract is the only one with a 12-month term
    private static Id getContractId() {
        return [SELECT Id FROM Contract WHERE ContractTerm = 12 LIMIT 1].Id;
    }

    private static Decimal getActiveCount( Id contractId ) {
        return [SELECT Active_Subscriptions__c FROM Contract WHERE Id = :contractId].Active_Subscriptions__c;
    }
}
