@IsTest
public with sharing class ContactQueueableTest {

    @IsTest
    static void testFullQueueableFlow() {
        // 1. EJECUCIÓN: Lanzamos el primer robot
        Test.startTest();
        System.enqueueJob(new CreateContactsQueueable('Partner Referral'));
        Test.stopTest(); 

        // 2. VALIDACIÓN: Comprobamos que fabricó los 500 contactos con su origen correcto
        List<Contact> createdContacts = [
            SELECT Id, LeadSource, Async_Test_Data__c 
            FROM Contact 
            WHERE Async_Test_Data__c = true
        ];
        
        System.assertEquals(500, createdContacts.size(), 'Debieron crearse 500 contactos.');
        System.assertEquals('Partner Referral', createdContacts[0].LeadSource, 'El origen debe ser Partner Referral.');
    }

    @IsTest
    static void testProcessQueueableDirectly() {
        // Este método tuyo ya funcionaba perfecto y da Cobertura al segundo Queueable
        List<Contact> testContacts = new List<Contact>();
        for(Integer i=0; i<50; i++) {
            testContacts.add(new Contact(LastName = 'Test ' + i));
        }
        insert testContacts;

        Test.startTest();
        System.enqueueJob(new ProcessContactsQueueable(testContacts));
        Test.stopTest();

        List<Task> tasks = [SELECT Id FROM Task WHERE Async_Test_Data__c = true];
        System.assertEquals(50, tasks.size(), 'Se debieron crear 50 tareas para los contactos pasados.');
    }
}