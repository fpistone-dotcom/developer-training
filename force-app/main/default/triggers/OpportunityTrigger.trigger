/* 
Whenever an Opportunity is created, default the Type field based on the related Account record's Type field:
If the Account record's Type is "Prospect", set the Opportunity record's Type to "New Customer"
Otherwise, set the Opportunity record's Type to "Existing Customer - Upgrade"

If an Opportunity changes to a "Closed Won" Stage and the related Account has a Type of "Prospect," update the related Account record's Type to "Customer - Direct."
*/ 

trigger OpportunityTrigger on Opportunity (before insert, after insert, before update, after update) {

    System.debug('<-------- Start OpportunityTrigger -------->');

    if (Trigger.isBefore && Trigger.isInsert) {

        System.debug('In OpportunityTrigger before insert context');
        
        // 1. Recolectar los IDs de las Cuentas
        Set<Id> accountIds = new Set<Id>();

        for (Opportunity opp : Trigger.new) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }

        // 2. Buscar las Cuentas con un solo SOQL usando un Map
        if (!accountIds.isEmpty()) {
            Map<Id, Account> accountMap = new Map<Id, Account>([
                SELECT Id, Type 
                FROM Account 
                WHERE Id IN :accountIds
            ]);
            
            // 3. Asignar el Type a la Oportunidad
            for (Opportunity opp : Trigger.new) {

                if (opp.AccountId != null && accountMap.containsKey(opp.AccountId)) {
                    
                    Account relatedAcc = accountMap.get(opp.AccountId);
                    
                    if (relatedAcc.Type == 'Prospect') {
                        opp.Type = 'New Customer';
                    } else {
                        opp.Type = 'Existing Customer - Upgrade';
                    }
                }
            }
        }
    } 
    

    else if (Trigger.isAfter && Trigger.isInsert) {
        System.debug('In OpportunityTrigger after insert context');
    } else if (Trigger.isBefore && Trigger.isUpdate) {
        System.debug('In OpportunityTrigger before update context');
    } 
    
    
    else if (Trigger.isAfter && Trigger.isUpdate) {

        System.debug('In OpportunityTrigger after update context');
        
        Set<Id> accountIdsToUpdate = new Set<Id>();

        for (Opportunity opp : Trigger.new) {
            Opportunity oldOpp = Trigger.oldMap.get(opp.Id);
            
            if (opp.StageName == 'Closed Won' && oldOpp.StageName != 'Closed Won' && opp.AccountId != null) {
                accountIdsToUpdate.add(opp.AccountId);
            }
        }

        if (!accountIdsToUpdate.isEmpty()) {
            List<Account> accountsToUpdate = new List<Account>();
            
            for (Account acc : [SELECT Id, Type FROM Account WHERE Id IN :accountIdsToUpdate AND Type = 'Prospect']) {
                
                acc.Type = 'Customer - Direct'; 
                accountsToUpdate.add(acc);      
            }
            
            if (!accountsToUpdate.isEmpty()) {
                update accountsToUpdate;
            }
        }
    } 

    System.debug('<-------- End OpportunityTrigger -------->');
}
