/**
 * @description Tests del DEV #4: ActiveSubscriptionRecountBatch (camino nocturno).
 *              En un test, el Batch corre completo en Test.stopTest() y su execute() se
 *              ejecuta una sola vez (por eso el bulk usa 200 Contracts, el tamaño de una tanda).
 */
@IsTest
private class ActiveSubscriptionRecountBatchTest {

    private static final Integer BULK_SIZE = 200;

    /**
     * @description Datos comunes: una Account y un producto.
     */
    @testSetup
    static void setup() {
        TestDataFactory.createAccount();
        TestDataFactory.createProduct();
    }

    /**
     * @description El problema del tiempo: la Subscription vence SIN que nadie la edite (acá se
     *              simula moviendo el Contract al pasado: la Subscription toma la fecha de fin del
     *              Contract). El trigger no se entera y el Contract sigue diciendo 1 -> el Batch
     *              lo corrige a 0.
     */
    @isTest
    static void expiredByTimeTest() {
        Contract con = TestDataFactory.createContract( getAccountId(), Date.today(), 12 );
        insert TestDataFactory.buildSubscriptions( con.Id, getProductId(), 1, 125 );
        System.assertEquals( 1, getActiveCount( con.Id ), 'Antes del vencimiento debería contar 1' );

        // Contract de 1 mes que empezó hace 60 días: ya terminó, y la Subscription con él
        con.StartDate = Date.today().addDays( -60 );
        con.ContractTerm = 1;
        update con;
        System.assertEquals( 1, getActiveCount( con.Id ),
            'Sin el Batch el número queda desactualizado (por eso hace falta el job nocturno)' );

        Test.startTest();
        Database.executeBatch( new ActiveSubscriptionRecountBatch() );
        Test.stopTest();

        System.assertEquals( 0, getActiveCount( con.Id ),
            'El Batch debería detectar que la Subscription venció y dejar el Contract en 0' );
    }

    /**
     * @description Backfill / corrección: el Contract tiene un número incorrecto (7) -> el Batch
     *              lo deja en el valor real (1).
     */
    @isTest
    static void fixWrongCountTest() {
        Contract con = TestDataFactory.createContract( getAccountId(), Date.today(), 12 );
        insert TestDataFactory.buildSubscriptions( con.Id, getProductId(), 1, 125 );
        update new Contract( Id = con.Id, Active_Subscriptions__c = 7 );

        Test.startTest();
        Database.executeBatch( new ActiveSubscriptionRecountBatch() );
        Test.stopTest();

        System.assertEquals( 1, getActiveCount( con.Id ), 'El Batch debería corregir el número a 1' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'No debería generarse ningún Error Log' );
    }

    /**
     * @description Bulk: 200 Contracts sin Subscriptions con un número viejo (5) -> los 200 quedan en 0.
     */
    @isTest
    static void bulkRecountTest() {
        // La query va afuera del for: adentro serían 200 queries y se pasa del límite de 100
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
        System.assertEquals( BULK_SIZE, zeroCount, 'Los 200 Contracts sin Subscriptions deberían quedar en 0' );
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
