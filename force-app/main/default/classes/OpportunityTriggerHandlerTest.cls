@IsTest
public with sharing class OpportunityTriggerHandlerTest {

    @IsTest
    static void testOpportunityDefaultsProspectAndHot() {
        Account acc = DataGenerator.createTestAccount('Prospect Hot Acc', 'Prospect', 'Hot', true);

        Test.startTest();
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);
        Test.stopTest();

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
        Account acc = DataGenerator.createTestAccount('Other Warm Acc', 'Other', 'Warm', true);

        Test.startTest();
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);
        Test.stopTest();

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
        Account acc = DataGenerator.createTestAccount('Prospect Acc', 'Prospect', 'Cold', true);
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);

        Test.startTest();
        opp.StageName = 'Closed Won';
        update opp;
        Test.stopTest();

        Account queriedAcc = [SELECT Type FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Customer - Direct', queriedAcc.Type, 'La cuenta debería haber cambiado a Customer - Direct');
    }

    @IsTest
    static void testPushChangesToQuotes() {
        Account acc = DataGenerator.createTestAccount('Push Acc', 'Prospect', 'Cold', true);
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);
        Quote__c q = DataGenerator.createTestQuote(opp.Id, acc.Id, 'Draft', true);

        Test.startTest();
        opp.Customer_Type__c = 'End Customer'; 
        opp.Priority__c = 'High';
        update opp;
        Test.stopTest();

        Quote__c queriedQuote = [SELECT Discount__c FROM Quote__c WHERE Id = :q.Id];
        System.assertEquals(20, queriedQuote.Discount__c, 'El descuento debió actualizarse a 20% gracias al empujón de la Oportunidad');
    }

    @IsTest
    static void testFutureUserIncrementOnClosedWon() {
        Account acc = DataGenerator.createTestAccount('Test Future Acc', 'Prospect', 'Medium', true);
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);
        Id currentOwnerId = UserInfo.getUserId();

        User currentUser = [SELECT Number_of_Won_Opportunities__c FROM User WHERE Id = :currentOwnerId];
        Decimal initialCount = currentUser.Number_of_Won_Opportunities__c != null ? currentUser.Number_of_Won_Opportunities__c : 0;

        Test.startTest();
        opp.StageName = 'Closed Won';
        update opp; 
        Test.stopTest(); 

        User updatedUser = [SELECT Number_of_Won_Opportunities__c FROM User WHERE Id = :currentOwnerId];
        System.assertEquals(initialCount + 1, updatedUser.Number_of_Won_Opportunities__c, 'El contador de oportunidades ganadas debió subir 1');
    }
} 