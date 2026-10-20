/**
 * @description Tests for DEV #4: SubscriptionTrigger + SubscriptionTriggerHandler.
 *              They test the 4 contexts (insert, update, delete, undelete), the Contract change
 *              and the bulk case. The "active" rule is tested in ActiveSubscriptionCounterTest.
 */
@IsTest
private class SubscriptionTriggerHandlerTest {

    private static final Integer BULK_SIZE = 200;

    /**
     * @description Common data: an Account, a product and two Contracts in force (A and B).
     */
    @testSetup
    static void setup() {
        Account acc = TestDataFactory.createAccount();
        TestDataFactory.createProduct();
        TestDataFactory.createContract( acc.Id, Date.today(), 12 );
        TestDataFactory.createContract( acc.Id, Date.today(), 24 );
    }

    /**
     * @description after insert: 2 Subscriptions on A and 1 on B, in the same insert -> A = 2, B = 1.
     */
    @isTest
    static void insertTest() {
        List<SBQQ__Subscription__c> subList = TestDataFactory.buildSubscriptions( getContractAId(), getProductId(), 2, 10 );
        subList.addAll( TestDataFactory.buildSubscriptions( getContractBId(), getProductId(), 1, 10 ) );

        Test.startTest();
        insert subList;
        Test.stopTest();

        System.assertEquals( 2, getActiveCount( getContractAId() ), 'Contract A should have 2 active' );
        System.assertEquals( 1, getActiveCount( getContractBId() ), 'Contract B should have 1 active' );
    }

    /**
     * @description after update (relevant change): the Subscription is terminated today -> goes from 1 to 0.
     */
    @isTest
    static void updateRelevantFieldTest() {
        List<SBQQ__Subscription__c> subList = insertSubscriptions( getContractAId(), 1 );

        Test.startTest();
        subList[0].SBQQ__TerminatedDate__c = Date.today();
        update subList;
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( getContractAId() ),
            'When terminated today, the Subscription should stop counting' );
    }

    /**
     * @description Negative, after update with no relevant change: only the price changes -> it is not
     *              recalculated. To prove it, a "wrong" number (99) is first set manually
     *              on the Contract: if the trigger recalculated, it would fix it to 1.
     */
    @isTest
    static void updateIrrelevantFieldTest() {
        List<SBQQ__Subscription__c> subList = insertSubscriptions( getContractAId(), 1 );
        update new Contract( Id = getContractAId(), Active_Subscriptions__c = 99 );

        Test.startTest();
        subList[0].SBQQ__NetPrice__c = 50;
        update subList;
        Test.stopTest();

        System.assertEquals( 99, getActiveCount( getContractAId() ),
            'A price change does not affect the count, so it should not be recalculated' );
    }

    /**
     * @description after update, special case: the Subscription moves from A to B -> both
     *              are recalculated: A loses one (0) and B gains one (1).
     */
    @isTest
    static void moveToAnotherContractTest() {
        List<SBQQ__Subscription__c> subList = insertSubscriptions( getContractAId(), 1 );

        Test.startTest();
        subList[0].SBQQ__Contract__c = getContractBId();
        update subList;
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( getContractAId() ), 'The old Contract (A) should end up at 0' );
        System.assertEquals( 1, getActiveCount( getContractBId() ), 'The new Contract (B) should end up at 1' );
    }

    /**
     * @description after delete: one of two Subscriptions is deleted -> goes from 2 to 1.
     */
    @isTest
    static void deleteTest() {
        List<SBQQ__Subscription__c> subList = insertSubscriptions( getContractAId(), 2 );

        Test.startTest();
        delete subList[0];
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( getContractAId() ),
            'The deleted Subscription should stop counting' );
    }

    /**
     * @description after undelete: it is deleted and restored from the Recycle Bin -> back to 1.
     */
    @isTest
    static void undeleteTest() {
        List<SBQQ__Subscription__c> subList = insertSubscriptions( getContractAId(), 1 );
        delete subList;

        Test.startTest();
        undelete subList;
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( getContractAId() ),
            'The restored Subscription should count again' );
    }

    /**
     * @description Negative: a Subscription without a Contract does not break anything or create errors.
     */
    @isTest
    static void subscriptionWithoutContractTest() {
        Test.startTest();
        insert TestDataFactory.buildSubscriptions( null, getProductId(), 1, 10 );
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( getContractAId() ), 'The Contracts should not change' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'No Error Log should be created' );
    }

    /**
     * @description Bulk: 200 Subscriptions in a single insert -> 200, without going over the limits
     *              (the recount does 1 query and 1 update for the whole batch).
     */
    @isTest
    static void bulkInsertTest() {
        List<SBQQ__Subscription__c> subList = TestDataFactory.buildSubscriptions( getContractAId(), getProductId(), BULK_SIZE, 1 );

        Test.startTest();
        insert subList;
        Test.stopTest();

        System.assertEquals( BULK_SIZE, getActiveCount( getContractAId() ),
            'The 200 Subscriptions should count' );
    }

    /**
     * @description Bulk: all 200 are deleted in a single delete -> 0.
     */
    @isTest
    static void bulkDeleteTest() {
        List<SBQQ__Subscription__c> subList = insertSubscriptions( getContractAId(), BULK_SIZE );

        Test.startTest();
        delete subList;
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( getContractAId() ),
            'After deleting the 200 the Contract should end up at 0' );
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    private static List<SBQQ__Subscription__c> insertSubscriptions( Id contractId, Integer numberOfSubscriptions ) {
        List<SBQQ__Subscription__c> subList = TestDataFactory.buildSubscriptions( contractId, getProductId(), numberOfSubscriptions, 10 );
        insert subList;
        return subList;
    }

    private static Id getProductId() {
        return [SELECT Id FROM Product2 LIMIT 1].Id;
    }

    // A = 12-month term, B = 24-month term (that is how they are told apart)
    private static Id getContractAId() {
        return [SELECT Id FROM Contract WHERE ContractTerm = 12 LIMIT 1].Id;
    }

    private static Id getContractBId() {
        return [SELECT Id FROM Contract WHERE ContractTerm = 24 LIMIT 1].Id;
    }

    private static Decimal getActiveCount( Id contractId ) {
        return [SELECT Active_Subscriptions__c FROM Contract WHERE Id = :contractId].Active_Subscriptions__c;
    }
}
