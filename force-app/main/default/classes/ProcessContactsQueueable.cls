public with sharing class ProcessContactsQueueable implements Queueable {
    
    private List<Contact> contactsToProcess;

    // 1. El constructor acepta la lista de contactos (sObjects) que le pase el robot anterior
    public ProcessContactsQueueable(List<Contact> contacts) {
        this.contactsToProcess = contacts;
    }

    public void execute(QueueableContext context) {
        List<Contact> currentChunk = new List<Contact>();
        List<Contact> remainingContacts = new List<Contact>();

        // 2. Separación lógica: Mandamos los primeros 100 a procesar y el resto a la lista de remanentes
        for (Integer i = 0; i < contactsToProcess.size(); i++) {
            if (i < 100) {
                currentChunk.add(contactsToProcess[i]);
            } else {
                remainingContacts.add(contactsToProcess[i]);
            }
        }

        // 3. Fabricamos las Tareas (Tasks) para los 100 contactos de este turno
        List<Task> tasksToInsert = new List<Task>();
        for (Contact con : currentChunk) {
            tasksToInsert.add(new Task(
                WhoId = con.Id,                          // Asociamos la tarea al contacto
                Async_Test_Data__c = true,               // Sello en el checkbox de Actividad
                Subject = 'Call and verify async data',  // Campo obligatorio
                Status = 'Not Started',                  // Campo obligatorio
                Priority = 'Normal'                      // Campo obligatorio
            ));
        }

        // Insertamos en la base de datos las 100 tareas juntas
        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }

        // 4. Si quedan contactos Y NO estamos en un Test, nos clonamos
        if (!remainingContacts.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new ProcessContactsQueueable(remainingContacts));
        }
    }
}