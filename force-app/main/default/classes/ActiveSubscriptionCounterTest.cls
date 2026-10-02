/**
 * @description Tests del DEV #4: ActiveSubscriptionCounter, la regla de "activa" y los Amendments.
 *              Las Subscriptions se insertan de verdad, así que el SubscriptionTrigger llama al
 *              recuento solo (es el camino real). Al final se lee el número guardado en el Contract.
 *
 *              Las revisiones de Amendment se arman igual que las que creó CPQ en el org:
 *              un registro nuevo por la diferencia (+100 / -10), con SBQQ__RevisedSubscription__c
 *              apuntando a la Subscription original.
 */
@IsTest
private class ActiveSubscriptionCounterTest {

    private static final Date TODAY = Date.today();

    /**
     * @description Datos comunes: una Account, un producto y un Contract de 12 meses que empieza hoy.
     */
    @testSetup
    static void setup() {
        Account acc = TestDataFactory.createAccount();
        TestDataFactory.createProduct();
        TestDataFactory.createContract( acc.Id, TODAY, 12 );
    }

    // ---------------------------------------------------------------------------------
    // Definición de "activa" (fechas y terminación)
    // ---------------------------------------------------------------------------------

    /**
     * @description Positivo: Subscription sin fechas propias (toma las del Contract, vigente) -> cuenta 1.
     */
    @isTest
    static void activeSubscriptionCountsTest() {
        Test.startTest();
        insert TestDataFactory.buildSubscriptions( getContractId(), getProductId(), 1, 125 );
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( getContractId() ),
            'Una Subscription vigente debería contar 1' );
    }

    /**
     * @description Negativo: Subscription que empieza mañana -> todavía no cuenta.
     */
    @isTest
    static void futureSubscriptionNotCountedTest() {
        List<SBQQ__Subscription__c> subList = TestDataFactory.buildSubscriptions( getContractId(), getProductId(), 1, 125 );
        subList[0].SBQQ__SubscriptionStartDate__c = TODAY.addDays( 1 );

        Test.startTest();
        insert subList;
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( getContractId() ),
            'Una Subscription que empieza mañana no debería contar hoy' );
    }

    /**
     * @description Negativo y borde: una vencida ayer no cuenta; una que vence HOY todavía cuenta.
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
            'Solo debería contar la que vence hoy: la vencida ayer ya no está activa' );
    }

    /**
     * @description Negativo y borde: terminada hoy no cuenta; terminada a partir de mañana todavía cuenta.
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
            'Solo debería contar la que se termina mañana: la terminada hoy ya no está activa' );
    }

    /**
     * @description Positivo: Contract evergreen (sin plazo ni fecha de fin) -> la Subscription cuenta.
     */
    @isTest
    static void evergreenContractTest() {
        Contract evergreenContract = TestDataFactory.createContract( getAccountId(), TODAY, null );

        Test.startTest();
        insert TestDataFactory.buildSubscriptions( evergreenContract.Id, getProductId(), 1, 5 );
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( evergreenContract.Id ),
            'Sin fecha de fin la Subscription no vence, así que debería contar' );
    }

    // ---------------------------------------------------------------------------------
    // Amendments (opción C: una por Subscription original con cantidad neta > 0)
    // ---------------------------------------------------------------------------------

    /**
     * @description Caso de la demo: original 125, Amendment +100 y Amendment -10, ya vigentes
     *              -> 125 + 100 - 10 = 215 > 0 -> cuenta 1 (no 3).
     */
    @isTest
    static void amendmentRevisionsCountOnceTest() {
        SBQQ__Subscription__c original = insertOriginal( 125 );

        Test.startTest();
        insert buildRevision( original.Id, 100, TODAY );
        insert buildRevision( original.Id, -10, TODAY );
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( getContractId() ),
            'Las revisiones de Amendment cambian la cantidad de la original: debería contar 1, no 3' );
    }

    /**
     * @description Negativo: un Amendment baja la cantidad a 0 (125 - 125) -> deja de contar.
     */
    @isTest
    static void fullCancellationNotCountedTest() {
        SBQQ__Subscription__c original = insertOriginal( 125 );

        Test.startTest();
        insert buildRevision( original.Id, -125, TODAY );
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( getContractId() ),
            'Con cantidad neta 0 la Subscription ya no está activa' );
    }

    /**
     * @description Borde: la baja total empieza mañana -> hoy la Subscription todavía cuenta.
     */
    @isTest
    static void futureCancellationStillCountsTest() {
        SBQQ__Subscription__c original = insertOriginal( 125 );

        Test.startTest();
        insert buildRevision( original.Id, -125, TODAY.addDays( 1 ) );
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( getContractId() ),
            'La baja todavía no empezó: hoy la Subscription sigue activa' );
    }

    // ---------------------------------------------------------------------------------
    // Eficiencia
    // ---------------------------------------------------------------------------------

    /**
     * @description Negativo: sin Contracts no se gasta ninguna query.
     */
    @isTest
    static void emptySetSkipsQueryTest() {
        Test.startTest();
        ActiveSubscriptionCounter.recountActiveSubscriptions( new Set<Id>() );
        Integer queryCount = Limits.getQueries();
        Test.stopTest();

        System.assertEquals( 0, queryCount, 'Con un Set vacío no debería hacerse ninguna query' );
    }

    /**
     * @description Negativo: si el número guardado ya es el correcto, no se hace update.
     */
    @isTest
    static void unchangedCountSkipsUpdateTest() {
        insert TestDataFactory.buildSubscriptions( getContractId(), getProductId(), 1, 125 );

        Test.startTest();
        ActiveSubscriptionCounter.recountActiveSubscriptions( new Set<Id>{ getContractId() } );
        Integer dmlCount = Limits.getDmlStatements();
        Test.stopTest();

        System.assertEquals( 0, dmlCount, 'Si el número no cambió no debería hacerse ningún update' );
        System.assertEquals( 1, getActiveCount( getContractId() ), 'El número debería seguir en 1' );
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    private static SBQQ__Subscription__c insertOriginal( Decimal quantity ) {
        List<SBQQ__Subscription__c> subList = TestDataFactory.buildSubscriptions( getContractId(), getProductId(), 1, quantity );
        insert subList;
        return subList[0];
    }

    // Revisión de Amendment: misma estructura que las que creó CPQ en el org (SUB-0000012 / 13)
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

    // El Contract del @testSetup es el único con plazo de 12 meses
    private static Id getContractId() {
        return [SELECT Id FROM Contract WHERE ContractTerm = 12 LIMIT 1].Id;
    }

    private static Decimal getActiveCount( Id contractId ) {
        return [SELECT Active_Subscriptions__c FROM Contract WHERE Id = :contractId].Active_Subscriptions__c;
    }
}
