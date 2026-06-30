public with sharing class CreateContactsQueueable implements Queueable {
    
    private String source;

    public CreateContactsQueueable(String source) {
        this.source = source;
    }

    public void execute(QueueableContext context) {
        List<Contact> contactsToInsert = new List<Contact>();

        for (Integer i = 0; i < 500; i++) {
            contactsToInsert.add(new Contact(
                LastName = 'AsyncTest Contact ' + i,
                LeadSource = this.source,
                Async_Test_Data__c = true
            ));
        }

        if (!contactsToInsert.isEmpty()) {
            insert contactsToInsert;
        }

        // 🛡️ ESCUDO PROTECTOR: Evita que falle el test por intentar encadenar
        if (!Test.isRunningTest()) {
            System.enqueueJob(new ProcessContactsQueueable(contactsToInsert));
        }
    }
}