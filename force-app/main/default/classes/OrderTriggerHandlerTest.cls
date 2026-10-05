/**
 * @description Tests for DEV #2: OrderTrigger, OrderTriggerHandler and OrderActivationQueueable.
 *              Covers positive, negative and bulk (200 records) cases of both paths:
 *              - Insert: the activation is done by the Queueable, which in a test runs in Test.stopTest().
 *              - Update: the activation happens right away (before update).
 */
@IsTest
private class OrderTriggerHandlerTest {

    private static final Integer BULK_SIZE = 200;

    /**
     * @description Common data for all the tests: an Account and a product with a price.
     */
    @testSetup
    static void setup() {
        TestDataFactory.createAccount();
        TestDataFactory.createPricebookEntry();
    }

    // ---------------------------------------------------------------------------------
    // INSERT path (Req B)
    // ---------------------------------------------------------------------------------

    /**
     * @description Positive: an Order created with 'Not Needed' that has products
     *              is activated when the Queueable runs.
     */
    @isTest
    static void activateOnInsertTest() {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), 1, 'Not Needed' );

        Test.startTest();
        insert orderList;
        insert TestDataFactory.buildOrderItems( orderList, getPricebookEntry() );
        Test.stopTest(); // the Queueable runs here

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Activated', result.Status, 'The Order created with Not Needed and with products should be Activated' );
    }

    /**
     * @description Bulk: 200 Orders created together are activated with a single Queueable.
     */
    @isTest
    static void activateOnInsertBulkTest() {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), BULK_SIZE, 'Not Needed' );

        Test.startTest();
        insert orderList;
        insert TestDataFactory.buildOrderItems( orderList, getPricebookEntry() );
        Test.stopTest();

        Integer activatedCount = [SELECT COUNT() FROM Order WHERE Status = 'Activated'];
        System.assertEquals( BULK_SIZE, activatedCount, 'The 200 Orders should be Activated' );
    }

    /**
     * @description Negative: an Order created with a status that is not ready ('Queued')
     *              is not activated.
     */
    @isTest
    static void notActivatedOnInsertWhenNotReadyTest() {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), 1, 'Queued' );

        Test.startTest();
        insert orderList;
        insert TestDataFactory.buildOrderItems( orderList, getPricebookEntry() );
        Test.stopTest();

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Draft', result.Status, 'An Order with Queued status should not be activated' );
    }

    /**
     * @description Negative: an Order created with 'Not Needed' but without products is not
     *              activated (Salesforce does not allow it and the Queueable skips it).
     */
    @isTest
    static void notActivatedOnInsertWithoutItemsTest() {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), 1, 'Not Needed' );

        Test.startTest();
        insert orderList;
        Test.stopTest();

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Draft', result.Status, 'An Order without products should not be activated' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'No error should be logged: the Order is skipped, it does not fail' );
    }

    /**
     * @description Edge case: if no more Queueables can be enqueued, the Order creation
     *              does not break and an Error Log is recorded.
     */
    @isTest
    static void logErrorWhenQueueableLimitReachedTest() {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), 1, 'Not Needed' );

        Test.startTest();
        // Fill the transaction's Queueable quota with empty jobs
        Integer queueableLimit = Limits.getLimitQueueableJobs();
        for ( Integer i = 0; i < queueableLimit; i++ ) {
            System.enqueueJob( new OrderActivationQueueable( new Set<Id>() ) );
        }
        insert orderList;
        Test.stopTest();

        // WITH SYSTEM_MODE: the test checks the log without depending on the permissions of the user running the test
        List<Error_Log__c> errorLogList = [SELECT Class_Name__c, Record_Id__c FROM Error_Log__c WITH SYSTEM_MODE];
        System.assertEquals( 1, errorLogList.size(), 'An Error Log should be recorded for the Order that could not be enqueued' );
        System.assertEquals( 'OrderTriggerHandler', errorLogList[0].Class_Name__c, 'The log should show the class that created it' );
        System.assertEquals( orderList[0].Id, errorLogList[0].Record_Id__c, 'The log should point to the affected Order' );
    }

    /**
     * @description Edge case: if Salesforce rejects the activation inside the Queueable,
     *              the Order stays in Draft and the error is recorded in Error_Log__c.
     *              To force the failure, the Order is linked to a Contract that is not
     *              activated: Salesforce does not allow activating an Order in that case.
     */
    @isTest
    static void logErrorWhenActivationFailsTest() {
        Id accountId = getAccountId();
        Contract draftContract = TestDataFactory.createDraftContract( accountId );
        List<Order> orderList = TestDataFactory.buildOrders( accountId, 1, 'Not Needed' );
        orderList[0].ContractId = draftContract.Id;

        Test.startTest();
        insert orderList;
        insert TestDataFactory.buildOrderItems( orderList, getPricebookEntry() );
        Test.stopTest(); // the Queueable runs here and the activation fails

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Draft', result.Status, 'The Order should not be activated if Salesforce rejects the activation' );

        List<Error_Log__c> errorLogList = [SELECT Class_Name__c, Record_Id__c FROM Error_Log__c WITH SYSTEM_MODE];
        System.assertEquals( 1, errorLogList.size(), 'An Error Log should be recorded for the failed activation' );
        System.assertEquals( 'OrderActivationQueueable', errorLogList[0].Class_Name__c, 'The log should show that it failed in the Queueable' );
        System.assertEquals( orderList[0].Id, errorLogList[0].Record_Id__c, 'The log should point to the Order that could not be activated' );
    }

    // ---------------------------------------------------------------------------------
    // UPDATE path (Req C)
    // ---------------------------------------------------------------------------------

    /**
     * @description Positive: an Order with products whose status changes from 'Queued' to
     *              'Completed' is activated right away.
     */
    @isTest
    static void activateOnUpdateTest() {
        List<Order> orderList = insertOrdersWithItems( 1, 'Queued' );

        Test.startTest();
        orderList[0].SBQQ__PriceCalcStatus__c = 'Completed';
        update orderList;
        Test.stopTest();

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Activated', result.Status, 'The Order should be activated when it changes to Completed' );
    }

    /**
     * @description Bulk: 200 Orders that change to 'Completed' in the same update are all activated.
     */
    @isTest
    static void activateOnUpdateBulkTest() {
        List<Order> orderList = insertOrdersWithItems( BULK_SIZE, 'Queued' );

        Test.startTest();
        for ( Order ord : orderList ) {
            ord.SBQQ__PriceCalcStatus__c = 'Completed';
        }
        update orderList;
        Test.stopTest();

        Integer activatedCount = [SELECT COUNT() FROM Order WHERE Status = 'Activated'];
        System.assertEquals( BULK_SIZE, activatedCount, 'The 200 Orders should be Activated' );
    }

    /**
     * @description Negative: if the status changes to a value that is not ready ('Failed'),
     *              the Order is not activated.
     */
    @isTest
    static void notActivatedOnUpdateToNotReadyValueTest() {
        List<Order> orderList = insertOrdersWithItems( 1, 'Queued' );

        Test.startTest();
        orderList[0].SBQQ__PriceCalcStatus__c = 'Failed';
        update orderList;
        Test.stopTest();

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Draft', result.Status, 'An Order that changes to Failed should not be activated' );
    }

    /**
     * @description Negative: if the status changes to 'Completed' but the Order has no
     *              products, it is not activated and the save does not fail.
     */
    @isTest
    static void notActivatedOnUpdateWithoutItemsTest() {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), 1, 'Queued' );
        insert orderList;

        Test.startTest();
        orderList[0].SBQQ__PriceCalcStatus__c = 'Completed';
        update orderList;
        Test.stopTest();

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Draft', result.Status, 'An Order without products should not be activated' );
    }

    /**
     * @description Negative: if another field is edited and the Price Calculation Status does not change,
     *              the Order is not reprocessed even if it already has a ready value.
     */
    @isTest
    static void notActivatedWhenPriceCalcStatusDidNotChangeTest() {
        // Draft Order with 'Completed' and no products: the update to Completed does not activate it
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), 1, 'Queued' );
        insert orderList;
        orderList[0].SBQQ__PriceCalcStatus__c = 'Completed';
        update orderList;
        // Now we add products to it, without touching the status
        insert TestDataFactory.buildOrderItems( orderList, getPricebookEntry() );

        Test.startTest();
        orderList[0].Description = 'Edited description';
        update orderList;
        Test.stopTest();

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Draft', result.Status, 'If the Price Calculation Status did not change, the Order should not be reprocessed' );
    }

    // ---------------------------------------------------------------------------------
    // Helper methods
    // ---------------------------------------------------------------------------------

    private static Id getAccountId() {
        return [SELECT Id FROM Account LIMIT 1].Id;
    }

    private static PricebookEntry getPricebookEntry() {
        return [SELECT Id, UnitPrice FROM PricebookEntry LIMIT 1];
    }

    /**
     * @description Inserts Orders with the given status and one product each.
     * @param numberOfOrders  Number of Orders
     * @param priceCalcStatus Value of SBQQ__PriceCalcStatus__c
     * @return Inserted Orders
     */
    private static List<Order> insertOrdersWithItems( Integer numberOfOrders, String priceCalcStatus ) {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), numberOfOrders, priceCalcStatus );
        insert orderList;
        insert TestDataFactory.buildOrderItems( orderList, getPricebookEntry() );
        return orderList;
    }
}
