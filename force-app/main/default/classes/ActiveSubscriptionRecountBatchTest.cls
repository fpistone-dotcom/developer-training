/**
 * @description Tests for DEV #4: ActiveSubscriptionRecountBatch (nightly path).
 *              In a test, the whole Batch runs in Test.stopTest() and its execute() runs
 *              only once (that is why the bulk test uses 200 Contracts, the size of one chunk).
 */
@IsTest
private class ActiveSubscriptionRecountBatchTest {

    private static final Integer BULK_SIZE = 200;

    /**
     * @description Common data: an Account and a product.
     */
    @testSetup
    static void setup() {
        TestDataFactory.createAccount();
        TestDataFactory.createProduct();
    }

    /**
     * @description The time problem: the Subscription expires WITHOUT anyone editing it (here it is
     *              simulated by moving the Contract to the past: the Subscription takes the Contract
     *              end date). The trigger never finds out and the Contract still says 1 -> the Batch
     *              fixes it to 0.
     */
    @isTest
    static void expiredByTimeTest() {
        Contract con = TestDataFactory.createContract( getAccountId(), Date.today(), 12 );
        insert TestDataFactory.buildSubscriptions( con.Id, getProductId(), 1, 125 );
        System.assertEquals( 1, getActiveCount( con.Id ), 'Before expiring it should count 1' );

        // 1-month Contract that started 60 days ago: it has already ended, and the Subscription with it
        con.StartDate = Date.today().addDays( -60 );
        con.ContractTerm = 1;
        update con;
        System.assertEquals( 1, getActiveCount( con.Id ),
            'Without the Batch the number stays outdated (that is why the nightly job is needed)' );

        Test.startTest();
        Database.executeBatch( new ActiveSubscriptionRecountBatch() );
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( con.Id ),
            'The Batch should detect that the Subscription expired and set the Contract to 0' );
    }

    /**
     * @description Backfill / correction: the Contract has a wrong number (7) -> the Batch
     *              sets it to the real value (1).
     */
    @isTest
    static void fixWrongCountTest() {
        Contract con = TestDataFactory.createContract( getAccountId(), Date.today(), 12 );
        insert TestDataFactory.buildSubscriptions( con.Id, getProductId(), 1, 125 );
        update new Contract( Id = con.Id, Active_Subscriptions__c = 7 );

        Test.startTest();
        Database.executeBatch( new ActiveSubscriptionRecountBatch() );
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( con.Id ), 'The Batch should fix the number to 1' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'No Error Log should be created' );
    }

    /**
     * @description Bulk: 200 Contracts without Subscriptions with an old number (5) -> all 200 end up at 0.
     */
    @isTest
    static void bulkRecountTest() {
        // The query goes outside the for: inside it would be 200 queries and go over the 100 limit
        Id accountId = getAccountId();
        List<Contract> contractList = new List<Contract>();
        for ( Integer i = 0; i < BULK_SIZE; i++ ) {
            Contract con = new Contract();
            con.AccountId = accountId;
            con.StartDate = Date.today();
            con.ContractTerm = 12;
            con.Status = 'Draft';
            con.Active_Subscriptions__c = 5;
            contractList.add( con );
        }
        insert contractList;

        Test.startTest();
        Database.executeBatch( new ActiveSubscriptionRecountBatch() );
        Test.stopTest();

        Integer zeroCount = [SELECT COUNT() FROM Contract WHERE Active_Subscriptions__c = 0];
        System.assertEquals( BULK_SIZE, zeroCount, 'The 200 Contracts without Subscriptions should end up at 0' );
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    private static Id getAccountId() {
        return [SELECT Id FROM Account LIMIT 1].Id;
    }

    private static Id getProductId() {
        return [SELECT Id FROM Product2 LIMIT 1].Id;
    }

    private static Decimal getActiveCount( Id contractId ) {
        return [SELECT Active_Subscriptions__c FROM Contract WHERE Id = :contractId].Active_Subscriptions__c;
    }
}
