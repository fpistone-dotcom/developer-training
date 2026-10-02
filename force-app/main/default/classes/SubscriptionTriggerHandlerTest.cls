/**
 * @description Tests del DEV #4: SubscriptionTrigger + SubscriptionTriggerHandler.
 *              Prueban los 4 contextos (insert, update, delete, undelete), el cambio de Contract
 *              y el caso bulk. La regla de "activa" se prueba en ActiveSubscriptionCounterTest.
 */
@IsTest
private class SubscriptionTriggerHandlerTest {

    private static final Integer BULK_SIZE = 200;

    /**
     * @description Datos comunes: una Account, un producto y dos Contracts vigentes (A y B).
     */
    @testSetup
    static void setup() {
        Account acc = TestDataFactory.createAccount();
        TestDataFactory.createProduct();
        TestDataFactory.createContract( acc.Id, Date.today(), 12 );
        TestDataFactory.createContract( acc.Id, Date.today(), 24 );
    }

    /**
     * @description after insert: 2 Subscriptions en A y 1 en B, en el mismo insert -> A = 2, B = 1.
     */
    @isTest
    static void insertTest() {
        List<SBQQ__Subscription__c> subList = TestDataFactory.buildSubscriptions( getContractAId(), getProductId(), 2, 10 );
        subList.addAll( TestDataFactory.buildSubscriptions( getContractBId(), getProductId(), 1, 10 ) );

        Test.startTest();
        insert subList;
        Test.stopTest();

        System.assertEquals( 2, getActiveCount( getContractAId() ), 'El Contract A debería tener 2 activas' );
        System.assertEquals( 1, getActiveCount( getContractBId() ), 'El Contract B debería tener 1 activa' );
    }

    /**
     * @description after update (cambio relevante): se termina la Subscription hoy -> pasa de 1 a 0.
     */
    @isTest
    static void updateRelevantFieldTest() {
        List<SBQQ__Subscription__c> subList = insertSubscriptions( getContractAId(), 1 );

        Test.startTest();
        subList[0].SBQQ__TerminatedDate__c = Date.today();
        update subList;
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( getContractAId() ),
            'Al terminarla hoy, la Subscription debería dejar de contar' );
    }

    /**
     * @description Negativo, after update sin cambio relevante: cambia solo el precio -> no se
     *              recalcula. Para comprobarlo, antes se pone a mano un número "incorrecto" (99)
     *              en el Contract: si el trigger recalculara, lo corregiría a 1.
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
            'Un cambio de precio no afecta el conteo, así que no debería recalcularse' );
    }

    /**
     * @description after update, caso especial: la Subscription se mueve de A a B -> se
     *              recalculan los dos: A pierde una (0) y B gana una (1).
     */
    @isTest
    static void moveToAnotherContractTest() {
        List<SBQQ__Subscription__c> subList = insertSubscriptions( getContractAId(), 1 );

        Test.startTest();
        subList[0].SBQQ__Contract__c = getContractBId();
        update subList;
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( getContractAId() ), 'El Contract viejo (A) debería quedar en 0' );
        System.assertEquals( 1, getActiveCount( getContractBId() ), 'El Contract nuevo (B) debería quedar en 1' );
    }

    /**
     * @description after delete: se borra una de dos Subscriptions -> pasa de 2 a 1.
     */
    @isTest
    static void deleteTest() {
        List<SBQQ__Subscription__c> subList = insertSubscriptions( getContractAId(), 2 );

        Test.startTest();
        delete subList[0];
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( getContractAId() ),
            'La Subscription borrada debería dejar de contar' );
    }

    /**
     * @description after undelete: se borra y se recupera de la papelera -> vuelve a 1.
     */
    @isTest
    static void undeleteTest() {
        List<SBQQ__Subscription__c> subList = insertSubscriptions( getContractAId(), 1 );
        delete subList;

        Test.startTest();
        undelete subList;
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( getContractAId() ),
            'La Subscription recuperada debería volver a contar' );
    }

    /**
     * @description Negativo: una Subscription sin Contract no rompe nada ni genera errores.
     */
    @isTest
    static void subscriptionWithoutContractTest() {
        Test.startTest();
        insert TestDataFactory.buildSubscriptions( null, getProductId(), 1, 10 );
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( getContractAId() ), 'Los Contracts no deberían cambiar' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'No debería generarse ningún Error Log' );
    }

    /**
     * @description Bulk: 200 Subscriptions en un solo insert -> 200, sin pasarse de los límites
     *              (el recuento hace 1 query y 1 update para todo el lote).
     */
    @isTest
    static void bulkInsertTest() {
        List<SBQQ__Subscription__c> subList = TestDataFactory.buildSubscriptions( getContractAId(), getProductId(), BULK_SIZE, 1 );

        Test.startTest();
        insert subList;
        Test.stopTest();

        System.assertEquals( BULK_SIZE, getActiveCount( getContractAId() ),
            'Las 200 Subscriptions deberían contar' );
    }

    /**
     * @description Bulk: se borran las 200 en un solo delete -> 0.
     */
    @isTest
    static void bulkDeleteTest() {
        List<SBQQ__Subscription__c> subList = insertSubscriptions( getContractAId(), BULK_SIZE );

        Test.startTest();
        delete subList;
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( getContractAId() ),
            'Al borrar las 200 el Contract debería quedar en 0' );
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

    // A = plazo de 12 meses, B = plazo de 24 meses (así se distinguen)
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
