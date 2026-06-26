@IsTest
public with sharing class OpportunityTriggerHandlerTest {

    @IsTest
    static void testOpportunityDefaultsProspectAndHot() {
        // 1. CREACIÓN DE DATOS: Cuenta Prospect y Hot
        Account acc = DataGenerator.createTestAccount('Prospect Hot Acc', 'Prospect', 'Hot', true);

        // 2. EJECUCIÓN: Insertar Oportunidad vinculada
        Test.startTest();
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);
        Test.stopTest();

        // 3. VALIDACIÓN (Aserciones): Verificar que el Trigger hizo su trabajo
        Opportunity queriedOpp = [
            SELECT Type, Customer_Type__c, Priority__c 
            FROM Opportunity 
            WHERE Id = :opp.Id
        ];

        System.assertEquals('New Customer', queriedOpp.Type, 'El tipo de Opp debería ser New Customer para cuentas Prospect');
        System.assertEquals('End Customer', queriedOpp.Customer_Type__c, 'El Customer Type por defecto debe ser End Customer');
        System.assertEquals('High', queriedOpp.Priority__c, 'La prioridad debería ser High para cuentas Hot');
    }

    @IsTest
    static void testOpportunityDefaultsOtherAndWarm() {
        // 1. CREACIÓN DE DATOS: Cuenta con otro tipo y Rating Warm
        Account acc = DataGenerator.createTestAccount('Other Warm Acc', 'Other', 'Warm', true);

        // 2. EJECUCIÓN: Insertar Oportunidad vinculada
        Test.startTest();
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);
        Test.stopTest();

        // 3. VALIDACIÓN: Verificar las asignaciones alternativas
        Opportunity queriedOpp = [
            SELECT Type, Customer_Type__c, Priority__c 
            FROM Opportunity 
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Existing Customer - Upgrade', queriedOpp.Type, 'Debería ser Existing Customer - Upgrade si la cuenta no es Prospect');
        System.assertEquals('Medium', queriedOpp.Priority__c, 'La prioridad debería ser Medium para cuentas Warm');
    }

    @IsTest
    static void testUpdateAccountToClosedWon() {
        // 1. CREACIÓN DE DATOS: Cuenta Prospect y Opp en Qualification
        Account acc = DataGenerator.createTestAccount('Prospect Acc', 'Prospect', 'Cold', true);
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);

        // 2. EJECUCIÓN: Cambiar la Opp a Closed Won para disparar el afterUpdate
        Test.startTest();
        opp.StageName = 'Closed Won';
        update opp;
        Test.stopTest();

        // 3. VALIDACIÓN: Verificar que la cuenta se actualizó
        Account queriedAcc = [SELECT Type FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Customer - Direct', queriedAcc.Type, 'La cuenta debería haber cambiado a Customer - Direct');
    }

    @IsTest
    static void testPushChangesToQuotes() {
        // 1. CREACIÓN DE DATOS: Cuenta, Opp, y una Quote hija en estado Draft
        Account acc = DataGenerator.createTestAccount('Push Acc', 'Prospect', 'Cold', true);
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);
        Quote__c q = DataGenerator.createTestQuote(opp.Id, acc.Id, 'Draft', true);

        // 2. EJECUCIÓN: Cambiamos la prioridad en la Oportunidad de Low a High.
        // Esto disparará el pushChangesToDraftQuotes, que despertará a la Quote,
        // la cual ejecutará su propio trigger de descuentos y pasará del 0% al 20%.
        Test.startTest();
        opp.Customer_Type__c = 'End Customer'; 
        opp.Priority__c = 'High';
        update opp;
        Test.stopTest();

        // 3. VALIDACIÓN: Si el empujón funcionó, la Quote en Draft se recalcula
        Quote__c queriedQuote = [SELECT Discount__c FROM Quote__c WHERE Id = :q.Id];
        System.assertEquals(20, queriedQuote.Discount__c, 'El descuento debió actualizarse a 20% gracias al empujón de la Oportunidad');
    }
}