/* 
If the Account record's Type field changes, update the Type field accordingly on all child Opportunity records that are not in a "Closed Won" or "Closed Lost" Stage.
 */

trigger AccountTrigger on Account (before insert, after insert, before update, after update) {

    System.debug('<-------- Start AccountTrigger -------->');

    // Como vamos a actualizar OTROS registros (Oportunidades), usamos After Update
    if (Trigger.isAfter && Trigger.isUpdate) {
        System.debug('In AccountTrigger after update context');
        
        // --- REQUISITO B ---
        
        // PASO 1. Recolectar los IDs de las Cuentas cuyo Type realmente cambió
        Set<Id> changedAccountIds = new Set<Id>();
        
        for (Account acc : Trigger.new) {
            Account oldAcc = Trigger.oldMap.get(acc.Id); // Buscamos la versión anterior
            
            // Preguntamos: ¿El Type de ahora es distinto al Type viejo?
            if (acc.Type != oldAcc.Type) {
                changedAccountIds.add(acc.Id);
            }
        }

        // PASO 2. Si hay cuentas que cambiaron, buscar sus Oportunidades abiertas
        if (!changedAccountIds.isEmpty()) {
            
            // Nuestra "Caja de Envíos" para mandar a la base de datos
            List<Opportunity> oppsToUpdate = new List<Opportunity>();
            
            // Hacemos el SOQL pidiendo las Oportunidades hijas que NO estén cerradas
            List<Opportunity> childOpps = [
                SELECT Id, AccountId, Type
                FROM Opportunity
                WHERE AccountId IN :changedAccountIds
                  AND StageName != 'Closed Won'
                  AND StageName != 'Closed Lost'
            ];

            // PASO 3. Asignar el nuevo Type a las Oportunidades
            for (Opportunity opp : childOpps) {
                
                // Usamos Trigger.newMap (nuestro casillero) para ver el NUEVO Type de la cuenta
                Account parentAcc = Trigger.newMap.get(opp.AccountId); 
                
                if (parentAcc.Type == 'Prospect' && opp.Type != 'New Customer') {
                    opp.Type = 'New Customer';
                } else {
                    opp.Type = 'Existing Customer - Upgrade';
                }
                
                // Metemos la Oportunidad ya modificada en la caja
                oppsToUpdate.add(opp); 
            }

            // PASO 4. Mandamos el camión de mudanzas con los cambios
            if (!oppsToUpdate.isEmpty()) {
                update oppsToUpdate; 
            }
        }
        // --- FIN REQUISITO B ---
        
    } 

    System.debug('<-------- End AccountTrigger -------->');
}