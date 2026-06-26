@IsTest
public with sharing class QuoteTriggerHandlerTest {

    @IsTest
    static void testQuoteAutoDiscountEndCustomer() {
        Account acc = DataGenerator.createTestAccount('End Customer Acc', 'Prospect', 'Medium', true);
        
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', false);
        opp.Customer_Type__c = 'End Customer';
        opp.Priority__c = 'High';
        
        Contact con = new Contact(LastName = 'Perez', AccountId = acc.Id, MailingStreet = 'Av. Siempreviva 742');
        insert con;
        opp.Ship_To_Override__c = con.Id;
        insert opp;

        Test.startTest();
        Quote__c q = DataGenerator.createTestQuote(opp.Id, acc.Id, 'Draft', true);
        Test.stopTest();

        Quote__c queriedQuote = [SELECT Discount__c, Ship_To__c, Ship_To_Approval_Required__c FROM Quote__c WHERE Id = :q.Id];
        System.assertEquals(20, queriedQuote.Discount__c);
    }

    @IsTest
    static void testQuoteAutoDiscountPartnerAndDistributor() {
        Account acc = DataGenerator.createTestAccount('Bulk Acc', 'Prospect', 'Medium', true);
        
        Opportunity oppPartner = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);
        Opportunity oppDist = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);

        oppPartner.Customer_Type__c = 'Partner';
        oppPartner.Priority__c = 'Medium';
        update oppPartner;

        oppDist.Customer_Type__c = 'Distributor';
        oppDist.Priority__c = 'Low';
        update oppDist;

        Test.startTest();
        Quote__c qPartner = DataGenerator.createTestQuote(oppPartner.Id, acc.Id, 'Draft', true);
        Quote__c qDist = DataGenerator.createTestQuote(oppDist.Id, acc.Id, 'Draft', true);
        
        qPartner.Status__c = 'Approved';
        update qPartner;
        Test.stopTest();

        Quote__c queriedPartner = [SELECT Discount__c FROM Quote__c WHERE Id = :qPartner.Id];
        Quote__c queriedDist = [SELECT Discount__c FROM Quote__c WHERE Id = :qDist.Id];
        
        System.assertEquals(15, queriedPartner.Discount__c);
        System.assertEquals(5, queriedDist.Discount__c);
    }

    @IsTest
    static void testQuoteNoShipTo() {
        Account acc = DataGenerator.createTestAccount('No Ship To Acc', 'Prospect', 'Low', true);
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);

        Test.startTest();
        Quote__c q = DataGenerator.createTestQuote(opp.Id, acc.Id, 'Draft', true);
        Test.stopTest();

        Quote__c queriedQuote = [SELECT Ship_To_Approval_Required__c FROM Quote__c WHERE Id = :q.Id];
        System.assertEquals(true, queriedQuote.Ship_To_Approval_Required__c);
    }

    // 🌟 ¡MÉTODO NUEVO NUEVO PARA FORZAR EL BORRADO Y SUBIR COBERTURA!
    @IsTest
    static void testQuoteDeleteAndUndelete() {
        Account acc = DataGenerator.createTestAccount('Delete Acc', 'Prospect', 'Low', true);
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);
        Quote__c q = DataGenerator.createTestQuote(opp.Id, acc.Id, 'Approved', true);

        Test.startTest();
        delete q;   // Dispara el afterDelete en el Handler
        undelete q; // Dispara el afterUndelete en el Handler
        Test.stopTest();
        
        System.assertNotEquals(null, q.Id, 'La cotización debería ser restaurada exitosamente');
    }
}