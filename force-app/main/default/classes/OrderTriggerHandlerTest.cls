/**
 * @description Tests del DEV #2: OrderTrigger, OrderTriggerHandler y OrderActivationQueueable.
 *              Cubre casos positivos, negativos y bulk (200 registros) de los dos caminos:
 *              - Insert: la activación la hace el Queueable, que en un test corre en Test.stopTest().
 *              - Update: la activación ocurre en el momento (before update).
 */
@IsTest
private class OrderTriggerHandlerTest {

    private static final Integer BULK_SIZE = 200;

    /**
     * @description Datos comunes para todos los tests: una Account y un producto con precio.
     */
    @testSetup
    static void setup() {
        TestDataFactory.createAccount();
        TestDataFactory.createPricebookEntry();
    }

    // ---------------------------------------------------------------------------------
    // Camino INSERT (Req B)
    // ---------------------------------------------------------------------------------

    /**
     * @description Positivo: una Order que se crea con 'Not Needed' y tiene productos
     *              queda activada cuando corre el Queueable.
     */
    @isTest
    static void activateOnInsertTest() {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), 1, 'Not Needed' );

        Test.startTest();
        insert orderList;
        insert TestDataFactory.buildOrderItems( orderList, getPricebookEntry() );
        Test.stopTest(); // acá corre el Queueable

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Activated', result.Status, 'La Order creada con Not Needed y con productos debería quedar Activated' );
    }

    /**
     * @description Bulk: 200 Orders creadas juntas se activan con un solo Queueable.
     */
    @isTest
    static void activateOnInsertBulkTest() {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), BULK_SIZE, 'Not Needed' );

        Test.startTest();
        insert orderList;
        insert TestDataFactory.buildOrderItems( orderList, getPricebookEntry() );
        Test.stopTest();

        Integer activatedCount = [SELECT COUNT() FROM Order WHERE Status = 'Activated'];
        System.assertEquals( BULK_SIZE, activatedCount, 'Las 200 Orders deberían quedar Activated' );
    }

    /**
     * @description Negativo: una Order creada con un status que no está listo ('Queued')
     *              no se activa.
     */
    @isTest
    static void notActivatedOnInsertWhenNotReadyTest() {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), 1, 'Queued' );

        Test.startTest();
        insert orderList;
        insert TestDataFactory.buildOrderItems( orderList, getPricebookEntry() );
        Test.stopTest();

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Draft', result.Status, 'Una Order con status Queued no debería activarse' );
    }

    /**
     * @description Negativo: una Order creada con 'Not Needed' pero sin productos no se
     *              activa (Salesforce no lo permite y el Queueable la saltea).
     */
    @isTest
    static void notActivatedOnInsertWithoutItemsTest() {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), 1, 'Not Needed' );

        Test.startTest();
        insert orderList;
        Test.stopTest();

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Draft', result.Status, 'Una Order sin productos no debería activarse' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'No debería registrarse ningún error: la Order se saltea, no falla' );
    }

    /**
     * @description Edge case: si ya no se pueden encolar más Queueables, no se rompe la
     *              creación de la Order y se registra un Error Log.
     */
    @isTest
    static void logErrorWhenQueueableLimitReachedTest() {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), 1, 'Not Needed' );

        Test.startTest();
        // Llenamos el cupo de Queueables de la transacción con jobs vacíos
        Integer queueableLimit = Limits.getLimitQueueableJobs();
        for ( Integer i = 0; i < queueableLimit; i++ ) {
            System.enqueueJob( new OrderActivationQueueable( new Set<Id>() ) );
        }
        insert orderList;
        Test.stopTest();

        // WITH SYSTEM_MODE: el test verifica el log sin depender de los permisos del usuario que corre el test
        List<Error_Log__c> errorLogList = [SELECT Class_Name__c, Record_Id__c FROM Error_Log__c WITH SYSTEM_MODE];
        System.assertEquals( 1, errorLogList.size(), 'Debería registrarse un Error Log por la Order que no se pudo encolar' );
        System.assertEquals( 'OrderTriggerHandler', errorLogList[0].Class_Name__c, 'El log debería indicar la clase que lo generó' );
        System.assertEquals( orderList[0].Id, errorLogList[0].Record_Id__c, 'El log debería apuntar a la Order afectada' );
    }

    /**
     * @description Edge case: si Salesforce rechaza la activación dentro del Queueable,
     *              la Order queda en Draft y el error se registra en Error_Log__c.
     *              Para provocar la falla, la Order se vincula a un Contract que no está
     *              activado: Salesforce no permite activar una Order en ese caso.
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
        Test.stopTest(); // acá corre el Queueable y la activación falla

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Draft', result.Status, 'La Order no debería activarse si Salesforce rechaza la activación' );

        List<Error_Log__c> errorLogList = [SELECT Class_Name__c, Record_Id__c FROM Error_Log__c WITH SYSTEM_MODE];
        System.assertEquals( 1, errorLogList.size(), 'Debería registrarse un Error Log por la activación fallida' );
        System.assertEquals( 'OrderActivationQueueable', errorLogList[0].Class_Name__c, 'El log debería indicar que falló en el Queueable' );
        System.assertEquals( orderList[0].Id, errorLogList[0].Record_Id__c, 'El log debería apuntar a la Order que no se pudo activar' );
    }

    // ---------------------------------------------------------------------------------
    // Camino UPDATE (Req C)
    // ---------------------------------------------------------------------------------

    /**
     * @description Positivo: una Order con productos cuyo status pasa de 'Queued' a
     *              'Completed' queda activada en el momento.
     */
    @isTest
    static void activateOnUpdateTest() {
        List<Order> orderList = insertOrdersWithItems( 1, 'Queued' );

        Test.startTest();
        orderList[0].SBQQ__PriceCalcStatus__c = 'Completed';
        update orderList;
        Test.stopTest();

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Activated', result.Status, 'La Order debería activarse al pasar a Completed' );
    }

    /**
     * @description Bulk: 200 Orders que pasan a 'Completed' en un mismo update se activan todas.
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
        System.assertEquals( BULK_SIZE, activatedCount, 'Las 200 Orders deberían quedar Activated' );
    }

    /**
     * @description Negativo: si el status cambia a un valor que no está listo ('Failed'),
     *              la Order no se activa.
     */
    @isTest
    static void notActivatedOnUpdateToNotReadyValueTest() {
        List<Order> orderList = insertOrdersWithItems( 1, 'Queued' );

        Test.startTest();
        orderList[0].SBQQ__PriceCalcStatus__c = 'Failed';
        update orderList;
        Test.stopTest();

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Draft', result.Status, 'Una Order que pasa a Failed no debería activarse' );
    }

    /**
     * @description Negativo: si el status pasa a 'Completed' pero la Order no tiene
     *              productos, no se activa y el guardado no falla.
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
        System.assertEquals( 'Draft', result.Status, 'Una Order sin productos no debería activarse' );
    }

    /**
     * @description Negativo: si se edita otro campo y el Price Calculation Status no cambia,
     *              la Order no se reprocesa aunque ya tenga un valor listo.
     */
    @isTest
    static void notActivatedWhenPriceCalcStatusDidNotChangeTest() {
        // Order en Draft con 'Completed' y sin productos: el update a Completed no la activa
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), 1, 'Queued' );
        insert orderList;
        orderList[0].SBQQ__PriceCalcStatus__c = 'Completed';
        update orderList;
        // Ahora le agregamos productos, sin tocar el status
        insert TestDataFactory.buildOrderItems( orderList, getPricebookEntry() );

        Test.startTest();
        orderList[0].Description = 'Edited description';
        update orderList;
        Test.stopTest();

        Order result = [SELECT Status FROM Order WHERE Id = :orderList[0].Id];
        System.assertEquals( 'Draft', result.Status, 'Si el Price Calculation Status no cambió, la Order no debería reprocesarse' );
    }

    // ---------------------------------------------------------------------------------
    // Métodos de ayuda
    // ---------------------------------------------------------------------------------

    private static Id getAccountId() {
        return [SELECT Id FROM Account LIMIT 1].Id;
    }

    private static PricebookEntry getPricebookEntry() {
        return [SELECT Id, UnitPrice FROM PricebookEntry LIMIT 1];
    }

    /**
     * @description Inserta Orders con el status indicado y un producto cada una.
     * @param numberOfOrders  Cantidad de Orders
     * @param priceCalcStatus Valor de SBQQ__PriceCalcStatus__c
     * @return Orders insertadas
     */
    private static List<Order> insertOrdersWithItems( Integer numberOfOrders, String priceCalcStatus ) {
        List<Order> orderList = TestDataFactory.buildOrders( getAccountId(), numberOfOrders, priceCalcStatus );
        insert orderList;
        insert TestDataFactory.buildOrderItems( orderList, getPricebookEntry() );
        return orderList;
    }
}
