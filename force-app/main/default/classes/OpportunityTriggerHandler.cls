public with sharing class OpportunityTriggerHandler {

    // --- ROUTING METHODS ---

    public static void beforeInsert(List<Opportunity> newList) {
        defaultOpportunityType(newList);
    }

    public static void afterUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        updateRelatedAccount(newList, oldMap);

        pushChangesToDraftQuotes(newList, oldMap);

        updateUserWonOpportunitiesCount(newList, oldMap);
    }


    // --- HELPER METHODS ---

    // Requirement 2.6.1 and 2.6.4:    
    private static void defaultOpportunityType(List<Opportunity> newList) {
        
        Set<Id> accountIds = new Set<Id>();
        
        for (Opportunity opp : newList) { 
            // Direct default assignment of Customer Type on creation
            opp.Customer_Type__c = 'End Customer'; 

            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
        
        if (!accountIds.isEmpty()) {
            // Add Rating to the Account SOQL query
            Map<Id, Account> accountMap = new Map<Id, Account>([
                SELECT Id, Type, Rating FROM Account WHERE Id IN :accountIds
            ]);
            
            for (Opportunity opp : newList) {
                if (opp.AccountId != null && accountMap.containsKey(opp.AccountId)) {
                    Account relatedAcc = accountMap.get(opp.AccountId);
                    
                    // Existing logic for Opportunity Type
                    if (relatedAcc.Type == 'Prospect') {
                        opp.Type = 'New Customer';
                    } else {
                        opp.Type = 'Existing Customer - Upgrade';
                    }

                    // Evaluate Account Rating to define Opportunity Priority
                    if (relatedAcc.Rating == 'Hot') {
                        opp.Priority__c = 'High';
                    } else if (relatedAcc.Rating == 'Warm') {
                        opp.Priority__c = 'Medium';
                    } else if (relatedAcc.Rating == 'Cold') {
                        opp.Priority__c = 'Low';
                    }
                }
            }
        }
    }

    private static void updateRelatedAccount(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        
        // Requirement C: Update Account when Opportunity changes to Closed Won
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

    // Requirement 2.6.2 and 2.6.4:
    // If Ship To Override, Customer Type or Priority changes, push updates to Draft Quotes.
    private static void pushChangesToDraftQuotes(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        Set<Id> changedOppIds = new Set<Id>();

        // Step 1: Filter Opportunities where any of the 3 key fields changed
        for (Opportunity opp : newList) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            
            if (opp.Ship_To_Override__c != oldOpp.Ship_To_Override__c ||
                opp.Customer_Type__c != oldOpp.Customer_Type__c ||
                opp.Priority__c != oldOpp.Priority__c) {
                
                changedOppIds.add(opp.Id);
            }
        }

        // If no Opportunity changed these fields, exit early
        if (changedOppIds.isEmpty()) return;

        // Step 2: Query all child Quotes for those Opportunities in Draft
        List<Quote__c> childQuotesToUpdate = [
            SELECT Id 
            FROM Quote__c 
            WHERE Opportunity__c IN :changedOppIds 
            AND Status__c = 'Draft'
        ];

        // Step 3: Perform bulk DML to touch them
        if (!childQuotesToUpdate.isEmpty()) {
            update childQuotesToUpdate; 
            // This triggers the QuoteTrigger in update mode,
        }
    }

    // Requirement 4.1: Collect Owner IDs when Opportunity changes to Closed Won
    private static void updateUserWonOpportunitiesCount(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        List<Id> ownerIds = new List<Id>();
        
        for (Opportunity opp : newList) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            
            if (opp.StageName == 'Closed Won' && oldOpp.StageName != 'Closed Won') {
                ownerIds.add(opp.OwnerId);
            }
        }
        
        if (!ownerIds.isEmpty()) {
            // Despachamos el trabajo al hilo asincrónico futuro
            incrementUserWonOpportunities(ownerIds);
        }
    }

    //FUTURE METHOD: Runs in a separate thread to update Setup Objects (User) and avoid Mixed DML
    @Future
    public static void incrementUserWonOpportunities(List<Id> ownerIds) {
        Map<Id, Integer> ownerIncrementMap = new Map<Id, Integer>();
        for (Id ownerId : ownerIds) {
            if (!ownerIncrementMap.containsKey(ownerId)) {
                ownerIncrementMap.put(ownerId, 0);
            }
            ownerIncrementMap.put(ownerId, ownerIncrementMap.get(ownerId) + 1);
        }

        List<User> usersToUpdate = [SELECT Id, Number_of_Won_Opportunities__c FROM User WHERE Id IN :ownerIncrementMap.keySet()];
        for (User u : usersToUpdate) {
            Decimal currentWon = u.Number_of_Won_Opportunities__c != null ? u.Number_of_Won_Opportunities__c : 0;
            u.Number_of_Won_Opportunities__c = currentWon + ownerIncrementMap.get(u.Id);
        }
        
        update usersToUpdate;
    }
}