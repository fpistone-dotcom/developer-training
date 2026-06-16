/*
3) Whenever an Invitation record is created, default the following field:

If the Event Type is "Virtual", update the Address field to "Online"
Populate the Invitation record's Description field with the date in which the Invitation was created and the Full Name of the User that created the record


4)Whenever an Invitation record's Event Type has changed, update the Address field according to the new Event Type:

Conference -> "International Conference Center, 123 Main St."
Party -> "Executive Suite, Big Skyscraper 5"
Virtual -> "Virtual Meeting Room"
Meeting -> "Fancy Boardroom, High Tech Campus Drive"


5) Whenever the Invitation record's Create Reminder Task field is changed from false to true, create a new Task record and populate the following fields:

Subject: Populate with "Remember to invite " plus the related Contact record's Name field
OwnerId: Populate with the same User that created the Invitation
Priority: If the Event Date is less than 1 week away, then set to "High". Otherwise, set to "Normal"
Status: Set to "Not Started"
WhatId: Set to the same Account record related to the Invitation


6) Whenever the Invitation is created and when the Invitation is updated, check to ensure that the Account field on the Invitation is related to the same 
Account that the Contact is related to. If not, update the Invitation record's Account field to the same Account record related to the Contact.
*/

public with sharing class InvitationTriggerHandler {

    // --- MÉTODOS DE RUTEO PÚBLICOS ---

    public static void beforeInsert(List<Invitation__c> newList) {
        //3)
        setInvitationDefaults(newList);

        //6)
        alignAccountsWithContacts(newList, null);
    }
    public static void afterInsert(List<Invitation__c> newList) {
        // Aquí irá la lógica post-creación si se necesita
    }
    public static void beforeUpdate(List<Invitation__c> newList, Map<Id, Invitation__c> oldMap) {
        //4)
        handleEventTypeChange(newList, oldMap);

        //6)
        alignAccountsWithContacts(newList, oldMap);
    }
    public static void afterUpdate(List<Invitation__c> newList, Map<Id, Invitation__c> oldMap) {
        //5)
        createReminderTasks(newList, oldMap);
    }


    // --- MÉTODOS DE LÓGICA PRIVADOS (Los iremos llenando) ---

    //3)
    private static void setInvitationDefaults(List<Invitation__c> newList) {
    String currentUserName = UserInfo.getName();
    Date todayDate = Date.today();

        for (Invitation__c inv : newList) {
            // Si el tipo es Virtual, la dirección es Online
            if (inv.Event_Type__c == 'Virtual') {
                inv.Address__c = 'Online';
            }

            // Llenamos la descripción con la fecha de hoy y tu nombre
            inv.Description__c = 'Created Date: ' + todayDate.format() + ' | Created By: ' + currentUserName;
        }
    }

    //4)
    private static void handleEventTypeChange(List<Invitation__c> newList, Map<Id, Invitation__c> oldMap) {
        for (Invitation__c inv : newList) {
            // Obtenemos la versión del registro antes de que el usuario lo editara
            Invitation__c oldInv = oldMap.get(inv.Id);
            
            //Solo actuamos si el Event Type cambió
            if (inv.Event_Type__c != oldInv.Event_Type__c) {
                
                if (inv.Event_Type__c == 'Conference') {
                    inv.Address__c = 'International Conference Center, 123 Main St.';
                } else if (inv.Event_Type__c == 'Party') {
                    inv.Address__c = 'Executive Suite, Big Skyscraper 5';
                } else if (inv.Event_Type__c == 'Virtual') {
                    inv.Address__c = 'Virtual Meeting Room';
                } else if (inv.Event_Type__c == 'Meeting') {
                    inv.Address__c = 'Fancy Boardroom, High Tech Campus Drive';
                }
                
            }
        }
    }

    //5)
    private static void createReminderTasks(List<Invitation__c> newList, Map<Id, Invitation__c> oldMap) {
    List<Task> tasksToInsert = new List<Task>();
    Set<Id> contactIds = new Set<Id>();

        // PASO 1: Identificar qué invitaciones cambiaron el checkbox de false a true
        for (Invitation__c inv : newList) {
            Invitation__c oldInv = oldMap.get(inv.Id);
            
            if (inv.Create_Reminder_Task__c == true && oldInv.Create_Reminder_Task__c == false) {
                if (inv.Contact__c != null) {
                    contactIds.add(inv.Contact__c);
                }
            }
        }

        // Si nadie activó la casilla, terminamos temprano y ahorramos recursos
        if (contactIds.isEmpty()) {
            return;
        }

        // PASO 2: Buscar los nombres de los contactos en una sola consulta estructurada
        Map<Id, Contact> contactMap = new Map<Id, Contact>([
            SELECT Id, Name FROM Contact WHERE Id IN :contactIds
        ]);

        // Preparamos la fecha límite (hoy + 7 días) para evaluar la prioridad
        Date oneWeekFromNow = Date.today().addDays(7);

        // PASO 3: Construir las tareas con los datos requeridos
        for (Invitation__c inv : newList) {
            Invitation__c oldInv = oldMap.get(inv.Id);
            
            if (inv.Create_Reminder_Task__c == true && oldInv.Create_Reminder_Task__c == false) {
                Task newTask = new Task();
                
                // Asunto dinámico con el nombre obtenido del mapa
                String contactName = contactMap.containsKey(inv.Contact__c) ? contactMap.get(inv.Contact__c).Name : '';
                newTask.Subject = 'Remember to invite ' + contactName;
                
                // Asignamos el Owner como el creador original de la invitación
                newTask.OwnerId = inv.CreatedById;
                
                // Estado por defecto
                newTask.Status = 'Not Started';
                
                // Relacionamos la tarea con la cuenta de la invitación
                newTask.WhatId = inv.Account__c;
                
                // Cálculo de Prioridad: si falta menos de una semana es High, sino Normal
                if (inv.Event_Date__c != null && inv.Event_Date__c < oneWeekFromNow) {
                    newTask.Priority = 'High';
                } else {
                    newTask.Priority = 'Normal';
                }
                
                tasksToInsert.add(newTask);
            }
        }

        // PASO 4: Guardar todas las tareas nuevas de un solo golpe en la base de datos
        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

    //6)
    private static void alignAccountsWithContacts(List<Invitation__c> newList, Map<Id, Invitation__c> oldMap) {
    Set<Id> contactIds = new Set<Id>();

        // 1. Recolectamos los IDs de los contactos que necesitamos verificar
        for (Invitation__c inv : newList) {
            if (inv.Contact__c != null) {
                // Solo verificamos si es creación (oldMap == null) o si el contacto cambió
                if (oldMap == null || inv.Contact__c != oldMap.get(inv.Id).Contact__c) {
                    contactIds.add(inv.Contact__c);
                }
            }
        }

        if (contactIds.isEmpty()) return;

        // 2. Consulta SOQL masiva (bulkificada) para obtener las cuentas de esos contactos
        Map<Id, Contact> contactMap = new Map<Id, Contact>([
            SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds
        ]);

        // 3. Aplicamos la corrección
        for (Invitation__c inv : newList) {
            if (inv.Contact__c != null && contactMap.containsKey(inv.Contact__c)) {
                Id correctAccountId = contactMap.get(inv.Contact__c).AccountId;
                
                // Si la cuenta no coincide, la corregimos
                if (inv.Account__c != correctAccountId) {
                    inv.Account__c = correctAccountId;
                }
            }
        }
    }
}

