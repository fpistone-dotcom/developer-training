public with sharing class OpportunityTriggerHandler {

    // --- MÉTODOS DE RUTEO ---

    public static void beforeInsert(List<Opportunity> newList) {
        defaultOpportunityType(newList);
    }

    public static void afterUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        updateRelatedAccount(newList, oldMap);
    }


    // --- MÉTODOS HELPER ---

    private static void defaultOpportunityType(List<Opportunity> newList) {
        
        // Requisito A: Asignar Type basado en el Account relacionado
        Set<Id> accountIds = new Set<Id>();
        
        for (Opportunity opp : newList) { 
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
        
        if (!accountIds.isEmpty()) {
            Map<Id, Account> accountMap = new Map<Id, Account>([
                SELECT Id, Type FROM Account WHERE Id IN :accountIds
            ]);
            
            for (Opportunity opp : newList) {
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

    private static void updateRelatedAccount(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        
        // Requisito C: Actualizar Account si la Opp cambia a Closed Won
        Set<Id> accountIdsToUpdate = new Set<Id>();
        
        for (Opportunity opp : newList) {
            Opportunity oldOpp = oldMap.get(opp.Id); 
            
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
}