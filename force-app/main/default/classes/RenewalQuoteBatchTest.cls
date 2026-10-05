/**
 * @description Tests del DEV #3 (Parte 2): RenewalQuoteBatch.
 *              Verifican NUESTRA parte: qué Contracts entran en la ventana de 30 días, que se
 *              tilden los flags de CPQ y que la Renewal Opportunity pase de Prospecting a
 *              'Proposal/Price Quote'. La Renewal Quote la genera CPQ (código del paquete) y eso
 *              se prueba en el org.
 *
 *              Fechas: la EndDate de un Contract la calcula Salesforce (inicio + plazo - 1 día).
 *              createActivatedContracts recibe la EndDate que queremos y calcula el inicio.
 *
 *              En los tests el Batch se lanza con tamaño 200 (y no con BATCH_SIZE = 1): en un
 *              test, execute() corre una sola vez, así que con tamaño 1 solo procesaría un Contract.
 */
@IsTest
private class RenewalQuoteBatchTest {

    private static final Integer BULK_SIZE = 200;
    private static final Integer CONTRACT_TERM = 12;

    /**
     * @description Datos comunes para todos los tests: una Account.
     */
    @testSetup
    static void setup() {
        TestDataFactory.createAccount();
    }

    /**
     * @description Positivo: un Contract activado que vence en 19 días queda con Renewal Quoted
     *              y Renewal Forecast tildados.
     */
    @isTest
    static void contractInWindowQuotedTest() {
        Contract con = createActivatedContracts( Date.today().addDays( 19 ), 1 )[0];

        Test.startTest();
        Database.executeBatch( new RenewalQuoteBatch(), BULK_SIZE );
        Test.stopTest();

        Contract result = getContract( con.Id );
        System.assertEquals( true, result.SBQQ__RenewalQuoted__c,
            'Un Contract que vence dentro de 30 días debería quedar con Renewal Quoted tildado' );
        System.assertEquals( true, result.SBQQ__RenewalForecast__c,
            'Renewal Forecast debería seguir tildado' );
    }

    /**
     * @description Borde: vence hoy y vence en exactamente 30 días -> entran. Vence en 31 días y
     *              venció ayer -> no entran.
     */
    @isTest
    static void windowBoundaryTest() {
        Contract endsToday = createActivatedContracts( Date.today(), 1 )[0];
        Contract endsIn30Days = createActivatedContracts( Date.today().addDays( 30 ), 1 )[0];
        Contract endsIn31Days = createActivatedContracts( Date.today().addDays( 31 ), 1 )[0];
        Contract endedYesterday = createActivatedContracts( Date.today().addDays( -1 ), 1 )[0];

        Test.startTest();
        Database.executeBatch( new RenewalQuoteBatch(), BULK_SIZE );
        Test.stopTest();

        System.assertEquals( true, getContract( endsToday.Id ).SBQQ__RenewalQuoted__c,
            'Un Contract que vence hoy todavía está dentro de la ventana' );
        System.assertEquals( true, getContract( endsIn30Days.Id ).SBQQ__RenewalQuoted__c,
            'Un Contract que vence en exactamente 30 días está dentro de la ventana' );
        System.assertEquals( false, getContract( endsIn31Days.Id ).SBQQ__RenewalQuoted__c,
            'Un Contract que vence en 31 días todavía no entra en la ventana' );
        System.assertEquals( false, getContract( endedYesterday.Id ).SBQQ__RenewalQuoted__c,
            'Un Contract vencido no debería procesarse' );
    }

    /**
     * @description Negativo: un Contract en Draft que vence en 19 días no se procesa.
     */
    @isTest
    static void draftContractNotQuotedTest() {
        Contract con = TestDataFactory.createContract( getAccountId(), getStartDateFor( Date.today().addDays( 19 ) ), CONTRACT_TERM );

        Test.startTest();
        Database.executeBatch( new RenewalQuoteBatch(), BULK_SIZE );
        Test.stopTest();

        System.assertEquals( false, getContract( con.Id ).SBQQ__RenewalQuoted__c,
            'Un Contract que no está activado no debería procesarse' );
    }

    /**
     * @description Negativo: un Contract evergreen (sin fecha de fin) no se procesa.
     */
    @isTest
    static void evergreenContractNotQuotedTest() {
        Contract con = TestDataFactory.createContract( getAccountId(), Date.today().addMonths( -11 ), null );
        con.Status = ContractTriggerHandler.STATUS_ACTIVATED;
        update con;

        Test.startTest();
        Database.executeBatch( new RenewalQuoteBatch(), BULK_SIZE );
        Test.stopTest();

        System.assertEquals( false, getContract( con.Id ).SBQQ__RenewalQuoted__c,
            'Un Contract evergreen no tiene fin, así que no debería procesarse' );
    }

    /**
     * @description Red de seguridad: un Contract activado sin Renewal Forecast (por ejemplo,
     *              activado antes del deploy) queda con los dos flags tildados.
     */
    @isTest
    static void missingForecastSafetyNetTest() {
        Contract con = createActivatedContracts( Date.today().addDays( 19 ), 1 )[0];
        con.SBQQ__RenewalForecast__c = false;
        update con;

        Test.startTest();
        Database.executeBatch( new RenewalQuoteBatch(), BULK_SIZE );
        Test.stopTest();

        Contract result = getContract( con.Id );
        System.assertEquals( true, result.SBQQ__RenewalForecast__c,
            'El Batch debería tildar Renewal Forecast si faltaba' );
        System.assertEquals( true, result.SBQQ__RenewalQuoted__c,
            'El Batch debería tildar Renewal Quoted' );
    }

    /**
     * @description Positivo + negativo: la Renewal Opportunity en Prospecting pasa a
     *              'Proposal/Price Quote'; la que un vendedor ya avanzó no se toca.
     */
    @isTest
    static void opportunityStageUpdatedTest() {
        List<Contract> contractList = createActivatedContracts( Date.today().addDays( 19 ), 2 );
        Opportunity prospectingOpp = TestDataFactory.buildRenewalOpportunities( getAccountId(),
            new List<Contract>{ contractList[0] }, RenewalQuoteBatch.STAGE_PROSPECTING )[0];
        Opportunity advancedOpp = TestDataFactory.buildRenewalOpportunities( getAccountId(),
            new List<Contract>{ contractList[1] }, 'Negotiation/Review' )[0];
        insert new List<Opportunity>{ prospectingOpp, advancedOpp };

        Test.startTest();
        Database.executeBatch( new RenewalQuoteBatch(), BULK_SIZE );
        Test.stopTest();

        System.assertEquals( RenewalQuoteBatch.STAGE_PROPOSAL, getOpportunity( prospectingOpp.Id ).StageName,
            'La Renewal Opportunity en Prospecting debería pasar a Proposal/Price Quote' );
        System.assertEquals( 'Negotiation/Review', getOpportunity( advancedOpp.Id ).StageName,
            'Una Renewal Opportunity que ya avanzó no debería volver atrás' );
        System.assertEquals( 0, [SELECT COUNT() FROM Error_Log__c], 'No debería haber errores' );
    }

    /**
     * @description Negativo (idempotencia): un Contract que ya tiene Renewal Quote no se vuelve
     *              a procesar, así que su Opportunity no se toca.
     */
    @isTest
    static void alreadyQuotedNotReprocessedTest() {
        Contract con = createActivatedContracts( Date.today().addDays( 19 ), 1 )[0];
        con.SBQQ__RenewalQuoted__c = true;
        update con;
        Opportunity opp = TestDataFactory.buildRenewalOpportunities( getAccountId(),
            new List<Contract>{ con }, RenewalQuoteBatch.STAGE_PROSPECTING )[0];
        insert opp;

        Test.startTest();
        Database.executeBatch( new RenewalQuoteBatch(), BULK_SIZE );
        Test.stopTest();

        System.assertEquals( RenewalQuoteBatch.STAGE_PROSPECTING, getOpportunity( opp.Id ).StageName,
            'Un Contract que ya tenía Renewal Quote no debería volver a procesarse' );
    }

    /**
     * @description Bulk: 200 Contracts en la ventana, cada uno con su Renewal Opportunity.
     *
     *              SBQQ.TriggerControl.disable() (API del paquete CPQ, fuera del curso): apaga los
     *              triggers de CPQ SOLO en este test. Sin eso, al activar 200 Contracts (y al tildar
     *              200 Renewal Quoted) CPQ rompe el límite de queries dentro de SU código
     *              ("SBQQ: Too many SOQL queries: 101"). Este test mide NUESTRA bulkificación
     *              (1 query y 2 updates por tanda). Por esto mismo el job real usa tandas de 1.
     */
    @isTest
    static void bulkTest() {
        SBQQ.TriggerControl.disable();
        List<Contract> contractList = createActivatedContracts( Date.today().addDays( 19 ), BULK_SIZE );
        insert TestDataFactory.buildRenewalOpportunities( getAccountId(), contractList, RenewalQuoteBatch.STAGE_PROSPECTING );

        Test.startTest();
        Database.executeBatch( new RenewalQuoteBatch(), BULK_SIZE );
        Test.stopTest();

        Integer quotedCount = [SELECT COUNT() FROM Contract WHERE SBQQ__RenewalQuoted__c = true];
        System.assertEquals( BULK_SIZE, quotedCount, 'Los 200 Contracts deberían quedar con Renewal Quoted tildado' );
        Integer proposalCount = [
            SELECT COUNT()
            FROM Opportunity
            WHERE SBQQ__Renewal__c = true
            AND StageName = :RenewalQuoteBatch.STAGE_PROPOSAL
        ];
        System.assertEquals( BULK_SIZE, proposalCount, 'Las 200 Renewal Opportunities deberían pasar a Proposal/Price Quote' );
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    /**
     * @description Crea Contracts de 12 meses que vencen en la fecha indicada y los activa
     *              (insert en Draft + update del Status, porque no se pueden insertar activados).
     * @param endDate           EndDate que queremos
     * @param numberOfContracts Cantidad de Contracts
     * @return Contracts activados
     */
    private static List<Contract> createActivatedContracts( Date endDate, Integer numberOfContracts ) {
        List<Contract> contractList = TestDataFactory.buildContracts( getAccountId(), getStartDateFor( endDate ),
            CONTRACT_TERM, numberOfContracts );
        insert contractList;
        for ( Contract con : contractList ) {
            con.Status = ContractTriggerHandler.STATUS_ACTIVATED;
        }
        update contractList;
        return contractList;
    }

    /**
     * @description EndDate = inicio + 12 meses - 1 día, así que inicio = (EndDate + 1 día) - 12 meses.
     * @param endDate EndDate que queremos
     * @return Fecha de inicio para un Contract de 12 meses
     */
    private static Date getStartDateFor( Date endDate ) {
        return endDate.addDays( 1 ).addMonths( -CONTRACT_TERM );
    }

    private static Id getAccountId() {
        return [SELECT Id FROM Account LIMIT 1].Id;
    }

    private static Contract getContract( Id contractId ) {
        return [SELECT Id, EndDate, SBQQ__RenewalForecast__c, SBQQ__RenewalQuoted__c FROM Contract WHERE Id = :contractId];
    }

    private static Opportunity getOpportunity( Id opportunityId ) {
        return [SELECT Id, StageName FROM Opportunity WHERE Id = :opportunityId];
    }
}
