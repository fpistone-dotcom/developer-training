/**
 * @description Tests del DEV #3 (Parte 1): ContractTrigger y ContractTriggerHandler.
 *              Verifican NUESTRA parte: que SBQQ__RenewalForecast__c se tilde cuando el Status
 *              cambia a Activated. La Renewal Opportunity la genera CPQ (código del paquete),
 *              y eso se prueba en el org, no en un test unitario.
 */
@IsTest
private class ContractTriggerHandlerTest {

    private static final Integer BULK_SIZE = 200;

    /**
     * @description Datos comunes para todos los tests: una Account.
     */
    @testSetup
    static void setup() {
        TestDataFactory.createAccount();
    }

    /**
     * @description Positivo: un Contract en Draft que se activa queda con Renewal Forecast tildado.
     */
    @isTest
    static void activationSetsRenewalForecastTest() {
        Contract con = TestDataFactory.createContract( getAccountId(), Date.today(), 12 );

        Test.startTest();
        con.Status = ContractTriggerHandler.STATUS_ACTIVATED;
        update con;
        Test.stopTest();

        System.assertEquals( true, getContract( con.Id ).SBQQ__RenewalForecast__c,
            'Al activarse, el Contract debería quedar con Renewal Forecast tildado' );
    }

    /**
     * @description Bulk: 200 Contracts activados juntos quedan todos con Renewal Forecast tildado.
     *
     *              SBQQ.TriggerControl.disable() (API del paquete CPQ, fuera del curso): apaga los
     *              triggers de CPQ SOLO en este test. Sin eso, SBQQ.ContractAfter intenta generar
     *              200 Renewal Opportunities y rompe el límite de queries DENTRO del código de CPQ
     *              ("SBQQ: Too many SOQL queries: 101"); nuestro trigger usa 0 queries. Este test
     *              mide que NUESTRO código aguante 200 registros. Lo que genera CPQ se probó en el
     *              org, y los tests no bulk corren con CPQ prendido.
     */
    @isTest
    static void activationBulkTest() {
        List<Contract> contractList = TestDataFactory.buildContracts( getAccountId(), Date.today(), 12, BULK_SIZE );
        insert contractList;
        SBQQ.TriggerControl.disable();

        Test.startTest();
        for ( Contract con : contractList ) {
            con.Status = ContractTriggerHandler.STATUS_ACTIVATED;
        }
        update contractList;
        Test.stopTest();

        Integer forecastCount = [
            SELECT COUNT()
            FROM Contract
            WHERE SBQQ__RenewalForecast__c = true
        ];
        System.assertEquals( BULK_SIZE, forecastCount, 'Los 200 Contracts activados deberían tener Renewal Forecast tildado' );
    }

    /**
     * @description Negativo: si el Status pasa a otro valor (In Approval Process), no se tilda.
     */
    @isTest
    static void otherStatusDoesNotSetForecastTest() {
        Contract con = TestDataFactory.createContract( getAccountId(), Date.today(), 12 );

        Test.startTest();
        con.Status = 'In Approval Process';
        update con;
        Test.stopTest();

        System.assertEquals( false, getContract( con.Id ).SBQQ__RenewalForecast__c,
            'Si el Contract no se activa, Renewal Forecast no debería tildarse' );
    }

    /**
     * @description Negativo: si se edita otro campo y el Status no cambia, no se tilda.
     */
    @isTest
    static void otherFieldUpdateDoesNotSetForecastTest() {
        Contract con = TestDataFactory.createContract( getAccountId(), Date.today(), 12 );

        Test.startTest();
        con.Description = 'Edited';
        update con;
        Test.stopTest();

        System.assertEquals( false, getContract( con.Id ).SBQQ__RenewalForecast__c,
            'Editar otro campo no debería tildar Renewal Forecast' );
    }

    /**
     * @description Negativo: un Contract ya activado al que alguien le destilda Renewal Forecast
     *              y después lo edita no se vuelve a tildar (el Status no cambió).
     */
    @isTest
    static void alreadyActivatedNotReprocessedTest() {
        Contract con = TestDataFactory.createContract( getAccountId(), Date.today(), 12 );
        con.Status = ContractTriggerHandler.STATUS_ACTIVATED;
        update con;
        con.SBQQ__RenewalForecast__c = false;
        update con;

        Test.startTest();
        con.Description = 'Edited after activation';
        update con;
        Test.stopTest();

        System.assertEquals( false, getContract( con.Id ).SBQQ__RenewalForecast__c,
            'Si el Status no cambió en esta transacción, el trigger no debería volver a tildar el flag' );
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    private static Id getAccountId() {
        return [SELECT Id FROM Account LIMIT 1].Id;
    }

    private static Contract getContract( Id contractId ) {
        return [SELECT Id, Status, SBQQ__RenewalForecast__c FROM Contract WHERE Id = :contractId];
    }
}
