@IsTest
public with sharing class QuoteTriggerHandlerTest {

    @IsTest
    static void testQuoteAutoDiscountEndCustomer() {
        // 1. CREACIÓN DE DATOS
        Account acc = DataGenerator.createTestAccount('End Customer Acc', 'Prospect', 'Medium', true);
        
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', false);
        opp.Customer_Type__c = 'End Customer';
        opp.Priority__c = 'High';
        
        // Creamos un contacto con dirección real para probar el requerimiento 2.6.2
        Contact con = new Contact(LastName = 'Perez', AccountId = acc.Id, MailingStreet = 'Av. Siempreviva 742');
        insert con;
        opp.Ship_To_Override__c = con.Id;
        insert opp;

        // 2. EJECUCIÓN
        Test.startTest();
        Quote__c q = DataGenerator.createTestQuote(opp.Id, acc.Id, 'Draft', true);
        Test.stopTest();

        // 3. VALIDACIÓN (Agregamos Watermark_Shown__c y Shipping_Street__c a la consulta)
        Quote__c queriedQuote = [SELECT Discount__c, Watermark_Shown__c, Shipping_Street__c FROM Quote__c WHERE Id = :q.Id];
        
        // Validación original del descuento
        System.assertEquals(20, queriedQuote.Discount__c);
        
        // VALIDACIONES INTEGRADAS:
        System.assertEquals(true, queriedQuote.Watermark_Shown__c, 'La marca de agua debe ser TRUE si está en Draft');
        System.assertEquals('Av. Siempreviva 742', queriedQuote.Shipping_Street__c, 'La calle debió copiarse del Contacto');
    }

    @IsTest
    static void testQuoteAutoDiscountPartnerAndDistributor() {
        // 1. CREACIÓN DE DATOS
        Account acc = DataGenerator.createTestAccount('Bulk Acc', 'Prospect', 'Medium', true);
        
        Opportunity oppPartner = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);
        Opportunity oppDist = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);

        oppPartner.Customer_Type__c = 'Partner';
        oppPartner.Priority__c = 'Medium';
        update oppPartner;

        oppDist.Customer_Type__c = 'Distributor';
        oppDist.Priority__c = 'Low';
        update oppDist;

        // 2. EJECUCIÓN
        Test.startTest();
        Quote__c qPartner = DataGenerator.createTestQuote(oppPartner.Id, acc.Id, 'Draft', true);
        Quote__c qDist = DataGenerator.createTestQuote(oppDist.Id, acc.Id, 'Draft', true);
        
        // Modificamos el estado a Approved para disparar el contador y ocultar la marca de agua
        qPartner.Status__c = 'Approved';
        update qPartner;
        Test.stopTest();

        // 3. VALIDACIÓN (Traemos Watermark_Shown__c para validar la cotización aprobada)
        Quote__c queriedPartner = [SELECT Discount__c, Watermark_Shown__c FROM Quote__c WHERE Id = :qPartner.Id];
        Quote__c queriedDist = [SELECT Discount__c FROM Quote__c WHERE Id = :qDist.Id];
        
        System.assertEquals(15, queriedPartner.Discount__c);
        System.assertEquals(5, queriedDist.Discount__c);
        
        // VALIDACIÓN INTEGRADA (Marca de agua): Al estar aprobada, pasa a false
        System.assertEquals(false, queriedPartner.Watermark_Shown__c, 'La marca de agua debe ser FALSE si está Approved');

        // VALIDACIÓN INTEGRADA (Contador): Validamos que el roll-up manual subió a 1 en la Opp
        Opportunity queriedOpp = [SELECT Number_Of_Approved_Quotes__c FROM Opportunity WHERE Id = :oppPartner.Id];
        System.assertEquals(1, queriedOpp.Number_Of_Approved_Quotes__c, 'La Oportunidad debe reflejar 1 cotización aprobada');
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

    @IsTest
    static void testQuoteDeleteAndUndelete() {
        Account acc = DataGenerator.createTestAccount('Delete Acc', 'Prospect', 'Low', true);
        Opportunity opp = DataGenerator.createTestOpportunity(acc.Id, 'Qualification', true);
        Quote__c q = DataGenerator.createTestQuote(opp.Id, acc.Id, 'Approved', true);

        Test.startTest();
        delete q;   
        undelete q; 
        Test.stopTest();
        
        System.assertNotEquals(null, q.Id, 'La cotización debería ser restaurada exitosamente');
    }
}